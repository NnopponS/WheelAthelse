"""Native-axis loading helpers for the private three-IMU research captures."""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np

ROLES = ("L", "R", "C")
SAMPLE_COLUMNS = ("ax_raw", "ay_raw", "az_raw", "gx_raw", "gy_raw", "gz_raw")


def unwrap_u32(values: np.ndarray) -> np.ndarray:
    """Unwrap a uint32 device clock without converting the raw source."""
    raw = np.asarray(values, dtype=np.uint64)
    if raw.ndim != 1:
        raise ValueError("device timestamps must be one-dimensional")
    out = raw.astype(np.int64)
    if len(out) < 2:
        return out
    wraps = np.cumsum(np.diff(raw.astype(np.int64)) < -(2**31), dtype=np.int64)
    out[1:] += wraps * 2**32
    return out


def marker_pair(labels: list[str], source_name: str = "") -> tuple[int, int]:
    """Return explicit left/right wheel-center indices; never use column order."""
    normalized = [str(label).strip() for label in labels]
    left_names = ("L_FAL", "L")
    if source_name.casefold() == "7.5_mspt_4.c3d":
        left_names = ("L_FCC",)
    left = next((normalized.index(name) for name in left_names if name in normalized), None)
    right = next(
        (normalized.index(name) for name in ("R_FAL", "R") if name in normalized),
        None,
    )
    if left is None or right is None:
        raise ValueError(f"No explicit wheel-center marker pair in {source_name or labels}")
    return left, right


def load_three_imu_export(
    path: str | Path,
    *,
    accel_scale: float | None = None,
    gyro_scale: float | None = None,
) -> dict[str, dict[str, object]]:
    """Split one long-format Windows export into native L/R/C streams."""
    grouped: dict[str, dict[str, list[object]]] = {
        role: {"samples": [], "device": [], "host": [], "seq": [], "missing": []}
        for role in ROLES
    }
    with Path(path).open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            role = str(row.get("wheel", "")).strip().upper()
            if role not in grouped:
                raise ValueError(f"Unsupported sensor role {role!r}")
            target = grouped[role]
            target["samples"].append([int(row[name]) for name in SAMPLE_COLUMNS])
            target["device"].append(int(row["timestamp_device_us"]))
            target["host"].append(int(row["timestamp_pc_monotonic_ns"]))
            target["seq"].append(int(row["seq"]))
            target["missing"].append(int(row.get("missing_before") or 0))

    result: dict[str, dict[str, object]] = {}
    for role, values in grouped.items():
        if not values["samples"]:
            raise ValueError(f"Missing required {role} sensor stream")
        samples = np.asarray(values["samples"], dtype=np.float64)
        if accel_scale is not None:
            samples[:, :3] *= float(accel_scale)
        if gyro_scale is not None:
            samples[:, 3:] *= float(gyro_scale)
        device_us = unwrap_u32(np.asarray(values["device"], dtype=np.uint32))
        result[role] = {
            "samples": samples,
            "t_device_s": (device_us - device_us[0]).astype(np.float64) / 1e6,
            "timestamp_device_us_unwrapped": device_us,
            "timestamp_pc_monotonic_ns": np.asarray(values["host"], dtype=np.int64),
            "seq": np.asarray(values["seq"], dtype=np.uint32),
            "missing_before": np.asarray(values["missing"], dtype=np.int64),
            "scale_provenance": "declared" if accel_scale is not None and gyro_scale is not None else "missing",
        }
    return result


def reconstruct_shared_time(
    streams: dict[str, dict[str, object]],
) -> dict[str, dict[str, float]]:
    """Fit each device clock to host packet time and add a shared time axis."""
    fits: dict[str, tuple[np.ndarray, float, float, float]] = {}
    for role in ROLES:
        if role not in streams:
            raise ValueError(f"Missing required {role} sensor stream")
        device = np.asarray(streams[role]["timestamp_device_us_unwrapped"], dtype=float)
        host = np.asarray(streams[role]["timestamp_pc_monotonic_ns"], dtype=float)
        if len(device) < 2 or len(device) != len(host):
            raise ValueError(f"{role} timestamps require matching multi-sample arrays")
        if np.any(np.diff(device) <= 0) or np.any(np.diff(host) < 0):
            raise ValueError(f"{role} timestamps must be monotonic before clock fitting")
        x = device - device.mean()
        denominator = float(np.dot(x, x))
        if denominator <= 0:
            raise ValueError(f"{role} device clock has no measurable span")
        scale = float(np.dot(x, host - host.mean()) / denominator)
        if scale <= 0:
            raise ValueError(f"{role} clock fit must have positive scale")
        intercept = float(host.mean() - scale * device.mean())
        predicted = intercept + scale * device
        rms_ns = float(np.sqrt(np.mean(np.square(host - predicted))))
        fits[role] = (predicted, scale, intercept, rms_ns)

    origin_ns = min(float(predicted[0]) for predicted, *_ in fits.values())
    quality: dict[str, dict[str, float]] = {}
    for role, (predicted, scale, _intercept, rms_ns) in fits.items():
        streams[role]["t_shared_s"] = (predicted - origin_ns) / 1e9
        quality[role] = {
            "clock_scale_ns_per_us": scale,
            "clock_drift_ppm": (scale / 1000.0 - 1.0) * 1e6,
            "host_fit_rms_ms": rms_ns / 1e6,
        }
    return quality


def fit_center_gyro_gain(
    bias_corrected_raw_gx: np.ndarray,
    optical_yaw_rate: np.ndarray,
) -> tuple[float, float]:
    """Fit calibration-turn sign and counts-to-rad/s gain through the origin."""
    raw = np.asarray(bias_corrected_raw_gx, dtype=float)
    optical = np.asarray(optical_yaw_rate, dtype=float)
    valid = np.isfinite(raw) & np.isfinite(optical)
    if valid.sum() < 3 or float(np.dot(raw[valid], raw[valid])) <= 0:
        raise ValueError("center gyro calibration needs at least three finite turning samples")
    slope = float(np.dot(raw[valid], optical[valid]) / np.dot(raw[valid], raw[valid]))
    return (-1.0 if slope < 0 else 1.0), abs(slope)


def center_yaw_gate(metrics: dict[str, object]) -> tuple[bool, dict[str, bool]]:
    """Apply the locked retrospective/final acceptance thresholds."""
    regressions = dict(metrics.get("maneuver_macro_regressions", {}))
    checks = {
        "coverage": float(metrics["coverage"]) >= 0.90,
        "yaw_rate_correlation": float(metrics["clean_turn_yaw_rate_correlation"]) >= 0.70,
        "turn_sign_accuracy": float(metrics["turn_sign_accuracy"]) >= 0.90,
        "heading_rmse_improvement": float(metrics["macro_heading_rmse_improvement"]) >= 0.20,
        "paired_ate": float(metrics["paired_ate_regression"]) <= 0.05,
        "maneuver_macros": bool(regressions)
        and all(float(value) <= 0.10 for value in regressions.values()),
    }
    return all(checks.values()), checks
