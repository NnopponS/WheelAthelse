"""WA-CAIF: generic constraint-aided three-IMU wheelchair odometry.

The v6 research method targets slow yaw scale/bias drift explicitly instead of
adding another local rate residual. Runtime inference uses synchronized L/R/C
IMU data only; protocol labels and C3D are intentionally absent from the API.
"""
from __future__ import annotations

from dataclasses import dataclass, replace

import numpy as np
from scipy.ndimage import uniform_filter1d
from scipy.signal import savgol_filter

from .three_imu_odometry_v2 import (
    IMUSynchronized,
    ThreeIMUCalibration,
    ThreeIMUEstimate,
    _odd_window,
    detect_stationary,
    integrate_se2,
    pause_bias_trace,
)
from .three_imu_odometry_v4 import generic_motion_features, generic_v4_config

HUB_GYRO_RADPS_PER_COUNT = float(np.deg2rad(0.06103515625))
MULTISCALE_WINDOWS_S = (0.5, 2.0, 5.0)
MULTISCALE_BASE_COLUMNS = (3, 4, 5, 6, 7, 10)
MULTISCALE_FEATURE_COUNT = 12 + 2 * len(MULTISCALE_WINDOWS_S) * len(MULTISCALE_BASE_COLUMNS)


@dataclass(frozen=True)
class CAIFMultiScaleResidualModel:
    """Bounded multi-scale yaw residual fitted from development data only."""

    feature_scale: tuple[float, ...]
    yaw_coeff: tuple[float, ...]
    yaw_clip_deg_s: float = 2.0

    def validate(self) -> None:
        scale = np.asarray(self.feature_scale, dtype=float)
        coeff = np.asarray(self.yaw_coeff, dtype=float)
        expected = (MULTISCALE_FEATURE_COUNT,)
        if scale.shape != expected or coeff.shape != expected:
            raise ValueError(
                f"WA-CAIF multi-scale model requires {MULTISCALE_FEATURE_COUNT} features"
            )
        if not np.isfinite(scale).all() or np.any(scale <= 0.0):
            raise ValueError("WA-CAIF multi-scale feature scales must be finite and positive")
        if not np.isfinite(coeff).all():
            raise ValueError("WA-CAIF multi-scale coefficients must be finite")
        if not 0.0 <= float(self.yaw_clip_deg_s) <= 10.0:
            raise ValueError("WA-CAIF yaw residual clip is outside the safe range")


CAIF_FEATURE_NAMES = (
    "wheel_center_slope",
    "hub_center_slope",
    "center_wheel_corr",
    "center_hub_corr",
    "center_wheel_disagreement",
    "hub_lr_disagreement",
    "center_abs_yaw",
    "wheel_abs_yaw",
    "hub_abs_yaw",
    "stationary_fraction",
)


@dataclass(frozen=True)
class CAIFYawScaleModel:
    """Low-capacity session-level correction for the center-yaw contribution."""

    feature_mean: tuple[float, ...]
    feature_scale: tuple[float, ...]
    coeff: tuple[float, ...]
    intercept: float = 0.0
    shrinkage: float = 1.0
    scale_min: float = 0.88
    scale_max: float = 1.08
    min_abs_yaw_rad: float = 1.0
    min_turn_samples: int = 100
    min_scale_delta: float = 0.0

    def validate(self) -> None:
        n = len(CAIF_FEATURE_NAMES)
        mean = np.asarray(self.feature_mean, dtype=float)
        scale = np.asarray(self.feature_scale, dtype=float)
        coeff = np.asarray(self.coeff, dtype=float)
        if mean.shape != (n,) or scale.shape != (n,) or coeff.shape != (n,):
            raise ValueError(f"WA-CAIF yaw scale model requires {n} features")
        if not np.isfinite(mean).all() or not np.isfinite(scale).all() or not np.isfinite(coeff).all():
            raise ValueError("WA-CAIF model parameters must be finite")
        if np.any(scale <= 0.0):
            raise ValueError("WA-CAIF feature scales must be positive")
        if not (0.5 <= float(self.scale_min) <= 1.0 <= float(self.scale_max) <= 1.5):
            raise ValueError("WA-CAIF scale bounds must contain 1.0 and remain conservative")
        if int(self.min_turn_samples) < 1 or float(self.min_abs_yaw_rad) < 0.0:
            raise ValueError("WA-CAIF support gates must be non-negative")
        if not 0.0 <= float(self.min_scale_delta) <= 0.25:
            raise ValueError("WA-CAIF minimum scale delta is outside the safe range")

    def predict(self, features: np.ndarray) -> float:
        self.validate()
        x = np.asarray(features, dtype=float)
        if x.shape != (len(CAIF_FEATURE_NAMES),):
            raise ValueError("WA-CAIF feature vector has the wrong shape")
        z = (x - np.asarray(self.feature_mean, dtype=float)) / np.asarray(
            self.feature_scale, dtype=float
        )
        delta = float(self.intercept + np.dot(z, np.asarray(self.coeff, dtype=float)))
        value = float(np.clip(1.0 + float(self.shrinkage) * delta, self.scale_min, self.scale_max))
        if abs(value - 1.0) < float(self.min_scale_delta):
            return 1.0
        return value


