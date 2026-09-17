"""Three-IMU wheelchair odometry v2 (research/offline).

This module is intentionally separate from the frozen production L/R estimator.
It builds a deployable IMU-only backbone from the left hub (L), right hub (R),
and chair-center (C) XIAO IMUs.  Optical C3D data is used only by calibration and
evaluation helpers; :func:`estimate_trajectory` never accepts C3D input.

The design attacks long-horizon drift before adding another large network:

1. robust device-clock -> shared-host-time reconstruction,
2. raw-count preservation and synchronized resampling,
3. pause detection from all three IMUs,
4. pause-anchored interpolation of gyro zero-rate bias (ZARU/ZUPT),
5. learned-on-calibration-data gains for wheel speed, differential wheel yaw,
   and center/chassis yaw,
6. adaptive center/wheel yaw fusion, and
7. midpoint SE(2) integration.

C3D helpers retain a per-frame validity mask.  Missing optical frames are never
silently promoted to ground truth; interpolation is used only to make stable
local derivatives and the validity mask is eroded before supervision/metrics.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Iterable, Mapping

import numpy as np
from scipy.signal import savgol_filter

try:
    from biwheel3d.three_imu_data import load_three_imu_export, marker_pair
except ImportError:
    try:
        from .three_imu_data import load_three_imu_export, marker_pair
    except ImportError:
        load_three_imu_export = None
        marker_pair = None

try:  # optional at import time; required only for optical evaluation
    import ezc3d
except ImportError:  # pragma: no cover
    ezc3d = None


@dataclass(frozen=True)
class ThreeIMUConfig:
    sample_rate_hz: float = 100.0
    min_pause_s: float = 0.45
    close_pause_gap_s: float = 0.12
    wheel_pause_floor_counts: float = 35.0
    center_pause_floor_counts: float = 10.0
    center_gravity_window_s: float = 1.0
    pause_quantile_fraction: float = 0.035
    pause_bias_max_std_counts: float = 5.0
    wheel_pause_bias_max_std_counts: float = 10.0
    turn_scale_deg_s: float = 28.0
    center_weight_straight: float = 0.62
    center_weight_turn: float = 0.94
    center_weight_disagreement_bonus: float = 0.05
    disagreement_scale_deg_s: float = 24.0
    straight_deadband_deg_s: float = 0.35
    straight_bias_observer_enabled: bool = False
    straight_bias_max_rate_deg_s: float = 5.0
    straight_bias_max_disagreement_deg_s: float = 4.0
    straight_bias_min_speed_mps: float = 0.15
    straight_bias_min_s: float = 0.50
    straight_bias_max_correction_deg_s: float = 0.75
    pause_turn_anchor_enabled: bool = False
    pause_turn_min_deg: float = 120.0
    pause_turn_max_deg: float = 240.0
    pause_turn_target_deg: float = 180.0
    pause_turn_max_scale_delta: float = 0.25
    smoothing_window_s: float = 0.11
    c3d_derivative_window_s: float = 0.13
    c3d_valid_erosion_s: float = 0.06
    max_alignment_lag_s: float = 5.0
    alignment_step_s: float = 0.02


@dataclass
class IMUSynchronized:
    t: np.ndarray
    raw: dict[str, np.ndarray]
    clock_quality: dict[str, dict[str, float]]
    source: str = ""


@dataclass
class C3DReference:
    t: np.ndarray
    xy: np.ndarray
    heading: np.ndarray
    signed_speed: np.ndarray
    yaw_rate: np.ndarray
    valid: np.ndarray
    marker_spacing_m: np.ndarray
    rate_hz: float
    source: str = ""


@dataclass(frozen=True)
class ThreeIMUCalibration:
    """Frozen gains learned from calibration/development trials only."""

    speed_gain_mps_per_count: float
    center_yaw_gain_radps_per_count: float
    wheel_yaw_gain_radps_per_count: float
    calibration_trials: int = 0
    provenance: str = "development_only"
    diagnostics: Mapping[str, float] = field(default_factory=dict)


@dataclass
class ThreeIMUEstimate:
    t: np.ndarray
    xy: np.ndarray
    heading: np.ndarray
    speed: np.ndarray
    yaw_rate: np.ndarray
    center_yaw_rate: np.ndarray
    wheel_yaw_rate: np.ndarray
    stationary: np.ndarray
    center_weight: np.ndarray
    disagreement_rad_s: np.ndarray
    bias_raw: dict[str, np.ndarray]
    quality: dict[str, float]


@dataclass
class AlignedTrial:
    """C3D labels and raw-derived IMU predictors on the C3D timebase."""

    lag_s: float
    alignment_corr: float
    valid: np.ndarray
    gt_xy: np.ndarray
    gt_heading: np.ndarray
    gt_speed: np.ndarray
    gt_yaw_rate: np.ndarray
    speed_raw: np.ndarray
    center_yaw_raw: np.ndarray
    wheel_yaw_raw: np.ndarray
    stationary: np.ndarray


def _odd_window(seconds: float, fs: float, n: int, *, minimum: int = 5) -> int:
    if n < 3:
        return max(1, n)
    w = max(minimum, int(round(float(seconds) * float(fs))))
    if w % 2 == 0:
        w += 1
    if w >= n:
        w = n if n % 2 == 1 else n - 1
    return max(3, w)


def _smooth(values: np.ndarray, fs: float, seconds: float) -> np.ndarray:
    x = np.asarray(values, dtype=float)
    if len(x) < 5:
        return x.copy()
    w = _odd_window(seconds, fs, len(x))
    if w < 5:
        return x.copy()
    return savgol_filter(x, window_length=w, polyorder=min(2, w - 2), mode="interp")


def _runs(mask: np.ndarray) -> list[tuple[int, int, bool]]:
    m = np.asarray(mask, dtype=bool)
    if len(m) == 0:
        return []
    out: list[tuple[int, int, bool]] = []
    i = 0
    while i < len(m):
        j = i + 1
        while j < len(m) and bool(m[j]) == bool(m[i]):
            j += 1
        out.append((i, j, bool(m[i])))
        i = j
    return out


def _close_boolean_gaps(mask: np.ndarray, max_gap: int) -> np.ndarray:
    out = np.asarray(mask, dtype=bool).copy()
    if max_gap <= 0:
        return out
    for i0, i1, value in _runs(out):
        if (not value) and i0 > 0 and i1 < len(out) and (i1 - i0) <= max_gap:
            out[i0:i1] = True
    return out


def _drop_short_true_runs(mask: np.ndarray, min_len: int) -> np.ndarray:
    out = np.asarray(mask, dtype=bool).copy()
    for i0, i1, value in _runs(out):
        if value and (i1 - i0) < min_len:
            out[i0:i1] = False
    return out


def erode_mask(mask: np.ndarray, radius: int) -> np.ndarray:
    """Require every sample in +/- ``radius`` to be valid."""
    m = np.asarray(mask, dtype=bool)
    if radius <= 0 or len(m) == 0:
        return m.copy()
    bad = (~m).astype(np.int64)
    kernel = np.ones(2 * radius + 1, dtype=np.int64)
    padded = np.pad(bad, (radius, radius), constant_values=1)
    return np.convolve(padded, kernel, mode="valid") == 0


def robust_clock_fit(device_us: np.ndarray, host_ns: np.ndarray) -> tuple[np.ndarray, dict[str, float]]:
    """Robust affine device->host clock fit with iterative MAD rejection.

    BLE packet timestamps are intentionally quantized/repeated, so the device
    clock remains the high-resolution within-packet timebase.  Host time only
    establishes cross-device offset and slow clock scale.
    """
    x = np.asarray(device_us, dtype=float)
    y = np.asarray(host_ns, dtype=float)
    if len(x) != len(y) or len(x) < 8:
        raise ValueError("clock fit requires matching arrays with at least 8 samples")
    if np.any(np.diff(x) <= 0):
        raise ValueError("device clock must be strictly monotonic")
    if not np.isfinite(y).all():
        raise ValueError("host clock must be finite")

    x0 = float(np.mean(x))
    y0 = float(np.mean(y))
    xc = x - x0
    yc = y - y0
    keep = np.ones(len(x), dtype=bool)
    slope = 1000.0
    intercept_c = 0.0
    for _ in range(6):
        A = np.column_stack([xc[keep], np.ones(int(keep.sum()))])
        slope, intercept_c = np.linalg.lstsq(A, yc[keep], rcond=None)[0]
        residual = yc - (slope * xc + intercept_c)
        med = float(np.median(residual[keep]))
        mad = 1.4826 * float(np.median(np.abs(residual[keep] - med)))
        if not np.isfinite(mad) or mad < 1.0:
            break
        new_keep = np.abs(residual - med) <= max(4.5 * mad, 2_000_000.0)
        if new_keep.sum() < max(8, int(0.65 * len(x))) or np.array_equal(new_keep, keep):
            break
        keep = new_keep
    predicted = y0 + slope * xc + intercept_c
    residual = y - predicted
    rms_ms = float(np.sqrt(np.mean(np.square(residual[keep]))) / 1e6)
    return predicted, {
        "clock_scale_ns_per_us": float(slope),
        "clock_drift_ppm": float((slope / 1000.0 - 1.0) * 1e6),
        "host_fit_rms_ms": rms_ms,
        "clock_inlier_fraction": float(np.mean(keep)),
    }


def load_synchronized_imu(path: str | Path, *, config: ThreeIMUConfig | None = None) -> IMUSynchronized:
    """Load raw L/R/C counts and resample them onto a common robust host clock."""
    cfg = config or ThreeIMUConfig()
    streams = load_three_imu_export(path)
    host_times: dict[str, np.ndarray] = {}
    quality: dict[str, dict[str, float]] = {}
    for role in ("L", "R", "C"):
        predicted_ns, q = robust_clock_fit(
            np.asarray(streams[role]["timestamp_device_us_unwrapped"], dtype=float),
            np.asarray(streams[role]["timestamp_pc_monotonic_ns"], dtype=float),
        )
        host_times[role] = predicted_ns / 1e9
        quality[role] = q

    start = max(float(v[0]) for v in host_times.values())
    stop = min(float(v[-1]) for v in host_times.values())
    if stop - start < 1.0:
        raise ValueError("three IMUs do not have at least one second of shared support")
    dt = 1.0 / float(cfg.sample_rate_hz)
    t_abs = np.arange(start, stop + 0.25 * dt, dt, dtype=float)
    raw: dict[str, np.ndarray] = {}
    for role in ("L", "R", "C"):
        samples = np.asarray(streams[role]["samples"], dtype=float)
        raw[role] = np.column_stack(
            [np.interp(t_abs, host_times[role], samples[:, j]) for j in range(samples.shape[1])]
        )
    return IMUSynchronized(
        t=t_abs - t_abs[0],
        raw=raw,
        clock_quality=quality,
        source=str(path),
    )


def _point_unit_scale(unit: str) -> float:
    name = str(unit).strip().lower()
    if name in {"m", "meter", "metre", "meters", "metres"}:
        return 1.0
    if name in {"mm", "millimeter", "millimetre", "millimeters", "millimetres"}:
        return 1e-3
    if name in {"cm", "centimeter", "centimetre", "centimeters", "centimetres"}:
        return 1e-2
    raise ValueError(f"unsupported C3D point unit {unit!r}")


def _interp_for_derivative(values: np.ndarray, valid: np.ndarray) -> np.ndarray:
    x = np.asarray(values, dtype=float)
    valid = np.asarray(valid, dtype=bool) & np.isfinite(x)
    if valid.sum() < 2:
        return np.full_like(x, np.nan, dtype=float)
    idx = np.arange(len(x), dtype=float)
    return np.interp(idx, idx[valid], x[valid])


def load_c3d_reference(path: str | Path, *, config: ThreeIMUConfig | None = None) -> C3DReference:
    """Load explicit optical L/R XIAO markers with conservative frame validity."""
    if ezc3d is None:  # pragma: no cover
        raise ImportError("ezc3d is required for C3D evaluation")
    cfg = config or ThreeIMUConfig()
    path = Path(path)
    c3d = ezc3d.c3d(str(path))
    labels = [str(v).strip() for v in c3d["parameters"]["POINT"]["LABELS"]["value"]]
    il, ir = marker_pair(labels, path.name)
    rate = float(c3d["parameters"]["POINT"]["RATE"]["value"][0])
    unit = str(c3d["parameters"]["POINT"]["UNITS"]["value"][0])
    scale = _point_unit_scale(unit)
    points = np.asarray(c3d["data"]["points"], dtype=float)
    residuals = np.asarray(c3d["data"]["meta_points"]["residuals"], dtype=float)[0]
    left = (points[:3, il, :].T * scale).astype(float)
    right = (points[:3, ir, :].T * scale).astype(float)
    valid_l = np.isfinite(left).all(axis=1) & np.isfinite(residuals[il]) & (residuals[il] >= 0)
    valid_r = np.isfinite(right).all(axis=1) & np.isfinite(residuals[ir]) & (residuals[ir] >= 0)
    spacing = np.linalg.norm(right - left, axis=1)
    both = valid_l & valid_r & np.isfinite(spacing)
    if both.sum() < max(20, int(rate)):
        raise ValueError(f"{path.name}: insufficient jointly visible L/R optical frames")
    spacing_median = float(np.median(spacing[both]))
    spacing_mad = 1.4826 * float(np.median(np.abs(spacing[both] - spacing_median)))
    spacing_tol = max(0.025, 8.0 * spacing_mad)
    valid = both & (np.abs(spacing - spacing_median) <= spacing_tol)

    # Interpolation stabilizes local derivatives only.  The original validity
    # is eroded below and remains the supervision/evaluation mask.
    left_f = np.column_stack([_interp_for_derivative(left[:, j], valid) for j in range(3)])
    right_f = np.column_stack([_interp_for_derivative(right[:, j], valid) for j in range(3)])
    center = 0.5 * (left_f + right_f)
    axle = right_f[:, :2] - left_f[:, :2]
    heading = np.unwrap(np.arctan2(axle[:, 0], -axle[:, 1]))
    fs = rate
    heading = _smooth(heading, fs, cfg.c3d_derivative_window_s)
    cx = _smooth(center[:, 0], fs, cfg.c3d_derivative_window_s)
    cy = _smooth(center[:, 1], fs, cfg.c3d_derivative_window_s)
    dt = 1.0 / fs
    vx = np.gradient(cx, dt)
    vy = np.gradient(cy, dt)
    signed_speed = vx * np.cos(heading) + vy * np.sin(heading)
    yaw_rate = np.gradient(heading, dt)
    erosion = max(1, int(round(cfg.c3d_valid_erosion_s * fs)))
    support = erode_mask(valid, erosion)
    t = np.arange(len(center), dtype=float) / fs
    return C3DReference(
        t=t,
        xy=np.column_stack([center[:, 0], center[:, 1]]),
        heading=heading,
        signed_speed=signed_speed,
        yaw_rate=yaw_rate,
        valid=support,
        marker_spacing_m=spacing,
        rate_hz=rate,
        source=str(path),
    )


def detect_stationary(imu: IMUSynchronized, *, config: ThreeIMUConfig | None = None) -> np.ndarray:
    """Detect true all-sensor stillness; low center yaw alone is not a pause."""
    cfg = config or ThreeIMUConfig()
    lgz = imu.raw["L"][:, 5]
    rgz = imu.raw["R"][:, 5]
    cgyro = imu.raw["C"][:, 3:6]
    n0 = max(10, min(len(imu.t), int(round(0.8 * cfg.sample_rate_hz))))
    b_l = float(np.median(lgz[:n0]))
    b_r = float(np.median(rgz[:n0]))
    b_c = np.median(cgyro[:n0], axis=0)
    wheel_activity = np.maximum(np.abs(lgz - b_l), np.abs(rgz - b_r))
    center_activity = np.linalg.norm(cgyro - b_c, axis=1)
    w99 = float(np.quantile(wheel_activity, 0.99))
    c99 = float(np.quantile(center_activity, 0.99))
    w_thr = max(cfg.wheel_pause_floor_counts, cfg.pause_quantile_fraction * w99)
    c_thr = max(cfg.center_pause_floor_counts, cfg.pause_quantile_fraction * c99)

    # A real stop must be quiet at both hubs and at the chair.  This rejects a
    # pivot where wheel speeds oppose each other but chassis yaw is non-zero.
    quiet = (wheel_activity <= w_thr) & (center_activity <= c_thr)
    gap = max(1, int(round(cfg.close_pause_gap_s * cfg.sample_rate_hz)))
    min_len = max(1, int(round(cfg.min_pause_s * cfg.sample_rate_hz)))
    quiet = _close_boolean_gaps(quiet, gap)
    quiet = _drop_short_true_runs(quiet, min_len)
    return quiet


def pause_bias_trace(
    values: np.ndarray,
    stationary: np.ndarray,
    *,
    fallback_samples: int = 80,
    max_std: float | None = None,
    min_samples: int = 1,
) -> np.ndarray:
    """Interpolate zero-rate gyro bias between detected stationary anchors."""
    x = np.asarray(values, dtype=float)
    stationary = np.asarray(stationary, dtype=bool)
    anchors_t: list[float] = []
    anchors_v: list[float] = []
    for i0, i1, value in _runs(stationary):
        if value and i1 > i0 and (i1 - i0) >= min_samples:
            if max_std is not None and float(np.std(x[i0:i1])) > max_std:
                continue
            anchors_t.append(0.5 * (i0 + i1 - 1))
            anchors_v.append(float(np.median(x[i0:i1])))
    if not anchors_t:
        n = max(1, min(len(x), int(fallback_samples)))
        return np.full(len(x), float(np.median(x[:n])), dtype=float)
    if len(anchors_t) == 1:
        return np.full(len(x), anchors_v[0], dtype=float)
    return np.interp(np.arange(len(x), dtype=float), anchors_t, anchors_v)


def center_gravity_axis(
    imu: IMUSynchronized,
    stationary: np.ndarray,
    *,
    config: ThreeIMUConfig | None = None,
) -> np.ndarray:
    """Estimate the fixed sensor-frame vertical axis from center accelerometer gravity."""
    cfg = config or ThreeIMUConfig()
    accel = np.asarray(imu.raw["C"][:, :3], dtype=float)
    support = np.asarray(stationary, dtype=bool)
    min_samples = max(10, int(round(0.5 * cfg.sample_rate_hz)))
    if int(support.sum()) < min_samples:
        n = max(min_samples, int(round(cfg.center_gravity_window_s * cfg.sample_rate_hz)))
        support = np.zeros(len(accel), dtype=bool)
        support[: min(len(accel), n)] = True
    gravity = np.median(accel[support], axis=0)
    norm = float(np.linalg.norm(gravity))
    if not np.isfinite(norm) or norm <= 1e-9:
        raise ValueError("center gravity axis is not observable")
    return gravity / norm


def dynamic_gravity_tilt(
    accel: np.ndarray,
    cgyro_corrected: np.ndarray,
    stationary: np.ndarray,
    fs: float,
    g_init: np.ndarray,
) -> np.ndarray:
    """Track body tilt dynamically using complementary attitude integration.

    Decouples pitch and roll motion during explosive sprints and braking
    from horizontal yaw angular velocity.
    """
    n = len(accel)
    if n == 0:
        return np.zeros((0, 3), dtype=float)
    dt = 1.0 / max(float(fs), 1.0)
    g_track = np.zeros((n, 3), dtype=float)
    g_curr = np.asarray(g_init, dtype=float).copy()
    norm_init = float(np.linalg.norm(g_curr))
    if norm_init > 1e-9:
        g_curr = g_curr / norm_init
    else:
        g_curr = np.array([0.0, 0.0, 1.0])

    stat = np.asarray(stationary, dtype=bool)
    g_mag = (
        float(np.median(np.linalg.norm(accel[stat], axis=1)))
        if stat.any()
        else float(np.median(np.linalg.norm(accel, axis=1)))
    )
    tau = 2.0
    alpha = dt / (tau + dt)
    scale_gyro = np.deg2rad(0.06103515625)

    for i in range(n):
        omega = cgyro_corrected[i] * scale_gyro
        g_curr = g_curr + np.cross(g_curr, omega) * dt
        a_norm = float(np.linalg.norm(accel[i]))
        if abs(a_norm - g_mag) / max(g_mag, 1.0) < 0.15:
            a_dir = accel[i] / max(a_norm, 1e-6)
            g_curr = (1.0 - alpha) * g_curr + alpha * a_dir
        norm = float(np.linalg.norm(g_curr))
        if norm > 1e-6:
            g_curr = g_curr / norm
        g_track[i] = g_curr
    return g_track


def raw_predictors(
    imu: IMUSynchronized,
    *,
    config: ThreeIMUConfig | None = None,
) -> dict[str, np.ndarray]:
    """Build bias-corrected raw predictors without using optical data."""
    cfg = config or ThreeIMUConfig()
    stationary = detect_stationary(imu, config=cfg)
    lgz = imu.raw["L"][:, 5]
    rgz = imu.raw["R"][:, 5]
    cgyro = np.asarray(imu.raw["C"][:, 3:6], dtype=float)
    b_l = pause_bias_trace(
        lgz,
        stationary,
        max_std=cfg.wheel_pause_bias_max_std_counts,
        min_samples=30,
    )
    b_r = pause_bias_trace(
        rgz,
        stationary,
        max_std=cfg.wheel_pause_bias_max_std_counts,
        min_samples=30,
    )
    b_c_xyz = np.column_stack(
        [
            pause_bias_trace(
                cgyro[:, axis],
                stationary,
                max_std=cfg.pause_bias_max_std_counts,
                min_samples=30,
            )
            for axis in range(3)
        ]
    )
    gravity_axis = center_gravity_axis(imu, stationary, config=cfg)
    cgyro_corrected = cgyro - b_c_xyz
    caccel = np.asarray(imu.raw["C"][:, :3], dtype=float)
    g_dyn = dynamic_gravity_tilt(
        caccel,
        cgyro_corrected,
        stationary,
        cfg.sample_rate_hz,
        gravity_axis,
    )
    left = lgz - b_l
    right = -(rgz - b_r)  # canonical forward wheel sign
    speed_raw = 0.5 * (left + right)
    wheel_yaw_raw = right - left
    center_yaw_raw = np.sum(cgyro_corrected * g_dyn, axis=1)
    return {
        "speed_raw": speed_raw,
        "wheel_yaw_raw": wheel_yaw_raw,
        "center_yaw_raw": center_yaw_raw,
        "stationary": stationary,
        "bias_l": b_l,
        "bias_r": b_r,
        "bias_c": np.sum(b_c_xyz * gravity_axis[None, :], axis=1),
        "bias_c_xyz": b_c_xyz,
        "center_gravity_axis": gravity_axis,
    }


def estimate_pause_bounded_speed_gain(
    imu: IMUSynchronized,
    *,
    config: ThreeIMUConfig | None = None,
) -> tuple[float, dict[str, float]]:
    """Estimate chair speed gain from center acceleration and pause-bounded motion.

    This is an IMU-only one-time chair calibration. Gravity sets accelerometer
    scale, wheel acceleration identifies the center-sensor forward axis, and
    each moving interval is bounded by zero-velocity pauses.
    """
    cfg = config or ThreeIMUConfig()
    p = raw_predictors(imu, config=cfg)
    t = np.asarray(imu.t, dtype=float)
    speed_raw = np.asarray(p["speed_raw"], dtype=float)
    stationary = np.asarray(p["stationary"], dtype=bool)
    if len(t) < 10 or not stationary.any():
        raise ValueError("chair speed calibration needs stationary support")
    dt = float(np.median(np.diff(t)))
    gravity_axis = np.asarray(p["center_gravity_axis"], dtype=float)
    accel = np.asarray(imu.raw["C"][:, :3], dtype=float)
    horizontal = accel - np.outer(accel @ gravity_axis, gravity_axis)
    window = _odd_window(0.30, cfg.sample_rate_hz, len(t), minimum=5)
    horizontal = savgol_filter(horizontal, window, 2, axis=0, mode="interp")
    smoothed_raw = savgol_filter(speed_raw, window, 2, mode="interp")
    wheel_acc = np.gradient(smoothed_raw, dt)
    moving = ~stationary
    if moving.sum() < 20:
        raise ValueError("chair speed calibration needs moving support")
    threshold = float(np.quantile(np.abs(wheel_acc[moving]), 0.55))
    dynamic = moving & (np.abs(wheel_acc) >= threshold)
    direction = np.sum(horizontal[dynamic] * wheel_acc[dynamic, None], axis=0)
    direction -= np.dot(direction, gravity_axis) * gravity_axis
    norm = float(np.linalg.norm(direction))
    if not np.isfinite(norm) or norm <= 1e-9:
        raise ValueError("chair forward axis is not observable")
    forward = direction / norm
    gravity_mag = float(np.median(np.linalg.norm(accel[stationary], axis=1)))
    if not np.isfinite(gravity_mag) or gravity_mag <= 1e-9:
        raise ValueError("accelerometer gravity scale is not observable")
    a_forward = (horizontal @ forward) * (9.80665 / gravity_mag)
    a_forward = savgol_filter(a_forward, window, 2, mode="interp")

    gains: list[float] = []
    weights: list[float] = []
    min_len = max(10, int(round(cfg.sample_rate_hz)))
    for start, stop, active in _runs(moving):
        if not active or start <= 0 or stop >= len(t) or stop - start < min_len:
            continue
        local_t = t[start:stop]
        duration = float(local_t[-1] - local_t[0])
        if duration <= 0:
            continue
        local_a = a_forward[start:stop].copy()
        local_a -= float(np.trapezoid(local_a, local_t) / duration)
        velocity = np.zeros(len(local_a), dtype=float)
        if len(velocity) > 1:
            velocity[1:] = np.cumsum(
                0.5 * (local_a[:-1] + local_a[1:]) * np.diff(local_t)
            )
        raw = speed_raw[start:stop]
        denom = float(np.dot(raw, raw))
        if denom <= 1e-9:
            continue
        gain = abs(float(np.dot(raw, velocity) / denom))
        if np.isfinite(gain) and gain > 0:
            gains.append(gain)
            weights.append(float(np.sum(np.abs(raw))))
    if not gains:
        raise ValueError("no pause-bounded motion segment supports speed calibration")
    gains_array = np.asarray(gains, dtype=float)
    weights_array = np.asarray(weights, dtype=float)
    gain = float(np.sum(gains_array * weights_array) / np.sum(weights_array))
    return gain, {
        "segments": float(len(gains)),
        "segment_gain_median": float(np.median(gains_array)),
        "segment_gain_min": float(np.min(gains_array)),
        "segment_gain_max": float(np.max(gains_array)),
        "gravity_counts": gravity_mag,
        "forward_x": float(forward[0]),
        "forward_y": float(forward[1]),
        "forward_z": float(forward[2]),
    }


def estimate_alignment_lag(
    imu: IMUSynchronized,
    reference: C3DReference,
    *,
    config: ThreeIMUConfig | None = None,
) -> tuple[float, float]:
    """Estimate evaluation/training time alignment from center yaw correlation.

    Returned lag follows ``imu_time = c3d_time + lag``.  The absolute value of
    correlation is optimized because center yaw sign is calibrated separately.
    This function is for dataset alignment, not runtime inference.
    """
    cfg = config or ThreeIMUConfig()
    pred = raw_predictors(imu, config=cfg)["center_yaw_raw"]
    gt = reference.yaw_rate
    valid_gt = reference.valid & np.isfinite(gt)
    lags = np.arange(-cfg.max_alignment_lag_s, cfg.max_alignment_lag_s + 0.5 * cfg.alignment_step_s, cfg.alignment_step_s)
    best_lag = 0.0
    best_corr = -np.inf
    for lag in lags:
        q = reference.t + float(lag)
        support = valid_gt & (q >= imu.t[0]) & (q <= imu.t[-1])
        if support.sum() < max(100, int(reference.rate_hz * 2.0)):
            continue
        x = np.interp(q[support], imu.t, pred)
        y = gt[support]
        x = x - np.mean(x)
        y = y - np.mean(y)
        denom = float(np.linalg.norm(x) * np.linalg.norm(y))
        if denom <= 1e-12:
            continue
        corr = float(np.dot(x, y) / denom)
        if abs(corr) > abs(best_corr) if np.isfinite(best_corr) else True:
            best_lag, best_corr = float(lag), corr
    if not np.isfinite(best_corr):
        raise ValueError("unable to align IMU and C3D yaw-rate signals")
    return best_lag, best_corr


def align_trial(
    imu: IMUSynchronized,
    reference: C3DReference,
    *,
    lag_s: float | None = None,
    config: ThreeIMUConfig | None = None,
) -> AlignedTrial:
    """Sample IMU raw predictors on the optical timebase for calibration/eval."""
    cfg = config or ThreeIMUConfig()
    lag, corr = estimate_alignment_lag(imu, reference, config=cfg) if lag_s is None else (float(lag_s), float("nan"))
    p = raw_predictors(imu, config=cfg)
    q = reference.t + lag
    time_ok = (q >= imu.t[0]) & (q <= imu.t[-1])
    valid = reference.valid & time_ok

    def sample(name: str) -> np.ndarray:
        return np.interp(q, imu.t, np.asarray(p[name], dtype=float), left=np.nan, right=np.nan)

    return AlignedTrial(
        lag_s=lag,
        alignment_corr=corr,
        valid=valid,
        gt_xy=reference.xy.copy(),
        gt_heading=reference.heading.copy(),
        gt_speed=reference.signed_speed.copy(),
        gt_yaw_rate=reference.yaw_rate.copy(),
        speed_raw=sample("speed_raw"),
        center_yaw_raw=sample("center_yaw_raw"),
        wheel_yaw_raw=sample("wheel_yaw_raw"),
        stationary=sample("stationary") >= 0.5,
    )


def _robust_gain(x: np.ndarray, y: np.ndarray, mask: np.ndarray) -> tuple[float, dict[str, float]]:
    """Huber-like robust through-origin gain fit."""
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    keep = np.asarray(mask, dtype=bool) & np.isfinite(x) & np.isfinite(y)
    if keep.sum() < 50:
        raise ValueError("calibration gain needs at least 50 valid samples")
    w = np.ones(len(x), dtype=float)
    gain = 0.0
    for _ in range(8):
        idx = keep & (w > 0)
        denom = float(np.sum(w[idx] * x[idx] * x[idx]))
        if denom <= 1e-12:
            raise ValueError("calibration predictor has no excitation")
        gain = float(np.sum(w[idx] * x[idx] * y[idx]) / denom)
        residual = y - gain * x
        med = float(np.median(residual[keep]))
        scale = 1.4826 * float(np.median(np.abs(residual[keep] - med))) + 1e-12
        u = np.abs(residual - med) / (1.5 * scale)
        w = np.ones(len(x), dtype=float)
        high = u > 1.0
        w[high] = 1.0 / u[high]
        w[~keep] = 0.0
    pred = gain * x[keep]
    rmse = float(np.sqrt(np.mean(np.square(pred - y[keep]))))
    denom_corr = float(np.linalg.norm(pred - pred.mean()) * np.linalg.norm(y[keep] - y[keep].mean()))
    corr = float(np.dot(pred - pred.mean(), y[keep] - y[keep].mean()) / denom_corr) if denom_corr > 1e-12 else float("nan")
    return gain, {"rmse": rmse, "correlation": corr, "samples": float(keep.sum())}


def fit_calibration(aligned_trials: Iterable[AlignedTrial]) -> ThreeIMUCalibration:
    """Fit frozen raw-count gains from development/calibration trials."""
    trials = list(aligned_trials)
    if not trials:
        raise ValueError("no calibration trials")
    speed_x: list[np.ndarray] = []
    center_x: list[np.ndarray] = []
    wheel_x: list[np.ndarray] = []
    speed_y: list[np.ndarray] = []
    yaw_y: list[np.ndarray] = []
    valid_all: list[np.ndarray] = []
    for tr in trials:
        speed_x.append(tr.speed_raw)
        center_x.append(tr.center_yaw_raw)
        wheel_x.append(tr.wheel_yaw_raw)
        speed_y.append(tr.gt_speed)
        yaw_y.append(tr.gt_yaw_rate)
        valid_all.append(tr.valid & (~tr.stationary))
    sx = np.concatenate(speed_x)
    cx = np.concatenate(center_x)
    wx = np.concatenate(wheel_x)
    sy = np.concatenate(speed_y)
    yy = np.concatenate(yaw_y)
    valid = np.concatenate(valid_all)
    speed_mask = valid & (np.abs(sy) >= 0.04)
    yaw_mask = valid & (np.abs(yy) >= np.deg2rad(4.0))
    speed_gain, speed_diag = _robust_gain(sx, sy, speed_mask)
    center_gain, center_diag = _robust_gain(cx, yy, yaw_mask)
    wheel_gain, wheel_diag = _robust_gain(wx, yy, yaw_mask)
    diagnostics = {
        "speed_fit_rmse_mps": speed_diag["rmse"],
        "speed_fit_corr": speed_diag["correlation"],
        "center_yaw_fit_rmse_rad_s": center_diag["rmse"],
        "center_yaw_fit_corr": center_diag["correlation"],
        "wheel_yaw_fit_rmse_rad_s": wheel_diag["rmse"],
        "wheel_yaw_fit_corr": wheel_diag["correlation"],
        "speed_fit_samples": speed_diag["samples"],
        "yaw_fit_samples": center_diag["samples"],
    }
    return ThreeIMUCalibration(
        speed_gain_mps_per_count=speed_gain,
        center_yaw_gain_radps_per_count=center_gain,
        wheel_yaw_gain_radps_per_count=wheel_gain,
        calibration_trials=len(trials),
        provenance="development_only",
        diagnostics=diagnostics,
    )


def integrate_se2(t: np.ndarray, speed: np.ndarray, yaw_rate: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Midpoint integration with pose exactly zero at the first sample."""
    t = np.asarray(t, dtype=float)
    v = np.asarray(speed, dtype=float)
    w = np.asarray(yaw_rate, dtype=float)
    if not (len(t) == len(v) == len(w)):
        raise ValueError("time, speed, and yaw-rate lengths must match")
    n = len(t)
    xy = np.zeros((n, 2), dtype=float)
    heading = np.zeros(n, dtype=float)
    if n < 2:
        return xy, heading
    dt = np.diff(t)
    for i in range(1, n):
        dpsi = 0.5 * (w[i - 1] + w[i]) * dt[i - 1]
        mid = heading[i - 1] + 0.5 * dpsi
        ds = 0.5 * (v[i - 1] + v[i]) * dt[i - 1]
        xy[i] = xy[i - 1] + ds * np.array([np.cos(mid), np.sin(mid)])
        heading[i] = heading[i - 1] + dpsi
    return xy, heading


