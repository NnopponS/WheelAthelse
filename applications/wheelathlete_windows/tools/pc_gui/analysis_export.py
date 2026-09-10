"""Create-only derived analysis export. Original recordings are never written."""

from __future__ import annotations

import csv
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile

from .analysis_contract import FIELDS, validate_analysis, window_statistics


def export_analysis(
    analysis: dict,
    parent: Path,
    *,
    start_s: float | None = None,
    stop_s: float | None = None,
) -> Path:
    validate_analysis(analysis)
    parent = Path(parent)
    if not parent.is_dir():
        raise ValueError("Choose an existing export directory")
    samples = analysis["samples"]
    start = samples[0]["time_s"] if start_s is None else start_s
    stop = samples[-1]["time_s"] if stop_s is None else stop_s
    stats = window_statistics(analysis, start, stop)
    session = (
        re.sub(
            r"[^A-Za-z0-9_-]",
            "_",
            str(analysis["metadata"].get("session_id", "session")),
        )[:64]
        or "session"
    )
    out = Path(
        tempfile.mkdtemp(prefix="WheelAthlete_analysis_" + session + "_", dir=parent)
    )
    try:
        timeline = out / "timeline.csv"
        with timeline.open("x", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=[*FIELDS, "quality_flags"])
            writer.writeheader()
            for sample in samples:
                writer.writerow(
                    {
                        **{k: sample[k] for k in FIELDS},
                        "quality_flags": json.dumps(
                            sample["quality_flags"], ensure_ascii=True
                        ),
                    }
                )
            handle.flush()
            os.fsync(handle.fileno())
        metadata = {
            "schema_version": 1,
            "export_type": "wheelathlete_derived_analysis",
            "metadata": analysis["metadata"],
            "columns": list(FIELDS) + ["quality_flags"],
            "row_count": len(samples),
            "null_encoding": "empty CSV numeric cell; JSON null",
            "timeline_sha256": hashlib.sha256(timeline.read_bytes()).hexdigest(),
            "selected_window": {
                "requested_start_s": start,
                "requested_stop_s": stop,
                **stats,
            },
            "export_scope": "full-resolution full-session timeline; selected window is metadata only; no pose reset",
        }
        with (out / "metadata.json").open("x", encoding="utf-8") as handle:
            json.dump(metadata, handle, ensure_ascii=False, allow_nan=False, indent=2)
            handle.flush()
            os.fsync(handle.fileno())
        # Completion marker is written last. Readers must require this marker
        # and verify the CSV hash before treating the export as complete.
        with (out / "COMPLETE").open("x", encoding="utf-8") as handle:
            handle.write(metadata["timeline_sha256"] + "\n")
        return out
    except Exception as exc:
        raise OSError(
            f"Analysis export did not complete. Incomplete files remain at {out}; no existing file was replaced. {exc}"
        ) from exc
