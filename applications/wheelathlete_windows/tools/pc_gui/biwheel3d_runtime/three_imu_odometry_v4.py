"""Generic three-IMU wheelchair odometry v4.

V4 is deliberately protocol-agnostic: runtime inference accepts synchronized
left/right/center IMU data and a frozen development model only.  C3D, athlete,
trial and course identifiers are not runtime inputs.
"""
from __future__ import annotations

from dataclasses import dataclass, replace

import numpy as np
from scipy.signal import savgol_filter

try:
    from .three_imu_odometry_v2 import (
        IMUSynchronized,
        ThreeIMUCalibration,
        ThreeIMUConfig,
        ThreeIMUEstimate,
        _odd_window,
        estimate_trajectory,
        integrate_se2,
        raw_predictors,
    )
except ImportError:
    from biwheel3d.three_imu_odometry_v2 import (
        IMUSynchronized,
        ThreeIMUCalibration,
        ThreeIMUConfig,
        ThreeIMUEstimate,
        _odd_window,
        estimate_trajectory,
        integrate_se2,
        raw_predictors,
    )

FEATURE_COUNT = 12


def generic_v4_config() -> ThreeIMUConfig:
    """Sep-9-development-selected generic v3 backbone, without protocol logic."""
    return replace(
        ThreeIMUConfig(),
        center_weight_straight=0.95,
        center_weight_turn=1.00,
        center_weight_disagreement_bonus=0.05,
        straight_deadband_deg_s=0.0,
    )


@dataclass(frozen=True)
class GenericResidualModel:
    """Small bounded rate-residual model fitted on development data only."""

    speed_coeff: tuple[float, ...]
    yaw_coeff: tuple[float, ...]
    feature_scale: tuple[float, ...]
    speed_clip_fraction: float = 0.15
    yaw_clip_deg_s: float = 8.0
    disagreement_guard_deg_s: float = 30.0
    speed_turn_attenuation: float = 0.80
    yaw_persistence_floor: float = 0.25

    @classmethod
    def zeros(cls) -> "GenericResidualModel":
        return cls(
            speed_coeff=(0.0,) * FEATURE_COUNT,
            yaw_coeff=(0.0,) * FEATURE_COUNT,
            feature_scale=(1.0,) * FEATURE_COUNT,
        )

    def validate(self) -> None:
        if not (
            len(self.speed_coeff)
            == len(self.yaw_coeff)
            == len(self.feature_scale)
            == FEATURE_COUNT
        ):
            raise ValueError(f"v4 residual model requires {FEATURE_COUNT} features")
        if np.any(np.asarray(self.feature_scale, dtype=float) <= 0.0):
            raise ValueError("v4 feature scales must be positive")


def _turn_persistence(yaw_rate: np.ndarray, *, sample_rate_hz: float) -> np.ndarray:
    """Return 0..1 local same-direction turn persistence from yaw alone."""
    yaw = np.asarray(yaw_rate, dtype=float)
    if len(yaw) < 3:
        return np.ones_like(yaw)
    window = _odd_window(1.0, sample_rate_hz, len(yaw), minimum=5)
    kernel = np.ones(window, dtype=float) / float(window)
    signed = np.convolve(yaw, kernel, mode="same")
    magnitude = np.convolve(np.abs(yaw), kernel, mode="same")
    return np.clip(np.abs(signed) / np.maximum(magnitude, 1e-9), 0.0, 1.0)


def _speed_turn_confidence(
    turn_strength: np.ndarray,
    persistence: np.ndarray,
    *,
    attenuation: float,
) -> np.ndarray:
    """Keep correction on sustained turns; attenuate only strong reversals."""
    turn = np.clip(np.asarray(turn_strength, dtype=float), 0.0, 1.0)
    persist = np.clip(np.asarray(persistence, dtype=float), 0.0, 1.0)
    amount = np.clip(float(attenuation), 0.0, 1.0)
    return 1.0 - amount * turn * (1.0 - persist)