def straight_yaw_bias_trace(
    center_yaw_rate: np.ndarray,
    wheel_yaw_rate: np.ndarray,
    speed: np.ndarray,
    stationary: np.ndarray,
    *,
    config: ThreeIMUConfig | None = None,
) -> tuple[np.ndarray, int]:
    """Estimate low-frequency center yaw bias from high-confidence straight motion."""
    cfg = config or ThreeIMUConfig()
    center = np.asarray(center_yaw_rate, dtype=float)
    wheel = np.asarray(wheel_yaw_rate, dtype=float)
    speed = np.asarray(speed, dtype=float)
    stationary = np.asarray(stationary, dtype=bool)
    if not cfg.straight_bias_observer_enabled:
        return np.zeros_like(center), 0
    rate_limit = np.deg2rad(cfg.straight_bias_max_rate_deg_s)
    disagreement_limit = np.deg2rad(cfg.straight_bias_max_disagreement_deg_s)
    candidate = (
        (~stationary)
        & (np.abs(speed) >= cfg.straight_bias_min_speed_mps)
        & (np.abs(center) <= rate_limit)
        & (np.abs(wheel) <= rate_limit)
        & (np.abs(center - wheel) <= disagreement_limit)
    )
    min_len = max(1, int(round(cfg.straight_bias_min_s * cfg.sample_rate_hz)))
    anchors_t: list[float] = []
    anchors_v: list[float] = []
    residual = center - wheel
    for i0, i1, value in _runs(candidate):
        if value and i1 - i0 >= min_len:
            anchors_t.append(0.5 * (i0 + i1 - 1))
            anchors_v.append(float(np.median(residual[i0:i1])))
    if not anchors_t:
        return np.zeros_like(center), 0
    limit = np.deg2rad(cfg.straight_bias_max_correction_deg_s)
    anchors_v_array = np.clip(np.asarray(anchors_v, dtype=float), -limit, limit)
    if len(anchors_t) == 1:
        return np.full_like(center, anchors_v_array[0]), 1
    trace = np.interp(
        np.arange(len(center), dtype=float),
        np.asarray(anchors_t, dtype=float),
        anchors_v_array,
    )
    return np.clip(trace, -limit, limit), len(anchors_t)


