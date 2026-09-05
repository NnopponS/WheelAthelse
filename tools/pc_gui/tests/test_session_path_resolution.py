import json
import uuid
from pathlib import Path

from tools.pc_acquisition.journal import JournalRecorder
from tools.pc_gui.controller import resolve_session_files


def test_gui_resolves_nested_friendly_session_by_internal_uuid(tmp_path: Path):
    session_id = str(uuid.uuid4())
    recorder = JournalRecorder(tmp_path, session_id=session_id)
    recorder.append_metadata(
        {
            "athlete": "Nipoon",
            "topic": "10x5",
            "trial_number": 16,
            "sample_rate_hz": 100,
        }
    )
    legacy_path = recorder.finalize(
        {"quality": "GOOD", "duration_s": 1.0, "reasons": []}
    )

    friendly_dir = tmp_path / "10x5"
    friendly_dir.mkdir()
    friendly_path = friendly_dir / "10x5_Trial16_Nipoon.waj"
    legacy_path.replace(friendly_path)
    manifest_path = friendly_path.with_suffix(".summary.json")
    manifest_path.write_text(
        json.dumps(
            {
                "session_id": session_id,
                "topic": "10x5",
                "trial_number": 16,
                "athlete": "Nipoon",
                "journal_path": str(friendly_path),
            }
        ),
        encoding="utf-8",
    )

    journal, manifest, csv_path = resolve_session_files(tmp_path, session_id)

    assert journal == friendly_path
    assert manifest == manifest_path
    assert csv_path == friendly_path.with_suffix(".csv")
