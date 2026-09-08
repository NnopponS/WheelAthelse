"""Offline timing/QC only. Never changes acquisition files or estimates clock lag."""

from __future__ import annotations

import math
from typing import Any

import numpy as np

UINT32 = 1 << 32
HALF32 = 1 << 31
MAX_BRACKET_S = 0.050  # Explicit analysis policy, not an acquisition quality grade.
CHANNELS = ("ax", "ay", "az", "gx", "gy", "gz")


class AnalysisInputError(ValueError):
    """The recording cannot support this offline analysis safely."""


def finite_number(value: Any, name: str) -> float:
    if isinstance(value, bool):
        raise AnalysisInputError(f"{name} must be a finite number")
    try:
        number = float(value)
    except (TypeError, ValueError, OverflowError) as exc:
        raise AnalysisInputError(f"{name} must be a finite number") from exc
    if not math.isfinite(number):
        raise AnalysisInputError(f"{name} must be finite")
    return number


def counter(value: Any, name: str) -> int:
    number = finite_number(value, name)
    if number != int(number) or not 0 <= number < UINT32:
        raise AnalysisInputError(f"{name} is not a uint32 counter")
    return int(number)


def ordered_samples(
    samples: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], np.ndarray, dict]:
    """Unwrap sequence in receipt order, then place replayed samples in their epoch.

    Conflicting repeats or backwards device time are not repaired. At most one
    uint32 epoch is distinguishable without an external epoch identifier.
    """
    if not isinstance(samples, list) or len(samples) < 2:
        raise AnalysisInputError("Both wheels need at least two samples")
    have_seq = ["seq" in row for row in samples]
    if any(have_seq) and not all(have_seq):
        raise AnalysisInputError("Partially missing sequence counters")
    if not all(have_seq):
        rows = list(samples)
        return (
            rows,
            np.arange(len(rows), dtype=np.int64),
            {
                "sequence_unavailable": True,
                "duplicates": 0,
                "reordered": 0,
                "rollovers": 0,
            },
        )
    anchor_raw = counter(samples[0]["seq"], "seq")
    anchor = 0
    unique: dict[int, dict] = {}
    duplicates = reordered = rollovers = 0
    for row in samples:
        raw = counter(row["seq"], "seq")
        diff = (raw - anchor_raw + HALF32) % UINT32 - HALF32
        if diff == -HALF32:
            raise AnalysisInputError("Ambiguous sequence epoch")
        position = anchor + diff
        # Time of receipt is not part of a sample's identity (BLE replay).
        signature = tuple(finite_number(row.get(c), c) for c in CHANNELS)
        if "t_device_us" in row:
            signature += (counter(row["t_device_us"], "t_device_us"),)
        if position in unique:
            existing = unique[position]
            old = tuple(finite_number(existing.get(c), c) for c in CHANNELS)
            if "t_device_us" in existing:
                old += (counter(existing["t_device_us"], "t_device_us"),)
            if signature != old:
                raise AnalysisInputError(
                    "Conflicting duplicate sequence or device reset; split the recording"
                )
            duplicates += 1
            continue
        unique[position] = row
        if diff > 0:
            rollovers += int(raw < anchor_raw)
            anchor, anchor_raw = position, raw
        elif diff < 0:
            reordered += 1
    keys = sorted(unique)
    if len(keys) < 2 or keys[-1] - keys[0] >= HALF32:
        raise AnalysisInputError(
            "Insufficient samples or ambiguous long sequence epoch"
        )
    return (
        [unique[k] for k in keys],
        np.asarray(keys, dtype=np.int64),
        {
            "sequence_unavailable": False,
            "duplicates": duplicates,
            "reordered": reordered,
            "rollovers": rollovers,
        },
    )


def map_device_clock(
    rows: list[dict], model: dict, start: dict, side: str
) -> np.ndarray:
    """Map raw device micros using the saved PRE-START affine model and T0.

    The inverse model reconstructs the scheduled uint32 epoch; no board clock is
    zeroed independently and no packet arrival timestamp is used as an offset.
    Mapping reproducibility is not physical synchronization certification.
    """
    slope = finite_number(model.get("slope_ns_per_us"), "clock slope")
    intercept = finite_number(model.get("intercept_ns"), "clock intercept")
    t0 = finite_number(start.get("pc_start_ns"), "recording start")
    if not 900 <= slope <= 1100:
        raise AnalysisInputError(
            "Saved clock slope is unusable (outside +/-10% of nominal); no silent fallback"
        )
    if finite_number(model.get("observation_count"), "clock observations") < 1:
        raise AnalysisInputError("Saved clock has no observations")
    for key in ("residual_rms_ns", "best_rtt_ns", "median_rtt_ns"):
        if finite_number(model.get(key), key) < 0:
            raise AnalysisInputError("Negative saved clock diagnostic")
    target = counter(
        start.get("target_device_us", {}).get(side), "scheduled device target"
    )
    epoch = round((t0 - intercept) / slope)
    mismatch = (target - (epoch % UINT32) + HALF32) % UINT32 - HALF32
    if abs(mismatch) > 2:
        raise AnalysisInputError(
            "Saved clock and scheduled START belong to different epochs/models"
        )
    raw = np.asarray(
        [counter(row.get("t_device_us"), "t_device_us") for row in rows], dtype=np.int64
    )
    first = epoch + ((int(raw[0]) - target + HALF32) % UINT32 - HALF32)
    delta = (np.diff(raw) + UINT32) % UINT32
    if np.any(delta == 0) or np.any(delta >= HALF32):
        raise AnalysisInputError(
            "Device clock reset, duplicate time, or ambiguous rollover"
        )
    unwrapped = first + np.r_[0, np.cumsum(delta)]
    return (slope * unwrapped.astype(np.float64) + intercept - t0) / 1e9