def anchor_pause_bounded_uturns(
    t: np.ndarray,
    yaw_rate: np.ndarray,
    stationary: np.ndarray,
    *,
    config: ThreeIMUConfig | None = None,
) -> tuple[np.ndarray, int]:
    """Normalize pause-bounded near-U-turn segments to the declared 180-degree protocol turn."""
    cfg = config or ThreeIMUConfig()
    out = np.asarray(yaw_rate, dtype=float).copy()
    if not cfg.pause_turn_anchor_enabled:
        return out, 0
    t = np.asarray(t, dtype=float)
    stationary = np.asarray(stationary, dtype=bool)
    if not (len(t) == len(out) == len(stationary)) or len(t) < 3:
        return out, 0
    low = np.deg2rad(cfg.pause_turn_min_deg)
    high = np.deg2rad(cfg.pause_turn_max_deg)
    target = np.deg2rad(cfg.pause_turn_target_deg)
    lo_scale = max(0.0, 1.0 - cfg.pause_turn_max_scale_delta)
    hi_scale = 1.0 + cfg.pause_turn_max_scale_delta
    anchored = 0
    for i0, i1, moving in _runs(~stationary):
        if not moving or i0 <= 0 or i1 >= len(out) or i1 - i0 < 3:
            continue
        if not (stationary[i0 - 1] and stationary[i1]):
            continue
        angle = float(np.trapezoid(out[i0:i1], t[i0:i1]))
        magnitude = abs(angle)
        if not (low <= magnitude <= high) or magnitude <= 1e-9:
            continue
        scale = float(np.clip(target / magnitude, lo_scale, hi_scale))
        out[i0:i1] *= scale
        anchored += 1
    return out, anchored


