"""Generic three-IMU wheelchair odometry v5 research candidate.

V5 remains protocol-agnostic and C3D-free at runtime.  Development and model
selection are restricted to the locked September-9 development partition.
"""
from __future__ import annotations

from dataclasses import dataclass, replace

import numpy as np

try:
    from .three_imu_odometry_v2 import (
        IMUSynchronized,
        ThreeIMUCalibration,
        ThreeIMUConfig,
        ThreeIMUEstimate,
        _smooth,
        anchor_pause_bounded_uturns,
        integrate_se2,
        pause_bias_trace,
        raw_predictors,
        straight_yaw_bias_trace,
    )
    from .three_imu_odometry_v4 import (
        FEATURE_COUNT,
        _turn_persistence,
        generic_motion_features,
        generic_v4_config,
    )
except ImportError:
    from biwheel3d.three_imu_odometry_v2 import (
        IMUSynchronized,
        ThreeIMUCalibration,
        ThreeIMUConfig,
        ThreeIMUEstimate,
        _smooth,
        anchor_pause_bounded_uturns,
        integrate_se2,
        pause_bias_trace,
        raw_predictors,
        straight_yaw_bias_trace,
    )
    from biwheel3d.three_imu_odometry_v4 import (
        FEATURE_COUNT,
        _turn_persistence,
        generic_motion_features,
        generic_v4_config,
    )

# XIAO/LSM6DS3 virtual raw gyro conversion used by the acquisition/runtime
# contract.  Attitude propagation needs the physical sensor scale, not the
# separately fitted optical yaw gain.
CENTER_GYRO_RADPS_PER_COUNT = float(np.deg2rad(0.06103515625))
V5_EXPERT_COUNT = 3


@dataclass(frozen=True)
class V5MotionExpertModel:
    """Small bounded mixture of IMU-motion residual experts."""

    feature_scale: tuple[float, ...]
    speed_coeff: tuple[tuple[float, ...], ...]
    yaw_coeff: tuple[tuple[float, ...], ...]
    speed_clip_fraction: float = 0.10
    yaw_clip_deg_s: float = 4.0
    disagreement_guard_deg_s: float = 25.0

    @classmethod
    def zeros(cls) -> "V5MotionExpertModel":
        row = (0.0,) * FEATURE_COUNT
        return cls(
            feature_scale=(1.0,) * FEATURE_COUNT,
            speed_coeff=(row,) * V5_EXPERT_COUNT,
            yaw_coeff=(row,) * V5_EXPERT_COUNT,
        )

    def validate(self) -> None:
        scale = np.asarray(self.feature_scale, dtype=float)
        speed = np.asarray(self.speed_coeff, dtype=float)
        yaw = np.asarray(self.yaw_coeff, dtype=float)
        if scale.shape != (FEATURE_COUNT,):
            raise ValueError(f"v5 feature scale requires {FEATURE_COUNT} values")
        if speed.shape != (V5_EXPERT_COUNT, FEATURE_COUNT) or yaw.shape != speed.shape:
            raise ValueError(
                f"v5 motion experts require {V5_EXPERT_COUNT}x{FEATURE_COUNT} coefficients"
            )
        if not np.isfinite(scale).all() or np.any(scale <= 0.0):
            raise ValueError("v5 feature scales must be finite and positive")
        if not np.isfinite(speed).all() or not np.isfinite(yaw).all():
            raise ValueError("v5 expert coefficients must be finite")


def motion_gates(
    base: ThreeIMUEstimate,
    *,
    sample_rate_hz: float,
    turn_scale_deg_s: float,
) -> np.ndarray:
    """Return generic straight/sustained/alternating motion weights."""
    turn = np.clip(
        np.abs(np.degrees(base.yaw_rate)) / max(float(turn_scale_deg_s), 1e-6),
        0.0,
        1.0,
    )
    persistence = _turn_persistence(base.yaw_rate, sample_rate_hz=sample_rate_hz)
    gates = np.column_stack(
        [
            1.0 - turn,
            turn * persistence,
            turn * (1.0 - persistence),
        ]
    )
    return gates / np.maximum(np.sum(gates, axis=1, keepdims=True), 1e-9)


def _unit(vector: np.ndarray, fallback: np.ndarray) -> np.ndarray:
    norm = float(np.linalg.norm(vector))
    if not np.isfinite(norm) or norm <= 1e-12:
        return np.asarray(fallback, dtype=float).copy()
    return np.asarray(vector, dtype=float) / norm