def _center_accel_features(
    imu: IMUSynchronized,
    predictors: dict[str, np.ndarray],
    base_speed: np.ndarray,
    config: ThreeIMUConfig,
) -> tuple[np.ndarray, np.ndarray]:
    """Return IMU-only forward acceleration and lateral acceleration magnitude."""
    accel = np.asarray(imu.raw["C"][:, :3], dtype=float)
    gravity = np.asarray(predictors["center_gravity_axis"], dtype=float)
    horizontal = accel - np.outer(accel @ gravity, gravity)
    window = _odd_window(0.21, config.sample_rate_hz, len(imu.t), minimum=5)
    if len(horizontal) >= 5:
        horizontal = savgol_filter(horizontal, window, 2, axis=0, mode="interp")

    dt = float(np.median(np.diff(imu.t))) if len(imu.t) > 1 else 1.0 / config.sample_rate_hz
    wheel_acc = np.gradient(base_speed, dt)
    moving = ~np.asarray(predictors["stationary"], dtype=bool)
    if moving.any():
        threshold = float(np.quantile(np.abs(wheel_acc[moving]), 0.55))
        dynamic = moving & (np.abs(wheel_acc) >= threshold)
    else:
        dynamic = moving
    direction = (
        np.sum(horizontal[dynamic] * wheel_acc[dynamic, None], axis=0)
        if dynamic.any()
        else np.array([1.0, 0.0, 0.0])
    )
    direction -= np.dot(direction, gravity) * gravity
    norm = float(np.linalg.norm(direction))
    if not np.isfinite(norm) or norm <= 1e-9:
        direction = np.array([1.0, 0.0, 0.0])
        direction -= np.dot(direction, gravity) * gravity
        norm = max(float(np.linalg.norm(direction)), 1e-9)
    direction /= norm

    stationary = np.asarray(predictors["stationary"], dtype=bool)
    gravity_mag = (
        float(np.median(np.linalg.norm(accel[stationary], axis=1)))
        if stationary.any()
        else float(np.median(np.linalg.norm(accel, axis=1)))
    )
    scale = 9.80665 / max(gravity_mag, 1e-9)
    forward = (horizontal @ direction) * scale
    horizontal_mps2 = horizontal * scale
    lateral_sq = np.maximum(
        np.sum(np.square(horizontal_mps2), axis=1) - np.square(forward), 0.0
    )
    lateral = np.sqrt(lateral_sq)
    if len(forward) >= 5:
        forward = savgol_filter(forward, window, 2, mode="interp")
        lateral = savgol_filter(lateral, window, 2, mode="interp")
    return forward, lateral


def generic_motion_features(
    imu: IMUSynchronized,
    calibration: ThreeIMUCalibration,
    *,
    config: ThreeIMUConfig | None = None,
) -> tuple[ThreeIMUEstimate, np.ndarray, np.ndarray]:
    """Build condition-free physical features from L/R/C IMU motion."""
    cfg = config or generic_v4_config()
    base = estimate_trajectory(imu, calibration, config=cfg)
    p = raw_predictors(imu, config=cfg)
    stationary = np.asarray(p["stationary"], dtype=bool)
    t = np.asarray(imu.t, dtype=float)
    dt = float(np.median(np.diff(t))) if len(t) > 1 else 1.0 / cfg.sample_rate_hz

    speed = np.asarray(base.speed, dtype=float)
    yaw = np.asarray(base.yaw_rate, dtype=float)
    center = np.asarray(base.center_yaw_rate, dtype=float)
    wheel = np.asarray(base.wheel_yaw_rate, dtype=float)
    disagreement = center - wheel
    speed_acc = np.gradient(speed, dt)
    yaw_acc = np.gradient(yaw, dt)
    forward_acc, lateral_acc = _center_accel_features(imu, p, speed, cfg)

    features = np.column_stack(
        [
            speed,
            speed * np.abs(speed),
            speed_acc,
            yaw,
            center,
            wheel,
            disagreement,
            np.abs(disagreement),
            yaw_acc,
            forward_acc,
            lateral_acc,
            speed * yaw,
        ]
    )
    features[stationary] = 0.0
    features[~np.isfinite(features)] = 0.0
    return base, features, stationary