def estimate_trajectory(
    imu: IMUSynchronized,
    calibration: ThreeIMUCalibration,
    *,
    config: ThreeIMUConfig | None = None,
) -> ThreeIMUEstimate:
    """Run the deployable IMU-only v2 backbone.  No C3D argument is accepted."""
    cfg = config or ThreeIMUConfig()
    p = raw_predictors(imu, config=cfg)
    fs = cfg.sample_rate_hz
    speed = calibration.speed_gain_mps_per_count * p["speed_raw"]
    center = calibration.center_yaw_gain_radps_per_count * p["center_yaw_raw"]
    wheel = calibration.wheel_yaw_gain_radps_per_count * p["wheel_yaw_raw"]
    speed = _smooth(speed, fs, cfg.smoothing_window_s)
    center = _smooth(center, fs, cfg.smoothing_window_s)
    wheel = _smooth(wheel, fs, cfg.smoothing_window_s)

    stationary = np.asarray(p["stationary"], dtype=bool)
    speed[stationary] = 0.0
    center[stationary] = 0.0
    wheel[stationary] = 0.0
    straight_bias, straight_bias_anchors = straight_yaw_bias_trace(
        center, wheel, speed, stationary, config=cfg
    )
    center = center - straight_bias
    center[stationary] = 0.0
    disagreement = np.abs(center - wheel)
    turn_scale = np.deg2rad(max(cfg.turn_scale_deg_s, 1e-3))
    turn_strength = np.clip(np.maximum(np.abs(center), np.abs(wheel)) / turn_scale, 0.0, 1.0)
    disagreement_strength = 1.0 - np.exp(-disagreement / np.deg2rad(max(cfg.disagreement_scale_deg_s, 1e-3)))
    weight = cfg.center_weight_straight + (cfg.center_weight_turn - cfg.center_weight_straight) * turn_strength
    weight += cfg.center_weight_disagreement_bonus * disagreement_strength
    weight = np.clip(weight, 0.0, 1.0)
    yaw_rate = weight * center + (1.0 - weight) * wheel
    dead = np.deg2rad(max(cfg.straight_deadband_deg_s, 0.0))
    near_straight = (np.abs(center) < 2.0 * dead) & (np.abs(wheel) < 3.0 * dead)
    yaw_rate[near_straight] = 0.0
    yaw_rate[stationary] = 0.0
    yaw_rate, anchored_turns = anchor_pause_bounded_uturns(
        imu.t, yaw_rate, stationary, config=cfg
    )
    xy, heading = integrate_se2(imu.t, speed, yaw_rate)
    quality = {
        "stationary_fraction": float(np.mean(stationary)),
        "mean_center_weight": float(np.mean(weight)),
        "straight_bias_anchors": float(straight_bias_anchors),
        "straight_bias_mean_deg_s": float(np.degrees(np.mean(straight_bias))),
        "yaw_disagreement_rmse_deg_s": float(np.degrees(np.sqrt(np.mean(np.square(center - wheel))))),
        "pause_turn_anchors": float(anchored_turns),
        "path_length_m": float(np.sum(np.linalg.norm(np.diff(xy, axis=0), axis=1))),
    }
    return ThreeIMUEstimate(
        t=imu.t.copy(),
        xy=xy,
        heading=heading,
        speed=speed,
        yaw_rate=yaw_rate,
        center_yaw_rate=center,
        wheel_yaw_rate=wheel,
        stationary=stationary,
        center_weight=weight,
        disagreement_rad_s=disagreement,
        bias_raw={"L_gz": p["bias_l"], "R_gz": p["bias_r"], "C_gx": p["bias_c"]},
        quality=quality,
    )


