"""DBF-3IMU: persistent dual-bias yaw observer fusion.

V8 keeps the generic C3D-free SOF wheel-frame yaw observation from v7, but
changes how it is used: supported hub-vs-center disagreement estimates a
persistent center-yaw bias state.  That state is held between supported turns
and subtracted from all moving yaw samples, so a learned bias correction does
not disappear on straight segments.
"""
from __future__ import annotations

from dataclasses import dataclass, replace

import numpy as np

from .three_imu_odometry_v2 import (
    IMUSynchronized,
    ThreeIMUCalibration,
    ThreeIMUEstimate,
    integrate_se2,
)
from .three_imu_odometry_v4 import generic_motion_features, generic_v4_config
from .three_imu_odometry_v7 import spin_orthogonal_hub_yaw


@dataclass(frozen=True)
class DualBiasObserverModel:
    """Small deterministic persistent yaw-bias observer."""

    correction_gain: float = 1.0
    observer_tau_s: float = 5.0
    center_hub_guard_deg_s: float = 15.0
    hub_lr_guard_deg_s: float = 12.0
    turn_threshold_deg_s: float = 5.0
    bias_clip_deg_s: float = 1.0

    def validate(self) -> None:
        if not 0.0 <= float(self.correction_gain) <= 1.5:
            raise ValueError("correction_gain must be in [0, 1.5]")
        if float(self.observer_tau_s) <= 0.0:
            raise ValueError("observer_tau_s must be positive")
        if float(self.center_hub_guard_deg_s) <= 0.0:
            raise ValueError("center_hub_guard_deg_s must be positive")
        if float(self.hub_lr_guard_deg_s) <= 0.0:
            raise ValueError("hub_lr_guard_deg_s must be positive")
        if float(self.turn_threshold_deg_s) < 0.0:
            raise ValueError("turn_threshold_deg_s must be non-negative")
        if float(self.bias_clip_deg_s) <= 0.0:
            raise ValueError("bias_clip_deg_s must be positive")


def _persistent_bias_trace(
    center: np.ndarray,
    hub_mean: np.ndarray,
    hub_lr_disagreement: np.ndarray,
    stationary: np.ndarray,
    t: np.ndarray,
    model: DualBiasObserverModel,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    center = np.asarray(center, dtype=float)
    hub_mean = np.asarray(hub_mean, dtype=float)
    lr = np.asarray(hub_lr_disagreement, dtype=float)
    stationary = np.asarray(stationary, dtype=bool)
    t = np.asarray(t, dtype=float)

    center_guard = np.deg2rad(float(model.center_hub_guard_deg_s))
    lr_guard = np.deg2rad(float(model.hub_lr_guard_deg_s))
    threshold = np.deg2rad(float(model.turn_threshold_deg_s))

    delta = center - hub_mean
    center_conf = 1.0 / (1.0 + np.square(delta / max(center_guard, 1e-9)))
    lr_conf = 1.0 / (1.0 + np.square(lr / max(lr_guard, 1e-9)))
    confidence = center_conf * lr_conf
    support = (
        (~stationary)
        & (np.maximum(np.abs(center), np.abs(hub_mean)) >= threshold)
        & (np.abs(lr) <= lr_guard)
    )

    trace = np.zeros(len(delta), dtype=float)
    state = 0.0
    dt_default = float(np.median(np.diff(t))) if len(t) > 1 else 0.01
    for index in range(len(delta)):
        dt = (
            max(float(t[index] - t[index - 1]), 1e-6)
            if index > 0
            else max(dt_default, 1e-6)
        )
        if support[index]:
            alpha = dt / (max(float(model.observer_tau_s), dt) + dt)
            state += alpha * float(confidence[index]) * (float(delta[index]) - state)
        state = float(
            np.clip(
                state,
                -np.deg2rad(float(model.bias_clip_deg_s)),
                np.deg2rad(float(model.bias_clip_deg_s)),
            )
        )
        trace[index] = state
    return trace, support, confidence


def estimate_trajectory_v8(
    imu: IMUSynchronized,
    calibration: ThreeIMUCalibration,
    *,
    model: DualBiasObserverModel | None = None,
) -> ThreeIMUEstimate:
    """Estimate generic planar motion with persistent IMU-only yaw-bias state."""
    cfg = generic_v4_config()
    base, _features, stationary = generic_motion_features(
        imu, calibration, config=cfg
    )
    if model is None:
        return base
    model.validate()

    hub = spin_orthogonal_hub_yaw(imu, calibration, base=base)
    center = np.asarray(base.center_yaw_rate, dtype=float)
    hub_mean = np.asarray(hub["mean"], dtype=float)
    hub_lr = np.asarray(hub["left_right_disagreement"], dtype=float)
    bias, support, confidence = _persistent_bias_trace(
        center,
        hub_mean,
        hub_lr,
        np.asarray(stationary, dtype=bool),
        np.asarray(base.t, dtype=float),
        model,
    )

    correction = float(model.correction_gain) * bias
    correction[np.asarray(stationary, dtype=bool)] = 0.0
    yaw_rate = np.asarray(base.yaw_rate, dtype=float) - correction
    yaw_rate[np.asarray(stationary, dtype=bool)] = 0.0
    xy, heading = integrate_se2(base.t, base.speed, yaw_rate)

    quality = dict(base.quality)
    quality.update(
        {
            "dbf_bias_observer_applied": 1.0,
            "dbf_supported_samples": float(np.sum(support)),
            "dbf_support_fraction": float(np.mean(support)),
            "dbf_mean_confidence": float(np.mean(confidence)),
            "dbf_bias_final_deg_s": float(np.degrees(bias[-1]) if len(bias) else 0.0),
            "dbf_bias_rms_deg_s": float(
                np.degrees(np.sqrt(np.mean(np.square(bias)))) if len(bias) else 0.0
            ),
            "dbf_correction_rms_deg_s": float(
                np.degrees(np.sqrt(np.mean(np.square(correction))))
                if len(correction)
                else 0.0
            ),
            "dbf_left_support_samples": float(hub["support_left"]),
            "dbf_right_support_samples": float(hub["support_right"]),
        }
    )
    return replace(
        base,
        xy=xy,
        heading=heading,
        yaw_rate=yaw_rate,
        quality=quality,
    )
