"""Experimental three-IMU wheelchair odometry v3.

V3 keeps the v2 backbone and adds Sep-9-development-selected handling for
short low-yaw propulsion trials. Runtime inference accepts no C3D input.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
import numpy as np
from scipy.signal import savgol_filter

from .three_imu_odometry_v2 import (
    C3DReference,
    IMUSynchronized,
    ThreeIMUCalibration,
    ThreeIMUConfig,
    ThreeIMUEstimate,
    _odd_window,
    apply_same_heading_constraint,
    estimate_alignment_lag,
    estimate_trajectory,
    integrate_se2,
    raw_predictors,
)

SAME_HEADING_PROTOCOLS = frozenset({"SL", "SLUP", "10X5", "10X5UP"})

# Sep-9 development-only low-yaw set (OSPT + 7.5-MSPT): the largest observed
# center-vs-wheel yaw disagreement, expanded by a 15% hardware/remount margin.
DEVELOPMENT_MAX_DISAGREEMENT_DEG_S = 10.31284286325838
DISAGREEMENT_SAFETY_MARGIN = 1.15


@dataclass(frozen=True)
class ThreeIMUV3Model:
    speed_residual_coeff: tuple[float, float, float, float, float] = (
        -0.014320348224285954,
        0.006846928718115279,
        0.0022071298062501785,
        0.002952664916172703,
        0.00026493317191811746,
    )
    disagreement_threshold_deg_s: float = DEVELOPMENT_MAX_DISAGREEMENT_DEG_S * DISAGREEMENT_SAFETY_MARGIN
    short_path_min_m: float = 4.0
    short_path_max_m: float = 12.0
    short_abs_yaw_max_rad: float = 1.0
    speed_residual_max_fraction: float = 0.12


DEFAULT_V3_MODEL = ThreeIMUV3Model()


def base_v3_config() -> ThreeIMUConfig:
    return replace(ThreeIMUConfig(), center_weight_straight=.95, center_weight_turn=.97,
                   center_weight_disagreement_bonus=.05, straight_deadband_deg_s=0.0)


def low_disagreement_v3_config() -> ThreeIMUConfig:
    return replace(ThreeIMUConfig(), center_weight_straight=.95, center_weight_turn=.95,
                   center_weight_disagreement_bonus=0.0, straight_deadband_deg_s=0.0)


def yaw_disagreement_rmse_deg_s(imu: IMUSynchronized, calibration: ThreeIMUCalibration) -> float:
    p = raw_predictors(imu, config=base_v3_config())
    center = calibration.center_yaw_gain_radps_per_count * np.asarray(p["center_yaw_raw"], float)
    wheel = calibration.wheel_yaw_gain_radps_per_count * np.asarray(p["wheel_yaw_raw"], float)
    stationary = np.asarray(p["stationary"], bool)
    center[stationary] = wheel[stationary] = 0.0
    return float(np.degrees(np.sqrt(np.mean(np.square(center - wheel)))))


def short_low_yaw_probe(imu: IMUSynchronized, calibration: ThreeIMUCalibration,
                        model: ThreeIMUV3Model = DEFAULT_V3_MODEL) -> tuple[bool, float, float]:
    probe = estimate_trajectory(imu, calibration, config=base_v3_config())
    path_m = float(np.trapezoid(np.abs(probe.speed), probe.t))
    abs_yaw_rad = float(np.trapezoid(np.abs(probe.yaw_rate), probe.t))
    selected = model.short_path_min_m <= path_m <= model.short_path_max_m and abs_yaw_rad < model.short_abs_yaw_max_rad
    return selected, path_m, abs_yaw_rad


def straight_speed_features(imu: IMUSynchronized, calibration: ThreeIMUCalibration,
                            config: ThreeIMUConfig) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    p = raw_predictors(imu, config=config)
    t = np.asarray(imu.t, float)
    stationary = np.asarray(p["stationary"], bool)
    speed = calibration.speed_gain_mps_per_count * np.asarray(p["speed_raw"], float)
    window = _odd_window(.21, config.sample_rate_hz, len(t), minimum=5)
    if len(speed) >= 5:
        speed = savgol_filter(speed, window, 2, mode="interp")
    dt = float(np.median(np.diff(t))) if len(t) > 1 else 1.0 / config.sample_rate_hz
    wheel_acc = np.gradient(speed, dt)
    gravity = np.asarray(p["center_gravity_axis"], float)
    accel = np.asarray(imu.raw["C"][:, :3], float)
    horizontal = accel - np.outer(accel @ gravity, gravity)
    if len(horizontal) >= 5:
        horizontal = savgol_filter(horizontal, window, 2, axis=0, mode="interp")
    moving = ~stationary
    dynamic = moving & (np.abs(wheel_acc) >= np.quantile(np.abs(wheel_acc[moving]), .55)) if moving.any() else moving
    direction = np.sum(horizontal[dynamic] * wheel_acc[dynamic, None], axis=0) if dynamic.any() else np.array([1., 0., 0.])
    direction -= np.dot(direction, gravity) * gravity
    norm = float(np.linalg.norm(direction))
    direction = direction / norm if np.isfinite(norm) and norm > 1e-9 else np.array([1., 0., 0.])
    gravity_mag = float(np.median(np.linalg.norm(accel[stationary], axis=1))) if stationary.any() else float(np.median(np.linalg.norm(accel, axis=1)))
    accel_forward = (horizontal @ direction) * (9.80665 / max(gravity_mag, 1e-9))
    if len(accel_forward) >= 5:
        accel_forward = savgol_filter(accel_forward, window, 2, mode="interp")
    jerk = np.gradient(wheel_acc, dt)
    features = np.column_stack([speed, speed * np.abs(speed), wheel_acc, accel_forward, jerk])
    features[stationary] = 0.0
    return speed, features, stationary


def apply_straight_speed_residual(estimate: ThreeIMUEstimate, imu: IMUSynchronized,
                                  calibration: ThreeIMUCalibration, config: ThreeIMUConfig,
                                  model: ThreeIMUV3Model = DEFAULT_V3_MODEL) -> ThreeIMUEstimate:
    speed, features, stationary = straight_speed_features(imu, calibration, config)
    residual = features @ np.asarray(model.speed_residual_coeff, float)
    residual = np.clip(residual, -model.speed_residual_max_fraction * np.maximum(np.abs(speed), .25),
                       model.speed_residual_max_fraction * np.maximum(np.abs(speed), .25))
    speed = speed + residual
    speed[stationary] = 0.0
    if len(speed) >= 5:
        speed = savgol_filter(speed, _odd_window(.11, config.sample_rate_hz, len(speed), minimum=5), 2, mode="interp")
        speed[stationary] = 0.0
    xy, heading = integrate_se2(estimate.t, speed, estimate.yaw_rate)
    return replace(estimate, speed=speed, xy=xy, heading=heading)


def estimate_trajectory_v3(imu: IMUSynchronized, calibration: ThreeIMUCalibration, *,
                           model: ThreeIMUV3Model = DEFAULT_V3_MODEL,
                           protocol: str | None = None) -> ThreeIMUEstimate:
    """Run v3 inference from L/R/C IMU only."""
    candidate, path_m, abs_yaw_rad = short_low_yaw_probe(imu, calibration, model)
    disagreement = yaw_disagreement_rmse_deg_s(imu, calibration)
    low_dis = candidate and disagreement <= model.disagreement_threshold_deg_s
    config = low_disagreement_v3_config() if low_dis else base_v3_config()
    estimate = estimate_trajectory(imu, calibration, config=config)
    # The straight-speed residual was fitted only on the Sep-9 low-disagreement
    # OSPT/7.5-MSPT development regime.  Do not extrapolate that correction to
    # high-disagreement/OOD motion (for example sprint-like wheel slip), where
    # the deployable v2 backbone is safer and preserves trajectory geometry.
    if low_dis:
        estimate = apply_straight_speed_residual(estimate, imu, calibration, config, model)
    if protocol and protocol.strip().upper() in SAME_HEADING_PROTOCOLS:
        estimate = apply_same_heading_constraint(estimate)
    quality = dict(estimate.quality)
    quality.update({"v3_short_low_yaw": float(candidate), "v3_low_disagreement_mode": float(low_dis),
                    "v3_speed_residual_applied": float(low_dis),
                    "v3_yaw_disagreement_rmse_deg_s": disagreement, "v3_probe_path_m": path_m,
                    "v3_probe_abs_yaw_rad": abs_yaw_rad})
    return replace(estimate, quality=quality)


def estimate_speed_alignment_lag(imu: IMUSynchronized, reference: C3DReference, *, step_s: float = .01) -> tuple[float, float]:
    """Evaluation-only speed alignment for short low-yaw trials."""
    config = base_v3_config()
    pred = np.asarray(raw_predictors(imu, config=config)["speed_raw"], float)
    gt = np.asarray(reference.signed_speed, float)
    best = None
    for lag in np.arange(-config.max_alignment_lag_s, config.max_alignment_lag_s + .5 * step_s, step_s):
        q = reference.t + float(lag)
        support = reference.valid & np.isfinite(gt) & (q >= imu.t[0]) & (q <= imu.t[-1])
        if int(support.sum()) < max(50, int(reference.rate_hz)):
            continue
        x, y = np.interp(q[support], imu.t, pred), gt[support]
        if np.std(x) <= 1e-12 or np.std(y) <= 1e-12:
            continue
        corr = float(np.corrcoef(x, y)[0, 1])
        if np.isfinite(corr) and (best is None or corr > best[1]):
            best = (float(lag), corr)
    if best is None:
        raise ValueError("unable to align low-yaw trial using signed speed")
    return best


def estimate_evaluation_lag_v3(imu: IMUSynchronized, reference: C3DReference,
                               calibration: ThreeIMUCalibration,
                               model: ThreeIMUV3Model = DEFAULT_V3_MODEL) -> tuple[float, str, float]:
    """Evaluation-only adaptive C3D alignment; never used by runtime inference."""
    candidate, _, _ = short_low_yaw_probe(imu, calibration, model)
    if candidate:
        lag, corr = estimate_speed_alignment_lag(imu, reference)
        return lag, "speed", corr
    lag, corr = estimate_alignment_lag(imu, reference, config=base_v3_config())
    return lag, "yaw", corr