def apply_same_heading_constraint(
    estimate: ThreeIMUEstimate,
    *,
    max_correction_deg_s: float = 1.0,
) -> ThreeIMUEstimate:
    """Apply a known same-start/end-heading protocol constraint using IMU output only."""
    t = np.asarray(estimate.t, dtype=float)
    yaw = np.asarray(estimate.yaw_rate, dtype=float).copy()
    stationary = np.asarray(estimate.stationary, dtype=bool)
    if len(t) < 2:
        return estimate
    final_heading = float(np.trapezoid(yaw, t))
    closure_error = float(np.angle(np.exp(1j * final_heading)))
    moving = (~stationary).astype(float)
    moving_time = float(np.trapezoid(moving, t))
    if moving_time <= 1e-6:
        return estimate
    correction = closure_error / moving_time
    limit = np.deg2rad(abs(max_correction_deg_s))
    correction = float(np.clip(correction, -limit, limit))
    yaw[~stationary] -= correction
    yaw[stationary] = 0.0
    xy, heading = integrate_se2(t, estimate.speed, yaw)
    quality = dict(estimate.quality)
    quality.update(
        {
            "same_heading_constraint": 1.0,
            "heading_closure_before_deg": float(np.degrees(closure_error)),
            "heading_bias_correction_deg_s": float(np.degrees(correction)),
            "heading_closure_after_deg": float(
                np.degrees(np.angle(np.exp(1j * heading[-1])))
            ),
        }
    )
    return replace(
        estimate,
        xy=xy,
        heading=heading,
        yaw_rate=yaw,
        quality=quality,
    )