def fit_yaw_scale_model(
    features: np.ndarray,
    target_scale: np.ndarray,
    *,
    ridge: float = 10.0,
    shrinkage: float = 1.0,
    scale_min: float = 0.88,
    scale_max: float = 1.08,
    min_abs_yaw_rad: float = 1.0,
    min_turn_samples: int = 100,
    min_scale_delta: float = 0.0,
) -> CAIFYawScaleModel:
    """Fit a tiny ridge head to sequence-level scale targets."""
    x = np.asarray(features, dtype=float)
    y = np.asarray(target_scale, dtype=float)
    if x.ndim != 2 or x.shape[1] != len(CAIF_FEATURE_NAMES) or y.shape != (len(x),):
        raise ValueError("WA-CAIF fit arrays have incompatible shapes")
    good = np.isfinite(x).all(axis=1) & np.isfinite(y)
    x, y = x[good], y[good]
    if len(x) < 2:
        raise ValueError("WA-CAIF scale fit needs at least two finite trials")
    mean = np.mean(x, axis=0)
    scale = np.std(x, axis=0)
    scale[scale < 1e-6] = 1.0
    z = (x - mean) / scale
    design = np.column_stack([np.ones(len(z)), z])
    regularizer = np.eye(design.shape[1], dtype=float)
    regularizer[0, 0] = 0.0
    beta = np.linalg.solve(
        design.T @ design + max(float(ridge), 0.0) * regularizer,
        design.T @ (y - 1.0),
    )
    model = CAIFYawScaleModel(
        feature_mean=tuple(float(v) for v in mean),
        feature_scale=tuple(float(v) for v in scale),
        coeff=tuple(float(v) for v in beta[1:]),
        intercept=float(beta[0]),
        shrinkage=float(shrinkage),
        scale_min=float(scale_min),
        scale_max=float(scale_max),
        min_abs_yaw_rad=float(min_abs_yaw_rad),
        min_turn_samples=int(min_turn_samples),
        min_scale_delta=float(min_scale_delta),
    )
    model.validate()
    return model


def _safe_corr(a: np.ndarray, b: np.ndarray) -> float:
    if len(a) < 3 or float(np.std(a)) <= 1e-9 or float(np.std(b)) <= 1e-9:
        return 0.0
    value = float(np.corrcoef(a, b)[0, 1])
    return value if np.isfinite(value) else 0.0


def _slope(source: np.ndarray, target: np.ndarray) -> float:
    denom = float(np.dot(source, source))
    if denom <= 1e-12:
        return 1.0
    value = float(np.dot(source, target) / denom)
    return value if np.isfinite(value) else 1.0


