"""Read-only session loading with immutable acquisition provenance for analysis."""

from __future__ import annotations

import csv
import json
import math
from pathlib import Path

from tools.pc_acquisition.journal import JournalReader, RecordKind


def read_recording(
    journal_path: Path, manifest_path: Path, csv_path: Path, session_id: str
) -> dict:
    manifest = {}
    errors, warnings = [], []
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if not isinstance(manifest, dict):
                raise ValueError("Summary is not an object")
        except (OSError, ValueError) as exc:
            raise ValueError(f"Cannot read recording summary: {exc}") from exc
    capture, final, models, frozen_models, start = {}, {}, {}, {}, {}
    records = []
    if journal_path.exists():
        reader = JournalReader(journal_path)
        validation = reader.validate()
        if not validation.finalized:
            errors.append(
                "Recording is not finalized; review recovery before model analysis"
            )
        records = (
            reader.read_all()
        )  # CRC validation completes before any sample is returned.
        for record in records:
            value = record.json_value or {}
            if record.kind is RecordKind.SESSION_META:
                capture.update(value)
            elif record.kind is RecordKind.SYNC and not start:
                side = value.get("side")
                if side in {"L", "R"}:
                    models[side] = value
            elif record.kind is RecordKind.EVENT and value.get("type") == "START":
                if start:
                    errors.append(
                        "Multiple START epochs in one journal; split before analysis"
                    )
                else:
                    start, frozen_models = dict(value), dict(models)
            elif record.kind is RecordKind.FINALIZE:
                final.update(value)
    # Identity/names may be edited in a summary; physical conversion uses capture
    # metadata first, NEVER the currently connected board.
    meta = {**capture, **final, **manifest}
    physical = capture if capture else manifest
    scales, provenance = {}, {}
    rates = {}
    for side in ("L", "R"):
        board = physical.get("boards", {}).get(side, {})
        rates[side] = board.get("sample_rate_hz", physical.get("sample_rate_hz", 100))
        scales[side], provenance[side] = {}, {}
        for key, fallback in (
            ("accel_scale", 16.0 / 32768),
            ("gyro_scale", 2000.0 / 32768),
        ):
            supplied = board.get(key, physical.get(key))
            if supplied is None:
                val, source = fallback, "legacy_assumed_default"
                warnings.append(
                    f"{side} {key} was not recorded; legacy conversion assumed, not validated."
                )
            else:
                val = float(supplied)
                source = "journal_capture" if capture else "saved_summary_only"
                if not math.isfinite(val) or val <= 0:
                    raise ValueError(
                        f"Invalid captured {side} {key}; no live-board fallback"
                    )
            scales[side][key] = val
            provenance[side][key] = {"value": val, "source": source}
        provenance[side]["board_model"] = board.get(
            "hardware_model", board.get("board_model")
        )
        provenance[side]["firmware"] = board.get("firmware_version")
        provenance[side]["accel_range"] = board.get("accel_range")
        provenance[side]["gyro_range"] = board.get("gyro_range")
    if meta.get("quality", "UNKNOWN") != "GOOD":
        warnings.append("Original recording quality: " + str(meta.get("quality", "UNKNOWN"))
                        + "; reported reasons: " + str(meta.get("reasons", [])))
    samples = {"L": [], "R": []}
    gaps = []
    origin = None

    def append(side, seq, device, arrival, raw, missing=0, classification="contiguous"):
        nonlocal origin
        if side not in samples:
            raise ValueError("Invalid recording wheel ID")
        if origin is None:
            origin = arrival
        axes = [float(v) for v in raw]
        if not all(math.isfinite(v) for v in axes):
            raise ValueError("Nonfinite raw axes")
        t = (arrival - origin) / 1e9
        sc = scales[side]
        entry = {
            "t": t,
            "seq": seq,
            "t_device_us": device,
            "raw_clipped": any(v >= 32767 or v <= -32768 for v in axes),
            "sequence_class": classification,
        }
        for i, key in enumerate(("ax", "ay", "az", "gx", "gy", "gz")):
            entry[key] = axes[i] * sc["accel_scale" if i < 3 else "gyro_scale"]
        samples[side].append(entry)
        if missing or classification in ("gap", "out_of_order", "duplicate"):
            gaps.append(
                {
                    "side": side,
                    "time_s": t,
                    "seq": seq,
                    "missing": missing,
                    "reason": classification,
                }
            )

    if records:
        for record in records:
            if record.kind is RecordKind.SAMPLE and record.sample is not None:
                rec, sample = record.sample, record.sample.sample
                append(
                    rec.side.value,
                    sample.seq,
                    sample.t_device_us,
                    rec.arrival_ns,
                    [sample.ax, sample.ay, sample.az, sample.gx, sample.gy, sample.gz],
                    rec.missing_before,
                    rec.sequence_class,
                )
    elif csv_path.exists() and not journal_path.exists():
        warnings.append(
            "CSV-only session: saved pre-START clock mapping is unavailable."
        )
        with csv_path.open(encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                append(
                    row["wheel"],
                    int(row["seq"]),
                    int(row["timestamp_device_us"]),
                    int(row["timestamp_pc_monotonic_ns"]),
                    [row[k + "_raw"] for k in ("ax", "ay", "az", "gx", "gy", "gz")],
                    int(row.get("missing_before", 0)),
                    row.get("sequence_class", "contiguous"),
                )
    if not any(samples.values()):
        errors.append("No readable recorded samples")
    timing = {"basis": "legacy_sequence_arrival_anchor", "side_sample_rates": rates}
    if start and set(frozen_models) == {"L", "R"}:
        timing.update(
            basis="saved_device_affine", clock_models=frozen_models, start=start
        )
    else:
        warnings.append(
            "Complete pre-START dual-wheel clock evidence is absent; legacy timing is explicitly uncertain."
        )
    return {
        "session_id": session_id,
        "topic": meta.get("topic", ""),
        "trial_number": meta.get("trial_number", ""),
        "athlete": meta.get("athlete", ""),
        "quality": meta.get("quality", "UNKNOWN"),
        "sample_rate_hz": physical.get("sample_rate_hz", 100),
        "duration_s": meta.get(
            "duration_s", max((s[-1]["t"] for s in samples.values() if s), default=0.0)
        ),
        "samples": samples,
        "gaps": gaps,
        "total_missing_samples": sum(g["missing"] for g in gaps),
        "analysis_timing": timing,
        "analysis_warnings": list(dict.fromkeys(warnings)),
        "analysis_errors": errors,
        "scale_provenance": provenance,
        "source_recording": str(journal_path if journal_path.exists() else csv_path),
    }