def _local_reference(reference: C3DReference) -> tuple[np.ndarray, np.ndarray]:
    valid_idx = np.flatnonzero(reference.valid & np.isfinite(reference.xy).all(axis=1) & np.isfinite(reference.heading))
    if len(valid_idx) == 0:
        raise ValueError("reference has no valid local origin")
    i0 = int(valid_idx[0])
    xy = reference.xy - reference.xy[i0]
    h0 = float(reference.heading[i0])
    c, s = np.cos(-h0), np.sin(-h0)
    rot = np.array([[c, -s], [s, c]], dtype=float)
    return xy @ rot.T, reference.heading - h0


def trajectory_metrics(
    reference: C3DReference,
    pred_xy: np.ndarray,
    pred_heading: np.ndarray,
    *,
    valid: np.ndarray | None = None,
) -> dict[str, float]:
    gt_xy, gt_heading = _local_reference(reference)
    pred_xy = np.asarray(pred_xy, dtype=float)
    pred_heading = np.asarray(pred_heading, dtype=float)
    n = min(len(gt_xy), len(pred_xy), len(pred_heading))
    mask = reference.valid[:n].copy()
    if valid is not None:
        mask &= np.asarray(valid, dtype=bool)[:n]
    mask &= np.isfinite(gt_xy[:n]).all(axis=1) & np.isfinite(pred_xy[:n]).all(axis=1)
    mask &= np.isfinite(gt_heading[:n]) & np.isfinite(pred_heading[:n])
    idx = np.flatnonzero(mask)
    if len(idx) < 2:
        raise ValueError("not enough valid frames for trajectory metrics")
    # Rebase prediction at first supervised frame; absolute starting pose is not
    # observable from IMU and must not be counted as drift.
    i0 = int(idx[0])
    pxy = pred_xy[:n] - pred_xy[i0]
    ph = pred_heading[:n] - pred_heading[i0]
    err = np.linalg.norm(pxy[idx] - gt_xy[:n][idx], axis=1)
    h_err = np.angle(np.exp(1j * (ph[idx] - gt_heading[:n][idx])))
    valid_steps = mask[1:] & mask[:-1]
    gt_step = np.linalg.norm(np.diff(gt_xy[:n], axis=0), axis=1)
    path_len = float(np.sum(gt_step[valid_steps]))
    last = int(idx[-1])
    endpoint = float(np.linalg.norm(pxy[last] - gt_xy[last]))
    ate = float(np.sqrt(np.mean(np.square(err))))
    return {
        "ate_rmse_m": ate,
        "ate_path_percent": 100.0 * ate / path_len if path_len > 1e-9 else float("nan"),
        "endpoint_error_m": endpoint,
        "endpoint_path_percent": 100.0 * endpoint / path_len if path_len > 1e-9 else float("nan"),
        "heading_rmse_deg": float(np.degrees(np.sqrt(np.mean(np.square(h_err))))),
        "final_heading_error_deg": float(np.degrees(abs(h_err[-1]))),
        "reference_path_length_m": path_len,
        "valid_fraction": float(np.mean(mask)),
    }