def prepare_side(
    samples: list[dict], source_hz: float, *, side: str, timing: dict
) -> tuple[np.ndarray, np.ndarray, np.ndarray, dict]:
    rows, seq, info = ordered_samples(samples)
    values = np.asarray(
        [[finite_number(row.get(c), c) for c in CHANNELS] for row in rows],
        dtype=np.float64,
    )
    supplied = np.asarray([finite_number(row.get("t"), "sample time") for row in rows])
    models, start = timing.get("clock_models", {}), timing.get("start", {})
    if models or start:
        if not {"L", "R"}.issubset(models) or not start:
            raise AnalysisInputError("Incomplete saved dual-wheel clock mapping")
        times = map_device_clock(rows, models[side], start, side)
        basis = "saved_device_affine"
    elif timing.get("basis") == "declared_recording_relative":
        times = supplied.copy()
        basis = "declared_recording_relative"
    else:
        # Older loader results have receipt-relative t; preserve their common
        # origin but explicitly retain the nominal-cadence approximation.
        if info["sequence_unavailable"]:
            times = supplied.copy()
            basis = "legacy_supplied_time"
        else:
            times = supplied[0] + (seq - seq[0]).astype(float) / source_hz
            basis = "legacy_sequence_arrival_anchor"
    if np.any(np.diff(times) <= 0):
        raise AnalysisInputError(
            "Nonmonotonic analysis clock; no sorting or fallback can certify it"
        )
    if any("t_device_us" in row for row in rows) and not all(
        "t_device_us" in row for row in rows
    ):
        raise AnalysisInputError("Partially missing device timestamps")
    # Validate device resets even when a legacy nominal timeline is used.
    if all("t_device_us" in row for row in rows):
        raw = np.array(
            [counter(row["t_device_us"], "t_device_us") for row in rows], dtype=np.int64
        )
        d = np.diff(raw) % UINT32
        if np.any(d == 0) or np.any(d >= HALF32):
            raise AnalysisInputError("Device timestamp reset or duplicate timestamp")
        if np.any(d / 1e6 > MAX_BRACKET_S + 1e-9):
            raise AnalysisInputError(
                "Device clock reveals a gap exceeding 0.05 s; no nominal-cadence concealment"
            )
    missing = (
        np.maximum(np.diff(seq) - 1, 0)
        if not info["sequence_unavailable"]
        else np.zeros(len(rows) - 1, dtype=int)
    )
    gaps = np.diff(times)
    if np.any(gaps > MAX_BRACKET_S + 1e-9) or (
        len(missing) and np.any(missing / source_hz > MAX_BRACKET_S)
    ):
        raise AnalysisInputError(
            f"{side} recording has a gap exceeding {MAX_BRACKET_S:g} s; analysis refused, raw data preserved"
        )
    clipped = np.asarray([bool(row.get("raw_clipped", False)) for row in rows])
    info.update(
        time_basis=basis,
        source_samples=len(samples),
        unique_samples=len(rows),
        missing_sequences=int(missing.sum()),
        max_bracket_s=float(gaps.max()),
        clipped_samples=int(clipped.sum()),
        sequence_gap_after=np.r_[missing > 0, False].tolist(),
    )
    return times, values, clipped, info


