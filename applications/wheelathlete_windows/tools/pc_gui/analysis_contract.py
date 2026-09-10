"""Versioned offline kinematics contract and full-resolution window statistics.

No estimator tuning, reference fitting, or UI dependencies. Shared definitions
are mirrored in mobile analysis_contract.dart and checked using common fixtures.
"""

from __future__ import annotations

import bisect
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Sequence

FIELDS = (
    "time_s",
    "x_m",
    "y_m",
    "signed_speed_mps",
    "speed_mps",
    "longitudinal_accel_mps2",
    "yaw_rad",
    "yaw_rate_radps",
    "lateral_accel_mps2",
    "speed_change_mps2",
)
OPTIONAL_FIELDS = FIELDS[3:]
DERIVATIVE_HALF = 3


def _finite(value: Any, name: str) -> float:
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
    ):
        raise ValueError(f"{name} must be finite numeric data")
    return float(value)


def derivative(
    times: Sequence[float],
    values: Sequence[float | None],
    invalid: Sequence[bool] | None = None,
) -> list[float | None]:
    """Seven-sample centered local-linear slope on actual times, never padded.

    On a uniform grid this is the centered SG(7,2) first derivative. For irregular
    time it is explicitly a local LINEAR least-squares fit (not quadratic SG).
    An invalid input or a >75ms model-step gap invalidates the complete stencil.
    """
    n = len(times)
    if len(values) != n or (invalid is not None and len(invalid) != n):
        raise ValueError("Derivative lengths differ")
    ts = [_finite(t, "derivative time") for t in times]
    if any(b <= a for a, b in zip(ts, ts[1:])):
        raise ValueError("Derivative times must increase strictly")
    for v in values:
        if v is not None:
            _finite(v, "derivative value")
    result: list[float | None] = [None] * n
    for i in range(DERIVATIVE_HALF, n - DERIVATIVE_HALF):
        a, b = i - DERIVATIVE_HALF, i + DERIVATIVE_HALF + 1
        segment = values[a:b]
        if any(v is None for v in segment) or (
            invalid is not None and any(invalid[a:b])
        ):
            continue
        t = [v - ts[i] for v in ts[a:b]]
        if any(v - u > 0.075 + 1e-9 for u, v in zip(t, t[1:])):
            continue
        tm = sum(t) / len(t)
        vm = sum(segment) / len(segment)
        denominator = sum((u - tm) ** 2 for u in t)
        result[i] = sum((u - tm) * (v - vm) for u, v in zip(t, segment)) / denominator
    return result


def build_analysis(
    *,
    times: list[float],
    xy: list[list[float]],
    flags: list[list[str]],
    signed_speed: list[float] | None = None,
    yaw: list[float] | None = None,
    yaw_rate: list[float] | None = None,
    metadata: dict | None = None,
) -> dict:
    n = len(times)
    if n < 2 or len(xy) != n or len(flags) != n:
        raise ValueError("Analysis needs equal lengths and at least two samples")
    for name, a in [
        ("signed speed", signed_speed),
        ("yaw", yaw),
        ("yaw rate", yaw_rate),
    ]:
        if a is not None and len(a) != n:
            raise ValueError(name + " length differs from analysis time")
    invalid = [
        bool(set(f) & {"small_gap_interpolated", "sensor_clipping", "input_invalid"})
        for f in flags
    ]
    if signed_speed is None:
        dx = derivative(times, [p[0] for p in xy], invalid)
        dy = derivative(times, [p[1] for p in xy], invalid)
        speed = [
            None if a is None or b is None else math.hypot(a, b) for a, b in zip(dx, dy)
        ]
        accel = [None] * n
    else:
        speed = [abs(v) for v in signed_speed]
        accel = derivative(times, signed_speed, invalid)
    speed_change = derivative(times, speed, invalid)
    samples = []
    for i in range(n):
        f = list(flags[i])
        if signed_speed is None:
            f.append("xy_only_model")
        if accel[i] is None and signed_speed is not None:
            f.append("derivative_support_unavailable")
        samples.append(
            dict(
                zip(
                    FIELDS,
                    [
                        times[i],
                        xy[i][0],
                        xy[i][1],
                        None if signed_speed is None else signed_speed[i],
                        speed[i],
                        accel[i],
                        None if yaw is None else yaw[i],
                        None if yaw_rate is None else yaw_rate[i],
                        None,
                        speed_change[i],
                    ],
                ),
                quality_flags=sorted(set(f)),
            )
        )
    meta = dict(metadata or {})
    meta.update(
        {
            "schema_version": 1,
            "algorithm_contract": "wheelathlete.offline_kinematics.v1",
            "mode": "offline",
            "sample_rate_hz": 20.0,
            "sample_semantics": "five-input-sample window center; one full-session pose state",
            "model_validation_status": "not_independently_validated",
            "physical_sync_verified": False,
            "derivative": {
                "method": "centered_local_linear_7",
                "half_window_samples": 3,
                "nominal_support_span_s": 0.30,
                "edge_policy": "null",
                "gap_or_clipping_support": "null",
            },
            "live_latency": "undefined_offline_whole_session",
            "lateral_accel_reason": "not exposed without validated no-slip support",
            "signed_speed_reason": "estimator output"
            if signed_speed is not None
            else "unavailable from XY-only output",
            "speed_reason": "absolute estimator signed speed"
            if signed_speed is not None
            else "XY local-linear derivative magnitude; not signed chair speed",
            "yaw_reason": "estimator orientation, unwrapped"
            if yaw is not None
            else "unavailable; trajectory tangent is not chair orientation",
            "coverage": {
                "samples": n,
                "input_unflagged_samples": sum(not v for v in invalid),
                "longitudinal_accel_samples": sum(v is not None for v in accel),
                "speed_samples": sum(v is not None for v in speed),
            },
        }
    )
    result = {"schema_version": 1, "metadata": meta, "samples": samples}
    validate_analysis(result)
    return result