def evaluate_estimate(
    imu: IMUSynchronized,
    reference: C3DReference,
    estimate: ThreeIMUEstimate,
    *,
    lag_s: float,
) -> dict[str, float]:
    """Evaluate an already-computed IMU-only trajectory on the C3D timebase."""
    q = reference.t + float(lag_s)
    time_ok = (q >= estimate.t[0]) & (q <= estimate.t[-1])
    px = np.interp(q, estimate.t, estimate.xy[:, 0], left=np.nan, right=np.nan)
    py = np.interp(q, estimate.t, estimate.xy[:, 1], left=np.nan, right=np.nan)
    ph = np.interp(q, estimate.t, estimate.heading, left=np.nan, right=np.nan)
    metrics = trajectory_metrics(reference, np.column_stack([px, py]), ph, valid=time_ok)
    valid = reference.valid & time_ok
    pv = np.interp(q, estimate.t, estimate.speed, left=np.nan, right=np.nan)
    pw = np.interp(q, estimate.t, estimate.yaw_rate, left=np.nan, right=np.nan)
    if valid.sum() > 1:
        metrics["signed_speed_mae_mps"] = float(np.mean(np.abs(pv[valid] - reference.signed_speed[valid])))
        metrics["yaw_rate_mae_deg_s"] = float(np.degrees(np.mean(np.abs(pw[valid] - reference.yaw_rate[valid]))))
    return metrics


