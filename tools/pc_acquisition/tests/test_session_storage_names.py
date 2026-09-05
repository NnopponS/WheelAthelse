import asyncio
import json
import uuid
from pathlib import Path

from tools.pc_acquisition.journal import JournalReader, JournalRecorder, RecordKind
from tools.pc_acquisition.service import (
    AcquisitionService,
    relocate_finalized_session,
    session_storage_destination,
)
from tools.pc_acquisition.transport import FakeBleTransport


def _finalized_friendly_session(tmp_path: Path) -> tuple[str, Path, Path]:
    session_id = str(uuid.uuid4())
    metadata = {
        "athlete": "Nipoon",
        "topic": "10x5",
        "trial_number": 16,
        "sample_rate_hz": 100,
    }
    recorder = JournalRecorder(tmp_path, session_id=session_id)
    recorder.append_metadata(metadata)
    legacy_path = recorder.finalize(
        {
            "quality": "GOOD",
            "duration_s": 12.5,
            "reasons": [],
        }
    )

    friendly_path = relocate_finalized_session(legacy_path, metadata)
    manifest_path = friendly_path.with_suffix(".summary.json")
    manifest_path.write_text(
        json.dumps(
            {
                **metadata,
                "session_id": session_id,
                "quality": "GOOD",
                "duration_s": 12.5,
                "journal_path": str(friendly_path),
                "sample_counts": {"L": 0, "R": 0},
            }
        ),
        encoding="utf-8",
    )
    return session_id, friendly_path, manifest_path


def test_session_storage_destination_matches_export_naming_and_avoids_overwrite(tmp_path: Path):
    metadata = {"topic": "10x5", "trial_number": 16, "athlete": "Nipoon"}

    first = session_storage_destination(tmp_path, metadata)
    assert first == tmp_path / "10x5" / "10x5_Trial16_Nipoon.waj"

    first.parent.mkdir(parents=True, exist_ok=True)
    first.touch()
    first.with_suffix(".summary.json").write_text("{}", encoding="utf-8")

    second = session_storage_destination(tmp_path, metadata)
    assert second == tmp_path / "10x5" / "10x5_Trial16_Nipoon_2.waj"


def test_service_lists_exports_and_deletes_friendly_nested_session(tmp_path: Path):
    async def scenario() -> None:
        session_id, journal_path, manifest_path = _finalized_friendly_session(tmp_path)
        service = AcquisitionService(FakeBleTransport(), journal_root=tmp_path)

        listed = await service.handle_command("list_sessions", {})
        assert len(listed["sessions"]) == 1
        assert listed["sessions"][0]["session_id"] == session_id
        assert listed["sessions"][0]["topic"] == "10x5"
        assert listed["sessions"][0]["trial_number"] == 16
        assert listed["sessions"][0]["athlete"] == "Nipoon"

        export_path = tmp_path / "export.csv"
        exported = await service.handle_command(
            "export_session",
            {"session_id": session_id, "output_path": str(export_path)},
        )
        assert Path(exported["output_path"]).exists()

        deleted = await service.handle_command(
            "delete_session",
            {"session_id": session_id},
        )
        assert str(journal_path) in deleted["deleted"]
        assert str(manifest_path) in deleted["deleted"]
        assert not journal_path.exists()
        assert not manifest_path.exists()
        await service.close()

    asyncio.run(scenario())


def test_service_can_rename_friendly_session_without_changing_internal_uuid(tmp_path: Path):
    async def scenario() -> None:
        session_id, old_journal, old_manifest = _finalized_friendly_session(tmp_path)
        service = AcquisitionService(FakeBleTransport(), journal_root=tmp_path)

        result = await service.handle_command(
            "update_session_metadata",
            {
                "session_id": session_id,
                "topic": "Sprint Final",
                "trial_number": 3,
                "athlete": "Knight",
            },
        )

        new_journal = Path(result["journal_path"])
        new_manifest = new_journal.with_suffix(".summary.json")
        assert new_journal == tmp_path / "Sprint Final" / "Sprint Final_Trial3_Knight.waj"
        assert new_journal.exists()
        assert new_manifest.exists()
        assert not old_journal.exists()
        assert not old_manifest.exists()

        summary = json.loads(new_manifest.read_text(encoding="utf-8"))
        assert summary["session_id"] == session_id
        assert summary["topic"] == "Sprint Final"
        assert summary["trial_number"] == 3
        assert summary["athlete"] == "Knight"
        assert summary["journal_path"] == str(new_journal)

        journal_session_id = next(
            record.json_value["session_id"]
            for record in JournalReader(new_journal).iter_records()
            if record.kind is RecordKind.SESSION_META and record.json_value
        )
        assert journal_session_id == session_id

        listed = await service.handle_command("list_sessions", {})
        assert listed["sessions"][0]["topic"] == "Sprint Final"
        assert listed["sessions"][0]["trial_number"] == 3
        assert listed["sessions"][0]["athlete"] == "Knight"
        await service.close()

    asyncio.run(scenario())