def prepare_windows(session: dict, *, target_hz: int = 100) -> tuple[np.ndarray, dict]:
    if target_hz != 100:
        raise AnalysisInputError(
            "The frozen model requires the 100 Hz / five-sample input contract"
        )
    if session.get("analysis_errors"):
        raise AnalysisInputError("; ".join(session["analysis_errors"]))
    source_hz = finite_number(session.get("sample_rate_hz", target_hz), "source rate")
    if not 20 <= source_hz <= 1000:
        raise AnalysisInputError("Source sample rate must be between 20 and 1000 Hz")
    samples = session.get("samples", {})
    timing = session.get("analysis_timing", {})
    per_rate = timing.get("side_sample_rates", {})
    prepared = {}
    for side in ("L", "R"):
        rate = finite_number(per_rate.get(side, source_hz), "side sample rate")
        if abs(rate - source_hz) > 1e-6:
            raise AnalysisInputError("Mismatched left/right configured sample rates")
        prepared[side] = prepare_side(
            samples.get(side, []), rate, side=side, timing=timing
        )
    start = max(0.0, *(v[0][0] for v in prepared.values()))
    stop = min(v[0][-1] for v in prepared.values())
    if stop <= start:
        raise AnalysisInputError("Left and right wheel timelines do not overlap")
    count = int(np.floor((stop - start) * target_hz + 1e-7)) + 1
    usable = count // 5 * 5
    if usable < 200:
        raise AnalysisInputError(
            "Recording needs at least 2.0 s of overlapping dual-wheel data"
        )
    grid = start + np.arange(usable, dtype=float) / target_hz
    matrices, gap_masks, clip_masks = [], [], []
    for side in ("L", "R"):
        t, x, clips, info = prepared[side]
        i = np.searchsorted(t, grid, side="right") - 1
        i = np.clip(i, 0, len(t) - 2)
        exact = (np.abs(grid - t[i]) <= 1e-8) | (np.abs(grid - t[i + 1]) <= 1e-8)
        bracket = t[i + 1] - t[i]
        explicit_gap = np.asarray(info["sequence_gap_after"], dtype=bool)[i]
        gap_masks.append(~exact & ((bracket > 1.5 / source_hz + 1e-9) | explicit_gap))
        clip_masks.append(clips[i] | clips[i + 1])
        z = np.column_stack([np.interp(grid, t, x[:, j]) for j in range(6)])
        z[:, :3] *= 9.80665
        z[:, 3:] *= np.pi / 180
        matrices.append(z)
    windows = np.concatenate(matrices, axis=1).astype(np.float32).reshape(-1, 5, 12)
    if not np.isfinite(windows).all():
        raise AnalysisInputError("SI conversion overflowed the model input")
    gap20 = np.logical_or(*gap_masks).reshape(-1, 5).any(axis=1)
    clip20 = np.logical_or(*clip_masks).reshape(-1, 5).any(axis=1)
    flags = [[] for _ in range(len(windows))]
    for i in range(len(flags)):
        if gap20[i]:
            flags[i].append("small_gap_interpolated")
        if clip20[i]:
            flags[i].append("sensor_clipping")
    warnings = list(session.get("analysis_warnings", []))
    basis = prepared["L"][3]["time_basis"]
    if basis != prepared["R"][3]["time_basis"]:
        raise AnalysisInputError("The two wheels do not share a time-basis policy")
    warnings.append(
        "Offline experimental estimate; physical accuracy and inter-hub synchronization are not certified."
    )
    if basis.startswith("legacy"):
        warnings.append(
            "Legacy timing: nominal sequence cadence anchored to arrival time; acquisition synchronization is unknown."
        )
    elif basis == "saved_device_affine":
        warnings.append(
            "Saved pre-START affine clocks used; BLE midpoint bias and physical synchronization remain unverified."
        )
    if abs(source_hz - target_hz) > 1e-6:
        warnings.append(f"Resampled {source_hz:g} Hz recording to 100 Hz.")
    reported = int(session.get("total_missing_samples", 0) or 0)
    missing = sum(v[3]["missing_sequences"] for v in prepared.values())
    if reported or missing or gap20.any():
        warnings.append(
            f"Recording reports {reported} missing sample(s); {missing} sequence holes remain; small interpolated windows are flagged."
        )
    if clip20.any():
        warnings.append(
            "Raw int16 sensor clipping detected; derivative metrics near these windows are unavailable."
        )
    return windows, {
        "source_hz": source_hz,
        "target_hz": target_hz,
        "raw_left_samples": len(samples["L"]),
        "raw_right_samples": len(samples["R"]),
        "aligned_samples": usable,
        "model_steps": len(windows),
        "duration_s": usable / target_hz,
        "resampled": abs(source_hz - target_hz) > 1e-6,
        "missing_samples": max(reported, missing),
        "warnings": list(dict.fromkeys(warnings)),
        "time_s": grid.reshape(-1, 5).mean(axis=1).tolist(),
        "overlap_start_s": float(start),
        "last_raw_sample_s": float(grid[-1]),
        "discarded_tail_samples": count - usable,
        "time_basis": basis,
        "clock_evidence": timing,
        "quality_flags": flags,
        "side_diagnostics": {k: v[3] for k, v in prepared.items()},
        "input_gap_policy": {
            "maximum_bracket_s": MAX_BRACKET_S,
            "large_gap": "reject",
            "small_gap": "interpolate_and_flag",
        },
        "scale_provenance": session.get("scale_provenance", {"status": "not_recorded"}),
        "physical_sync_verified": False,
    }
