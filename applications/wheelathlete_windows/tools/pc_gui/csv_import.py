"""Safe import and re-export of WheelAthlete raw session CSVs."""

from __future__ import annotations

import csv
from datetime import datetime, timezone
import json
import os
import shutil
from pathlib import Path
import tempfile
from typing import Any
from uuid import uuid4


_REQUIRED_COLUMNS = {
    "session_id", "wheel", "seq", "timestamp_device_us",
    "ax_raw", "ay_raw", "az_raw", "gx_raw", "gy_raw", "gz_raw",
}
_DATE_COLUMNS = (
    "started_utc_ms", "recorded_utc_ms", "finalized_utc_ms",
    "recorded_at", "date",
)


class ImportDateRequired(ValueError):
    """Raised when an imported recording has no date and needs operator input."""


def default_import_library_root() -> Path:
    return Path.home() / "Documents" / "WheelAthlete" / "Imported CSV"


def _recording_date_ms(value: Any, field: str) -> int | None:
    text = str(value or "").strip()
    if not text:
        return None
    if field.endswith("_utc_ms"):
        try:
            numeric = float(text)
            if numeric.is_integer() and numeric > 0:
                return int(numeric)
        except ValueError:
            pass
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp() * 1000)


def read_wheelathlete_csv(source: str | Path) -> dict[str, Any]:
    """Validate the exported raw-sample schema and summarize one session."""
    path = Path(source)
    if path.suffix.lower() != ".csv":
        raise ValueError("Choose a WheelAthlete CSV file")
    sample_counts = {"L": 0, "R": 0, "C": 0}
    pc_times: list[int] = []
    started_utc_ms = None
    session_ids: set[str] = set()
    try:
        with path.open("r", newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            fields = {str(name or "").strip().lower(): name for name in (reader.fieldnames or [])}
            if not _REQUIRED_COLUMNS.issubset(fields):
                raise ValueError("CSV is not a WheelAthlete CSV export")
            for row in reader:
                if not row or not any(str(value or "").strip() for value in row.values()):
                    continue
                side = str(row.get(fields["wheel"]) or "").strip().upper()
                if side not in sample_counts:
                    raise ValueError(f"CSV contains an unknown sensor role: {side or 'blank'}")
                session_id = str(row.get(fields["session_id"]) or "").strip()
                if not session_id:
                    raise ValueError("CSV sample is missing its session ID")
                session_ids.add(session_id)
                int(str(row.get(fields["seq"]) or ""))
                int(str(row.get(fields["timestamp_device_us"]) or ""))
                for name in ("ax_raw", "ay_raw", "az_raw", "gx_raw", "gy_raw", "gz_raw"):
                    int(str(row.get(fields[name]) or ""))
                sample_counts[side] += 1
                pc_time = row.get(fields.get("timestamp_pc_monotonic_ns", ""))
                if pc_time:
                    pc_times.append(int(str(pc_time)))
                if started_utc_ms is None:
                    for key in _DATE_COLUMNS:
                        if key in fields:
                            started_utc_ms = _recording_date_ms(row.get(fields[key]), key)
                            if started_utc_ms is not None:
                                break
    except (csv.Error, OSError, UnicodeError, TypeError) as exc:
        raise ValueError(f"Could not read WheelAthlete CSV: {exc}") from exc
    except (KeyError, ValueError) as exc:
        if isinstance(exc, ValueError) and str(exc).startswith("CSV "):
            raise
        raise ValueError(f"WheelAthlete CSV contains an invalid sample: {exc}") from exc

    if sum(sample_counts.values()) == 0:
        raise ValueError("WheelAthlete CSV contains no samples")
    if len(session_ids) != 1:
        raise ValueError("CSV must contain samples from exactly one WheelAthlete session")
    duration_s = (
        max(0, max(pc_times) - min(pc_times)) / 1_000_000_000 if pc_times else 0.0
    )
    return {
        "source_session_id": next(iter(session_ids)),
        "sample_counts": sample_counts,
        "duration_s": duration_s,
        "started_utc_ms": started_utc_ms,
    }


def _copy_create_only(source: Path, target_directory: Path, requested_name: str) -> Path:
    target_directory.mkdir(parents=True, exist_ok=True)
    requested = Path(requested_name)
    suffix = requested.suffix or source.suffix
    stem = requested.stem or source.stem
    index = 1
    while True:
        name = requested.name if index == 1 else f"{stem}_{index}{suffix}"
        target = target_directory / name
        if target.exists():
            index += 1
            continue
        descriptor, temp_name = tempfile.mkstemp(
            prefix=".wa-", suffix=".tmp", dir=target_directory
        )
        temp_path = Path(temp_name)
        try:
            with os.fdopen(descriptor, "wb") as output:
                with source.open("rb") as input_file:
                    shutil.copyfileobj(input_file, output, length=1024 * 1024)
            try:
                if os.name == "nt":
                    temp_path.rename(target)
                else:
                    os.link(temp_path, target)
            except FileExistsError:
                index += 1
                continue
            return target
        finally:
            try:
                temp_path.unlink(missing_ok=True)
            except OSError:
                pass


def import_wheelathlete_csv(
    source: str | Path,
    library_root: str | Path,
    *,
    date_if_missing_ms: int | None = None,
) -> dict[str, Any]:
    """Keep a create-only copy and sidecar under the WheelAthlete data folder."""
    source_path = Path(source).resolve(strict=True)
    summary = read_wheelathlete_csv(source_path)
    if summary["started_utc_ms"] is None and date_if_missing_ms is None:
        raise ImportDateRequired("Choose the date for this recording")
    recorded = summary["started_utc_ms"] or int(date_if_missing_ms)
    library = Path(library_root).resolve()
    library.mkdir(parents=True, exist_ok=True)
    csv_path = _copy_create_only(source_path, library, source_path.name)
    meta_path = csv_path.with_suffix(".meta.json")
    metadata = {
        "schema_version": 1,
        "session_id": f"imported-{uuid4().hex}",
        "source_session_id": summary["source_session_id"],
        "source_filename": source_path.name,
        "imported_file": csv_path.name,
        "started_utc_ms": int(recorded),
        "topic": "Imported CSV",
        "trial_number": 1,
        "athlete": "",
        "duration_s": summary["duration_s"],
        "sample_counts": summary["sample_counts"],
        "quality": "IMPORTED",
        "is_imported_csv": True,
    }
    try:
        with meta_path.open("x", encoding="utf-8", newline="") as handle:
            json.dump(metadata, handle, indent=2, sort_keys=True)
            handle.write("\n")
    except Exception:
        csv_path.unlink(missing_ok=True)
        raise
    return {**metadata, "imported_csv_path": str(csv_path)}


def list_imported_csvs(library_root: str | Path) -> list[dict[str, Any]]:
    library = Path(library_root).resolve()
    if not library.is_dir():
        return []
    imported = []
    for meta_path in sorted(library.glob("*.meta.json")):
        try:
            metadata = json.loads(meta_path.read_text(encoding="utf-8"))
            if not isinstance(metadata, dict) or metadata.get("schema_version") != 1:
                continue
            csv_path = (library / Path(str(metadata.get("imported_file", ""))).name).resolve(strict=True)
            csv_path.relative_to(library)
            if csv_path.suffix.lower() != ".csv":
                continue
            imported.append({**metadata, "imported_csv_path": str(csv_path)})
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            continue
    return imported


def copy_imported_csv_for_export(
    session: dict[str, Any], target_directory: str | Path, *, file_name: str | None = None
) -> Path:
    source = Path(str(session.get("imported_csv_path") or "")).resolve(strict=True)
    if source.suffix.lower() != ".csv":
        raise ValueError("Imported session CSV is unavailable")
    return _copy_create_only(
        source,
        Path(target_directory),
        file_name or str(session.get("imported_file") or source.name),
    )


def delete_imported_csv(session: dict[str, Any], library_root: str | Path) -> None:
    library = Path(library_root).resolve(strict=True)
    csv_path = (library / Path(str(session.get("imported_file") or "")).name).resolve(strict=True)
    csv_path.relative_to(library)
    if csv_path.suffix.lower() != ".csv":
        raise ValueError("Imported session is not a CSV file")
    meta_path = csv_path.with_suffix(".meta.json")
    csv_path.unlink()
    meta_path.unlink(missing_ok=True)