def _validate_json_metadata(value: Any) -> None:
    """Match Dart's JSON-only metadata contract; keys must remain strings."""
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                raise ValueError("Metadata keys must be strings")
            _validate_json_metadata(item)
    elif isinstance(value, list):
        for item in value:
            _validate_json_metadata(item)
    elif value is not None and not isinstance(value, (str, bool, int, float)):
        raise ValueError("Metadata must be JSON-compatible")


def validate_analysis(value: dict) -> None:
    if (
        not isinstance(value, dict)
        or isinstance(value.get("schema_version"), bool)
        or value.get("schema_version") != 1
    ):
        raise ValueError("Unsupported analysis schema")
    samples = value.get("samples")
    if (
        not isinstance(samples, list)
        or len(samples) < 2
        or not isinstance(value.get("metadata"), dict)
    ):
        raise ValueError("Invalid analysis container")
    # Serialization catches cycles/nonfinite values before recursive key checks.
    try:
        json.dumps(value["metadata"], allow_nan=False)
    except (TypeError, OverflowError, RecursionError) as exc:
        raise ValueError("Metadata must be finite JSON-compatible data") from exc
    _validate_json_metadata(value["metadata"])
    previous = -math.inf
    for row in samples:
        if not isinstance(row, dict) or not all(k in row for k in FIELDS):
            raise ValueError("Missing analysis sample fields")
        t = _finite(row["time_s"], "time_s")
        if t <= previous or t < 0:
            raise ValueError(
                "Analysis time must be nonnegative and strictly increasing"
            )
        previous = t
        _finite(row["x_m"], "x_m")
        _finite(row["y_m"], "y_m")
        for key in OPTIONAL_FIELDS:
            if row[key] is not None:
                _finite(row[key], key)
        if row["speed_mps"] is not None and row["speed_mps"] < 0:
            raise ValueError("Speed magnitude cannot be negative")
        if row["signed_speed_mps"] is not None and row["speed_mps"] is not None:
            if abs(abs(row["signed_speed_mps"]) - row["speed_mps"]) > 1e-6:
                raise ValueError("Signed speed and magnitude disagree")
        f = row.get("quality_flags")
        if not isinstance(f, list) or not all(isinstance(v, str) for v in f):
            raise ValueError("Invalid quality flags")
    json.dumps(
        value, allow_nan=False
    )  # Reject nonfinite numbers anywhere, including metadata.


def nearest_index(times: Sequence[float], time_s: float) -> int:
    if not times:
        raise ValueError("Empty timeline")
    time_s = _finite(time_s, "cursor time")
    i = bisect.bisect_left(times, time_s)
    if i == 0:
        return 0
    if i == len(times):
        return i - 1
    return i - 1 if time_s - times[i - 1] <= times[i] - time_s + 1e-12 else i


def window_statistics(analysis: dict, start_s: float, stop_s: float) -> dict:
    """Inclusive sample centers; no pose reset and no derivative recomputation."""
    start_s, stop_s = _finite(start_s, "window start"), _finite(stop_s, "window stop")
    if stop_s < start_s:
        raise ValueError("Window stop precedes start")
    samples = analysis["samples"]
    times = [p["time_s"] for p in samples]
    lo, hi = (
        bisect.bisect_left(times, start_s - 1e-12),
        bisect.bisect_right(times, stop_s + 1e-12),
    )
    chosen = samples[lo:hi]
    metrics = {}
    for field in OPTIONAL_FIELDS:
        available = [p[field] for p in chosen if p[field] is not None]
        total = support = 0.0
        for a, b in zip(chosen, chosen[1:]):
            dt = b["time_s"] - a["time_s"]
            if a[field] is not None and b[field] is not None and dt <= 0.075 + 1e-9:
                total += 0.5 * (a[field] + b[field]) * dt
                support += dt
        metrics[field] = {
            "samples": len(available),
            "mean": total / support if support else None,
            "min": min(available) if available else None,
            "max": max(available) if available else None,
            "supported_duration_s": support,
        }
    path = sum(
        math.hypot(b["x_m"] - a["x_m"], b["y_m"] - a["y_m"])
        for a, b in zip(chosen, chosen[1:])
    )
    net_yaw = None
    if (
        len(chosen) > 1
        and chosen[0]["yaw_rad"] is not None
        and chosen[-1]["yaw_rad"] is not None
    ):
        net_yaw = chosen[-1]["yaw_rad"] - chosen[0]["yaw_rad"]
    return {
        "start_index": lo,
        "stop_index_exclusive": hi,
        "samples": len(chosen),
        "duration_s": times[hi - 1] - times[lo] if len(chosen) > 1 else 0.0,
        "path_length_m": path,
        "net_yaw_rad": net_yaw,
        "metrics": metrics,
        "quality_flags": sorted({f for p in chosen for f in p["quality_flags"]}),
        "interpretation": "descriptive experimental estimates; time-weighted means; no independent accuracy claim",
    }


def file_identity(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()
