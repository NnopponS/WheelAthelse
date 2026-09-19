"""SOF-3IMU: spin-orthogonal wheel-frame yaw fusion.

The v7 research method adapts the constrained wheel-IMU frame-rotation geometry
from wheelchair-sport literature to WheelAthlete's mounting: wheel spin is raw
gyro Z and wheelchair-frame yaw lives in the orthogonal X/Y plane.  Runtime
uses synchronized L/R/C IMU only; optical reference and protocol identity are
not part of the API.
"""
from __future__ import annotations

from dataclasses import dataclass, replace

import numpy as np
from scipy.signal import butter, sosfiltfilt

from .three_imu_odometry_v2 import (
    IMUSynchronized,
    ThreeIMUCalibration,
    ThreeIMUEstimate,
    detect_stationary,
    integrate_se2,
    pause_bias_trace,
)
from .three_imu_odometry_v4 import generic_motion_features, generic_v4_config

SAMPLE_RATE_HZ = 100.0


@dataclass(frozen=True)
class SOFFusionModel:
    """Low-capacity slow-bias fusion settings selected on development data."""

    hub_correction_weight: float = 0.5
    bias_tau_s: float = 2.0
    disagreement_guard_deg_s: float = 12.0
    turn_threshold_deg_s: float = 5.0
    correction_clip_deg_s: float = 1.0

    def validate(self) -> None:
        if not 0.0 <= float(self.hub_correction_weight) <= 1.0:
            raise ValueError("hub_correction_weight must be in [0, 1]")
        if float(self.bias_tau_s) <= 0.0:
            raise ValueError("bias_tau_s must be positive")
        if float(self.disagreement_guard_deg_s) <= 0.0:
            raise ValueError("disagreement_guard_deg_s must be positive")
        if float(self.turn_threshold_deg_s) < 0.0:
            raise ValueError("turn_threshold_deg_s must be non-negative")
        if float(self.correction_clip_deg_s) <= 0.0:
            raise ValueError("correction_clip_deg_s must be positive")


def _slope(x: np.ndarray, y: np.ndarray) -> float:
    denom = float(np.dot(x, x))
    return float(np.dot(x, y) / denom) if denom > 1e-9 else 0.0


def _lowpass_wheel_plane(values: np.ndarray, sample_rate_hz: float) -> np.ndarray:
    values = np.asarray(values, dtype=float)
    if len(values) <= 30:
        return values.copy()
    cutoff_hz = min(6.0, 0.45 * float(sample_rate_hz))
    sos = butter(
        2,
        cutoff_hz / (0.5 * float(sample_rate_hz)),
        btype="low",
        output="sos",
    )
    return sosfiltfilt(sos, values, axis=0)


def spin_orthogonal_hub_yaw(
    imu: IMUSynchronized,
    calibration: ThreeIMUCalibration,
    *,
    min_spin_counts: float = 2500.0,
    min_support_samples: int = 100,
    base: ThreeIMUEstimate | None = None,
) -> dict[str, object]:
    """Estimate wheelchair-frame yaw from each hub after spin-leakage removal.

    For the current WheelAthlete hub mounting, raw gyro Z is the wheel-spin
    axis.  Fixed mounting error can leak a fraction of that large spin signal
    into gyro X/Y.  The leakage fraction is estimated only from high-spin,
    low-chair-yaw IMU intervals and subtracted before projecting the remaining
    X/Y gyro onto the wheel-plane gravity direction from accelerometer X/Y.
    """
    cfg = generic_v4_config()
    if base is None:
        base, _features, _stationary = generic_motion_features(
            imu, calibration, config=cfg
        )
    stationary = np.asarray(base.stationary, dtype=bool)
    center = np.asarray(base.center_yaw_rate, dtype=float)
    gain = abs(float(calibration.center_yaw_gain_radps_per_count))
    sample_rate_hz = (
        1.0 / max(float(np.median(np.diff(imu.t))), 1e-6)
        if len(imu.t) > 1
        else SAMPLE_RATE_HZ
    )

    output: dict[str, object] = {}
    yaw_by_role: dict[str, np.ndarray] = {}
    for role, name in (("L", "left"), ("R", "right")):
        accel = np.asarray(imu.raw[role][:, :3], dtype=float)
        gyro = np.asarray(imu.raw[role][:, 3:6], dtype=float)
        bias = np.column_stack(
            [
                pause_bias_trace(
                    gyro[:, axis],
                    stationary,
                    max_std=10.0,
                    min_samples=30,
                )
                for axis in range(3)
            ]
        )
        corrected = gyro - bias
        spin = corrected[:, 2]

        support = (
            (~stationary)
            & (np.abs(spin) >= abs(float(min_spin_counts)))
            & (np.abs(center) <= np.deg2rad(6.0))
        )
        if int(np.sum(support)) < int(min_support_samples):
            moving_spin = np.abs(spin[~stationary])
            percentile = (
                float(np.percentile(moving_spin, 70.0))
                if len(moving_spin)
                else 0.0
            )
            relaxed = max(0.75 * abs(float(min_spin_counts)), percentile)
            support = (
                (~stationary)
                & (np.abs(spin) >= relaxed)
                & (np.abs(center) <= np.deg2rad(10.0))
            )

        support_count = int(np.sum(support))
        if support_count >= int(min_support_samples):
            leak_x = _slope(spin[support], corrected[support, 0])
            leak_y = _slope(spin[support], corrected[support, 1])
            # Mounting leakage is a small cross-axis effect; refuse a fit that
            # is large enough to be ordinary wheelchair motion instead.
            leak_x = float(np.clip(leak_x, -0.25, 0.25))
            leak_y = float(np.clip(leak_y, -0.25, 0.25))
        else:
            leak_x = 0.0
            leak_y = 0.0

        transverse = np.column_stack(
            [
                corrected[:, 0] - leak_x * spin,
                corrected[:, 1] - leak_y * spin,
            ]
        )
        accel_plane = _lowpass_wheel_plane(accel[:, :2], sample_rate_hz)
        norm = np.linalg.norm(accel_plane, axis=1)
        vertical = accel_plane / np.maximum(norm[:, None], 1e-9)
        yaw = np.sum(transverse * vertical, axis=1) * gain
        yaw[stationary] = 0.0
        yaw[~np.isfinite(yaw)] = 0.0

        yaw_by_role[name] = yaw
        output[f"leakage_{name}_xy"] = np.asarray([leak_x, leak_y], dtype=float)
        output[f"support_{name}"] = support_count

    output["left"] = yaw_by_role["left"]
    output["right"] = yaw_by_role["right"]
    output["mean"] = 0.5 * (yaw_by_role["left"] + yaw_by_role["right"])
    output["left_right_disagreement"] = yaw_by_role["left"] - yaw_by_role["right"]
    return output