def multiscale_motion_features(
    imu: IMUSynchronized,
    calibration: ThreeIMUCalibration,
) -> tuple[ThreeIMUEstimate, np.ndarray, np.ndarray]:
    """Build the 48-D generic WA-CAIF temporal feature representation."""
    cfg = generic_v4_config()
    base, motion, stationary = generic_motion_features(imu, calibration, config=cfg)
    if len(imu.t) > 1:
        dt = float(np.median(np.diff(np.asarray(imu.t, dtype=float))))
        sample_rate_hz = 1.0 / max(dt, 1e-6)
    else:
        sample_rate_hz = float(cfg.sample_rate_hz)
    selected = np.asarray(motion[:, MULTISCALE_BASE_COLUMNS], dtype=float)
    parts = [np.asarray(motion, dtype=float)]
    for seconds in MULTISCALE_WINDOWS_S:
        width = max(3, int(round(float(seconds) * sample_rate_hz)))
        mean = uniform_filter1d(selected, size=width, axis=0, mode="nearest")
        second = uniform_filter1d(
            np.square(selected), size=width, axis=0, mode="nearest"
        )
        std = np.sqrt(np.maximum(second - np.square(mean), 0.0))
        parts.extend([mean, std])
    features = np.column_stack(parts)
    if features.shape[1] != MULTISCALE_FEATURE_COUNT:
        raise RuntimeError("WA-CAIF multi-scale feature dimension changed")
    features[~np.isfinite(features)] = 0.0
    return base, features, np.asarray(stationary, dtype=bool)


def hub_frame_yaw_proxy(
    imu: IMUSynchronized,
    *,
    gyro_scale_radps_per_count: float = HUB_GYRO_RADPS_PER_COUNT,
    accel_smoothing_s: float = 0.51,
) -> dict[str, np.ndarray]:
    """Estimate frame yaw from each wheel IMU using gravity-projected gyro."""
    stationary = detect_stationary(imu)
    outputs: dict[str, np.ndarray] = {}
    for role, name in (("L", "left"), ("R", "right")):
        accel = np.asarray(imu.raw[role][:, :3], dtype=float)
        gyro = np.asarray(imu.raw[role][:, 3:6], dtype=float)
        bias = np.column_stack(
            [
                pause_bias_trace(
                    gyro[:, axis], stationary, max_std=10.0, min_samples=30
                )
                for axis in range(3)
            ]
        )
        if len(accel) >= 5:
            window = _odd_window(accel_smoothing_s, 100.0, len(accel), minimum=5)
            gravity_like = savgol_filter(accel, window, 2, axis=0, mode="interp")
        else:
            gravity_like = accel.copy()
        norm = np.linalg.norm(gravity_like, axis=1)
        unit = gravity_like / np.maximum(norm[:, None], 1e-9)
        yaw = np.sum((gyro - bias) * unit, axis=1) * abs(float(gyro_scale_radps_per_count))
        yaw[stationary] = 0.0
        yaw[~np.isfinite(yaw)] = 0.0
        outputs[name] = yaw
    outputs["mean"] = 0.5 * (outputs["left"] + outputs["right"])
    outputs["left_right_disagreement"] = outputs["left"] - outputs["right"]
    return outputs


def caif_summary_features(
    estimate: ThreeIMUEstimate,
    hub: dict[str, np.ndarray],
    *,
    turn_threshold_deg_s: float = 5.0,
) -> tuple[np.ndarray, int, float]:
    """Return the ten IMU-only session statistics used by the scale head."""
    center = np.asarray(estimate.center_yaw_rate, dtype=float)
    wheel = np.asarray(estimate.wheel_yaw_rate, dtype=float)
    hub_mean = np.asarray(hub["mean"], dtype=float)
    stationary = np.asarray(estimate.stationary, dtype=bool)
    threshold = np.deg2rad(abs(float(turn_threshold_deg_s)))
    support = (~stationary) & (
        np.maximum.reduce([np.abs(center), np.abs(wheel), np.abs(hub_mean)]) >= threshold
    )
    c = center[support]
    w = wheel[support]
    h = hub_mean[support]
    lr = np.asarray(hub["left_right_disagreement"], dtype=float)[support]
    c_rms = max(float(np.sqrt(np.mean(np.square(c)))) if len(c) else 0.0, 1e-9)
    h_rms = max(float(np.sqrt(np.mean(np.square(h)))) if len(h) else 0.0, 1e-9)
    if len(c):
        values = np.array(
            [
                _slope(c, w),
                _slope(c, h),
                _safe_corr(c, w),
                _safe_corr(c, h),
                float(np.sqrt(np.mean(np.square(c - w))) / c_rms),
                float(np.sqrt(np.mean(np.square(lr))) / h_rms),
                float(np.mean(np.abs(c))),
                float(np.mean(np.abs(w))),
                float(np.mean(np.abs(h))),
                float(np.mean(stationary)),
            ],
            dtype=float,
        )
    else:
        values = np.array(
            [1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, float(np.mean(stationary))],
            dtype=float,
        )
    values[~np.isfinite(values)] = 0.0
    abs_yaw_rad = float(np.trapezoid(np.abs(center), estimate.t))
    return values, int(np.sum(support)), abs_yaw_rad