def estimate_trajectory_v4(
    imu: IMUSynchronized,
    calibration: ThreeIMUCalibration,
    *,
    model: GenericResidualModel | None = None,
    config: ThreeIMUConfig | None = None,
) -> ThreeIMUEstimate:
    """Estimate arbitrary planar motion from L/R/C IMU only."""
    cfg = config or generic_v4_config()
    frozen = model or GenericResidualModel.zeros()
    frozen.validate()
    base, features, stationary = generic_motion_features(imu, calibration, config=cfg)

    scales = np.asarray(frozen.feature_scale, dtype=float)
    z = features / scales[None, :]
    speed_residual = z @ np.asarray(frozen.speed_coeff, dtype=float)
    yaw_residual = z @ np.asarray(frozen.yaw_coeff, dtype=float)

    disagreement_deg_s = np.degrees(np.abs(base.center_yaw_rate - base.wheel_yaw_rate))
    guard = max(float(frozen.disagreement_guard_deg_s), 1e-6)
    disagreement_confidence = 1.0 / (1.0 + np.square(disagreement_deg_s / guard))

    # Wheel/accelerometer speed correction is least trustworthy during strong
    # turns (scrub + centripetal acceleration).  Yaw correction is most useful
    # on sustained turns and is conservatively attenuated on rapid reversals.
    turn_strength = np.clip(
        np.abs(np.degrees(base.yaw_rate)) / max(float(cfg.turn_scale_deg_s), 1e-6),
        0.0,
        1.0,
    )
    persistence = _turn_persistence(base.yaw_rate, sample_rate_hz=cfg.sample_rate_hz)
    speed_confidence = disagreement_confidence * _speed_turn_confidence(
        turn_strength,
        persistence,
        attenuation=frozen.speed_turn_attenuation,
    )
    persistence_floor = np.clip(float(frozen.yaw_persistence_floor), 0.0, 1.0)
    yaw_confidence = disagreement_confidence * (
        persistence_floor + (1.0 - persistence_floor) * persistence
    )
    speed_residual *= speed_confidence
    yaw_residual *= yaw_confidence

    speed_limit = float(frozen.speed_clip_fraction) * np.maximum(np.abs(base.speed), 0.25)
    speed_residual = np.clip(speed_residual, -speed_limit, speed_limit)
    yaw_limit = np.deg2rad(abs(float(frozen.yaw_clip_deg_s)))
    yaw_residual = np.clip(yaw_residual, -yaw_limit, yaw_limit)

    speed = np.asarray(base.speed, dtype=float) + speed_residual
    yaw = np.asarray(base.yaw_rate, dtype=float) + yaw_residual
    speed[stationary] = 0.0
    yaw[stationary] = 0.0
    xy, heading = integrate_se2(base.t, speed, yaw)

    quality = dict(base.quality)
    quality.update(
        {
            "v4_residual_applied": 1.0,
            "v4_speed_residual_rms_mps": float(np.sqrt(np.mean(np.square(speed_residual)))),
            "v4_yaw_residual_rms_deg_s": float(
                np.degrees(np.sqrt(np.mean(np.square(yaw_residual))))
            ),
            "v4_mean_speed_confidence": float(np.mean(speed_confidence)),
            "v4_mean_yaw_confidence": float(np.mean(yaw_confidence)),
            "v4_turn_persistence_mean": float(np.mean(persistence)),
            "v4_ood_guard": float(np.mean(disagreement_confidence) < 0.75),
        }
    )
    return replace(base, speed=speed, yaw_rate=yaw, xy=xy, heading=heading, quality=quality)