def _slow_hub_delta(
    delta: np.ndarray,
    support: np.ndarray,
    confidence: np.ndarray,
    t: np.ndarray,
    tau_s: float,
) -> np.ndarray:
    out = np.zeros(len(delta), dtype=float)
    state = 0.0
    if len(delta) == 0:
        return out
    dt_default = (
        float(np.median(np.diff(t))) if len(t) > 1 else 1.0 / SAMPLE_RATE_HZ
    )
    for index in range(len(delta)):
        if index > 0:
            dt = max(float(t[index] - t[index - 1]), 1e-6)
        else:
            dt = max(dt_default, 1e-6)
        alpha = dt / (max(float(tau_s), dt) + dt)
        if support[index]:
            state += alpha * float(confidence[index]) * (
                float(delta[index]) - state
            )
        out[index] = state
    return out


def estimate_trajectory_v7(
    imu: IMUSynchronized,
    calibration: ThreeIMUCalibration,
    *,
    model: SOFFusionModel | None = None,
) -> ThreeIMUEstimate:
    """Run generic SOF-3IMU slow yaw-bias fusion from L/R/C IMU only."""
    cfg = generic_v4_config()
    base, _features, stationary = generic_motion_features(
        imu, calibration, config=cfg
    )
    if model is None:
        return base
    model.validate()

    hub = spin_orthogonal_hub_yaw(
        imu,
        calibration,
        base=base,
    )
    hub_mean = np.asarray(hub["mean"], dtype=float)
    center = np.asarray(base.center_yaw_rate, dtype=float)
    disagreement = np.abs(hub_mean - center)
    guard = np.deg2rad(float(model.disagreement_guard_deg_s))
    confidence = 1.0 / (1.0 + np.square(disagreement / max(guard, 1e-9)))
    threshold = np.deg2rad(float(model.turn_threshold_deg_s))
    support = (~np.asarray(stationary, dtype=bool)) & (
        np.maximum(np.abs(center), np.abs(hub_mean)) >= threshold
    )
    delta = hub_mean - center
    slow = _slow_hub_delta(
        delta,
        support,
        confidence,
        np.asarray(base.t, dtype=float),
        float(model.bias_tau_s),
    )
    clip = np.deg2rad(float(model.correction_clip_deg_s))
    slow = np.clip(slow, -clip, clip)
    turn_strength = np.clip(
        np.maximum(np.abs(center), np.abs(hub_mean))
        / max(np.deg2rad(8.0), threshold, 1e-9),
        0.0,
        1.0,
    )
    correction = float(model.hub_correction_weight) * slow * turn_strength
    correction[np.asarray(stationary, dtype=bool)] = 0.0

    yaw_rate = np.asarray(base.yaw_rate, dtype=float) + correction
    xy, heading = integrate_se2(base.t, base.speed, yaw_rate)
    quality = dict(base.quality)
    quality.update(
        {
            "sof_hub_correction_applied": 1.0,
            "sof_hub_correction_rms_deg_s": float(
                np.degrees(np.sqrt(np.mean(np.square(correction))))
            ),
            "sof_hub_correction_max_abs_deg_s": float(
                np.degrees(np.max(np.abs(correction))) if len(correction) else 0.0
            ),
            "sof_hub_mean_confidence": float(np.mean(confidence)),
            "sof_left_support_samples": float(hub["support_left"]),
            "sof_right_support_samples": float(hub["support_right"]),
            "sof_left_leak_x": float(np.asarray(hub["leakage_left_xy"])[0]),
            "sof_left_leak_y": float(np.asarray(hub["leakage_left_xy"])[1]),
            "sof_right_leak_x": float(np.asarray(hub["leakage_right_xy"])[0]),
            "sof_right_leak_y": float(np.asarray(hub["leakage_right_xy"])[1]),
        }
    )
    return replace(
        base,
        xy=xy,
        heading=heading,
        yaw_rate=yaw_rate,
        quality=quality,
    )