def estimate_trajectory_v6_scale_probe(
    imu: IMUSynchronized,
    calibration: ThreeIMUCalibration,
    *,
    model: CAIFYawScaleModel | None = None,
) -> ThreeIMUEstimate:
    """Archived WA-CAIF sequence-scale probe used by rejected iterations 1-2."""
    cfg = generic_v4_config()
    base, _motion_features, stationary = generic_motion_features(imu, calibration, config=cfg)
    hub = hub_frame_yaw_proxy(imu)
    features, turn_samples, abs_yaw_rad = caif_summary_features(base, hub)

    scale = 1.0
    applied = False
    if model is not None:
        model.validate()
        if turn_samples >= model.min_turn_samples and abs_yaw_rad >= model.min_abs_yaw_rad:
            scale = model.predict(features)
            applied = True

    if applied and abs(scale - 1.0) > 1e-12:
        yaw_rate = np.asarray(base.yaw_rate, dtype=float) + (
            (scale - 1.0)
            * np.asarray(base.center_weight, dtype=float)
            * np.asarray(base.center_yaw_rate, dtype=float)
        )
        yaw_rate[stationary] = 0.0
        xy, heading = integrate_se2(base.t, base.speed, yaw_rate)
    else:
        yaw_rate = np.asarray(base.yaw_rate, dtype=float).copy()
        xy = np.asarray(base.xy, dtype=float).copy()
        heading = np.asarray(base.heading, dtype=float).copy()

    quality = dict(base.quality)
    quality.update(
        {
            "wa_caif_scale_applied": float(applied),
            "wa_caif_center_scale": float(scale),
            "wa_caif_turn_samples": float(turn_samples),
            "wa_caif_abs_center_yaw_rad": float(abs_yaw_rad),
            "wa_caif_center_hub_corr": float(features[3]),
            "wa_caif_center_wheel_corr": float(features[2]),
            "wa_caif_hub_lr_disagreement_norm": float(features[5]),
        }
    )
    return replace(base, xy=xy, heading=heading, yaw_rate=yaw_rate, quality=quality)


def estimate_trajectory_v6(
    imu: IMUSynchronized,
    calibration: ThreeIMUCalibration,
    *,
    model: CAIFMultiScaleResidualModel | None = None,
) -> ThreeIMUEstimate:
    """Run the primary generic WA-CAIF multi-scale residual estimator."""
    base, features, stationary = multiscale_motion_features(imu, calibration)
    if model is None:
        return base
    model.validate()
    scale = np.asarray(model.feature_scale, dtype=float)
    coeff = np.asarray(model.yaw_coeff, dtype=float)
    residual = (features / scale[None, :]) @ coeff
    limit = np.deg2rad(abs(float(model.yaw_clip_deg_s)))
    residual = np.clip(residual, -limit, limit)
    residual[stationary] = 0.0
    yaw_rate = np.asarray(base.yaw_rate, dtype=float) + residual
    xy, heading = integrate_se2(base.t, base.speed, yaw_rate)
    quality = dict(base.quality)
    quality.update(
        {
            "wa_caif_multiscale_residual_applied": 1.0,
            "wa_caif_yaw_residual_rms_deg_s": float(
                np.degrees(np.sqrt(np.mean(np.square(residual))))
            ),
            "wa_caif_yaw_residual_max_abs_deg_s": float(
                np.degrees(np.max(np.abs(residual))) if len(residual) else 0.0
            ),
        }
    )
    return replace(base, xy=xy, heading=heading, yaw_rate=yaw_rate, quality=quality)