def dynamic_center_vertical_axis(
    imu: IMUSynchronized,
    stationary: np.ndarray,
    *,
    gyro_scale_radps_per_count: float,
    sample_rate_hz: float = 100.0,
    accel_correction_tau_s: float = 0.60,
    accel_norm_tolerance_fraction: float = 0.20,
) -> np.ndarray:
    """Track the center sensor's instantaneous gravity axis without C3D.

    Gyro propagation carries orientation through dynamic motion while a slow,
    magnitude-gated accelerometer correction prevents long-term tilt drift.
    """
    accel = np.asarray(imu.raw["C"][:, :3], dtype=float)
    gyro_counts = np.asarray(imu.raw["C"][:, 3:6], dtype=float)
    stationary = np.asarray(stationary, dtype=bool)
    if accel.shape != gyro_counts.shape or len(accel) != len(imu.t):
        raise ValueError("center IMU arrays must be aligned Nx3 samples")
    if len(accel) == 0:
        return np.empty((0, 3), dtype=float)

    min_support = max(10, int(round(0.5 * float(sample_rate_hz))))
    support = stationary.copy()
    if int(support.sum()) < min_support:
        support = np.zeros(len(accel), dtype=bool)
        support[: min(len(accel), min_support)] = True
    initial_accel = np.median(accel[support], axis=0)
    initial_axis = _unit(initial_accel, np.array([1.0, 0.0, 0.0]))
    gravity_counts = float(np.median(np.linalg.norm(accel[support], axis=1)))
    if not np.isfinite(gravity_counts) or gravity_counts <= 1e-9:
        gravity_counts = float(np.median(np.linalg.norm(accel, axis=1)))
    if not np.isfinite(gravity_counts) or gravity_counts <= 1e-9:
        gravity_counts = 1.0

    cfg = ThreeIMUConfig(sample_rate_hz=float(sample_rate_hz))
    bias = np.column_stack(
        [
            pause_bias_trace(
                gyro_counts[:, axis],
                stationary,
                max_std=cfg.pause_bias_max_std_counts,
                min_samples=30,
            )
            for axis in range(3)
        ]
    )
    gyro = (gyro_counts - bias) * abs(float(gyro_scale_radps_per_count))

    axes = np.empty_like(accel, dtype=float)
    axes[0] = initial_axis
    tau = max(float(accel_correction_tau_s), 1e-3)
    tolerance = max(float(accel_norm_tolerance_fraction), 0.0)
    for index in range(1, len(accel)):
        dt = float(imu.t[index] - imu.t[index - 1])
        if not np.isfinite(dt) or dt <= 0.0:
            dt = 1.0 / max(float(sample_rate_hz), 1e-6)
        predicted = axes[index - 1] + np.cross(axes[index - 1], gyro[index - 1]) * dt
        predicted = _unit(predicted, axes[index - 1])

        a = accel[index]
        a_norm = float(np.linalg.norm(a))
        trustworthy = (
            np.isfinite(a_norm)
            and a_norm > 1e-9
            and abs(a_norm - gravity_counts) <= tolerance * gravity_counts
        )
        if trustworthy:
            measured = a / a_norm
            if float(np.dot(measured, predicted)) < 0.0:
                measured = -measured
            alpha = 1.0 - np.exp(-dt / tau)
            if stationary[index]:
                alpha = max(alpha, min(1.0, 4.0 * alpha))
            predicted = _unit((1.0 - alpha) * predicted + alpha * measured, predicted)
        axes[index] = predicted
    return axes


def estimate_trajectory_v5(
    imu: IMUSynchronized,
    calibration: ThreeIMUCalibration,
    *,
    model: V5MotionExpertModel | None = None,
    config: ThreeIMUConfig | None = None,
) -> ThreeIMUEstimate:
    """Estimate generic planar motion with bounded IMU-motion experts only."""
    cfg = config or generic_v4_config()
    frozen = model or V5MotionExpertModel.zeros()
    frozen.validate()
    base, features, stationary = generic_motion_features(imu, calibration, config=cfg)
    gates = motion_gates(
        base,
        sample_rate_hz=cfg.sample_rate_hz,
        turn_scale_deg_s=cfg.turn_scale_deg_s,
    )

    scale = np.asarray(frozen.feature_scale, dtype=float)
    z = features / scale[None, :]
    speed_coeff = np.asarray(frozen.speed_coeff, dtype=float)
    yaw_coeff = np.asarray(frozen.yaw_coeff, dtype=float)
    speed_residual = np.sum(gates * (z @ speed_coeff.T), axis=1)
    yaw_residual = np.sum(gates * (z @ yaw_coeff.T), axis=1)

    disagreement_deg_s = np.degrees(np.abs(base.center_yaw_rate - base.wheel_yaw_rate))
    confidence = 1.0 / (
        1.0
        + np.square(
            disagreement_deg_s / max(float(frozen.disagreement_guard_deg_s), 1e-6)
        )
    )
    speed_residual *= confidence
    yaw_residual *= confidence
    speed_limit = float(frozen.speed_clip_fraction) * np.maximum(np.abs(base.speed), 0.25)
    speed_residual = np.clip(speed_residual, -speed_limit, speed_limit)
    yaw_limit = np.deg2rad(abs(float(frozen.yaw_clip_deg_s)))
    yaw_residual = np.clip(yaw_residual, -yaw_limit, yaw_limit)

    speed = np.asarray(base.speed, dtype=float) + speed_residual
    yaw_rate = np.asarray(base.yaw_rate, dtype=float) + yaw_residual
    speed[stationary] = 0.0
    yaw_rate[stationary] = 0.0
    xy, heading = integrate_se2(base.t, speed, yaw_rate)

    quality = dict(base.quality)
    quality.update(
        {
            "v5_motion_experts": 1.0,
            "v5_speed_residual_rms_mps": float(
                np.sqrt(np.mean(np.square(speed_residual)))
            ),
            "v5_yaw_residual_rms_deg_s": float(
                np.degrees(np.sqrt(np.mean(np.square(yaw_residual))))
            ),
            "v5_mean_expert_confidence": float(np.mean(confidence)),
            "v5_straight_gate_mean": float(np.mean(gates[:, 0])),
            "v5_sustained_turn_gate_mean": float(np.mean(gates[:, 1])),
            "v5_alternating_turn_gate_mean": float(np.mean(gates[:, 2])),
        }
    )
    return replace(
        base,
        speed=speed,
        yaw_rate=yaw_rate,
        xy=xy,
        heading=heading,
        quality=quality,
    )