def oracle_decomposition(
    aligned: AlignedTrial,
    calibration: ThreeIMUCalibration,
    reference: C3DReference,
    *,
    config: ThreeIMUConfig | None = None,
) -> dict[str, dict[str, float]]:
    """Quantify speed-vs-yaw bottlenecks; never use these paths for inference."""
    cfg = config or ThreeIMUConfig()
    v = calibration.speed_gain_mps_per_count * aligned.speed_raw
    wc = calibration.center_yaw_gain_radps_per_count * aligned.center_yaw_raw
    ww = calibration.wheel_yaw_gain_radps_per_count * aligned.wheel_yaw_raw
    turn_strength = np.clip(np.maximum(np.abs(wc), np.abs(ww)) / np.deg2rad(cfg.turn_scale_deg_s), 0.0, 1.0)
    w_center = cfg.center_weight_straight + (cfg.center_weight_turn - cfg.center_weight_straight) * turn_strength
    yaw = w_center * wc + (1.0 - w_center) * ww
    v[aligned.stationary] = 0.0
    yaw[aligned.stationary] = 0.0

    # Fill label gaps only for numerical integration; metrics remain restricted
    # to the strict optical validity mask.
    idx = np.arange(len(reference.t), dtype=float)
    def filled(x: np.ndarray) -> np.ndarray:
        good = aligned.valid & np.isfinite(x)
        if good.sum() < 2:
            return np.nan_to_num(x)
        return np.interp(idx, idx[good], x[good])

    gt_v = filled(aligned.gt_speed)
    gt_w = filled(aligned.gt_yaw_rate)
    pred_v = filled(v)
    pred_w = filled(yaw)
    variants = {
        "imu_speed_imu_yaw": (pred_v, pred_w),
        "gt_speed_imu_yaw": (gt_v, pred_w),
        "imu_speed_gt_yaw": (pred_v, gt_w),
        "gt_speed_gt_yaw": (gt_v, gt_w),
    }
    out: dict[str, dict[str, float]] = {}
    for name, (vv, ww_) in variants.items():
        xy, h = integrate_se2(reference.t, vv, ww_)
        out[name] = trajectory_metrics(reference, xy, h, valid=aligned.valid)
    return out
