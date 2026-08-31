import asyncio
import json
import struct
import time
import uuid
from pathlib import Path

from tools.pc_acquisition.journal import JournalRecorder
from tools.pc_acquisition.models import DeviceCandidate
from tools.pc_acquisition.service import AcquisitionService
from tools.pc_acquisition.transport import FakeBleTransport
from tools.pc_acquisition.uuids import BATTERY_LEVEL_UUID, CONFIG_UUID, INFO_UUID


def _info(side=0x4C):
    return (
        bytes([side, 1, 7, 0, 1, 3])
        + struct.pack("<ff", 4 / 32768, 2000 / 32768)
        + bytes([2, 1])
    )


def _config(name="Research-L", side=0x4C, rate=100):
    encoded = name.encode("ascii")[:24].ljust(24, b"\x00")
    return encoded + bytes([side]) + struct.pack("<H", rate) + bytes([1, 7, 0, 1])


def _batch(start_seq=0, count=2):
    payload = bytearray([count])
    for index in range(count):
        seq = start_seq + index
        payload.extend(
            struct.pack(
                "<IIhhhhhh",
                seq,
                1_000_000 + seq * 10_000,
                100 + index,
                200 + index,
                300 + index,
                400 + index,
                500 + index,
                600 + index,
            )
        )
    return bytes(payload)


def test_scan_connect_and_status_expose_desktop_observability(tmp_path: Path):
    async def scenario():
        transport = FakeBleTransport()
        transport.scan_results = [
            DeviceCandidate("left-device", "WheelAthlete-L", -47)
        ]
        transport.read_values[("left-device", INFO_UUID)] = _info()
        transport.read_values[("left-device", CONFIG_UUID)] = _config()
        transport.read_values[("left-device", BATTERY_LEVEL_UUID)] = bytes([88])
        transport.mtu["left-device"] = 247

        service = AcquisitionService(transport, journal_root=tmp_path)
        scan = await service.handle_command("scan", {"timeout_s": 0.1})
        assert scan["devices"][0]["rssi"] == -47

        connected = await service.handle_command(
            "connect", {"device_id": "left-device"}
        )
        assert connected["name"] == "Research-L"
        assert connected["sample_rate_hz"] == 100
        assert connected["battery_percent"] == 88
        assert connected["rssi"] == -47
        assert connected["mtu"] == 247

        # Seed a status-rate baseline, then deliver a packet through the real
        # per-board worker. Status may inspect the queue; it never owns it.
        await service.handle_command("status", {})
        transport.emit_imu("left-device", _batch())
        await service.engine.join()
        await asyncio.sleep(0.01)
        status = await service.handle_command("status", {})
        board = status["boards"]["L"]
        assert board["samples"] == 2
        assert board["notifications"] == 1
        assert board["queue_depth"] == 0
        assert board["queue_high_water"] >= 1
        assert board["samples_hz"] is not None and board["samples_hz"] > 0
        assert board["notifications_hz"] is not None and board["notifications_hz"] > 0
        assert board["info"]["battery_percent"] == 88
        assert status["journal_root"] == str(tmp_path)
        await service.close()

    asyncio.run(scenario())


def test_pc_sessions_export_and_diagnostic_report(tmp_path: Path):
    async def scenario():
        session_id = str(uuid.uuid4())
        recorder = JournalRecorder(tmp_path, session_id=session_id)
        recorder.append_metadata(
            {
                "athlete": "Athlete A",
                "topic": "Sprint",
                "trial_number": 2,
                "sample_rate_hz": 100,
            }
        )
        journal = recorder.finalize(
            {
                "quality": "GOOD",
                "duration_s": 12.5,
                "reasons": [],
            }
        )

        service = AcquisitionService(FakeBleTransport(), journal_root=tmp_path)
        result = await service.handle_command("list_sessions", {})
        assert len(result["sessions"]) == 1
        session = result["sessions"][0]
        assert session["session_id"] == session_id
        assert session["athlete"] == "Athlete A"
        assert session["topic"] == "Sprint"
        assert session["quality"] == "GOOD"
        assert session["sample_counts"] == {"L": 0, "R": 0}

        csv_path = tmp_path / "exports" / "session.csv"
        exported = await service.handle_command(
            "export_session",
            {"session_id": session_id, "output_path": str(csv_path)},
        )
        assert Path(exported["output_path"]).exists()
        assert Path(exported["output_path"]).read_text(encoding="utf-8").startswith(
            "session_id,wheel,seq"
        )

        report_path = tmp_path / "diagnostic.json"
        report = await service.handle_command(
            "diagnostic_report", {"output_path": str(report_path)}
        )
        assert report["output_path"] == str(report_path)
        payload = json.loads(report_path.read_text(encoding="utf-8"))
        assert payload["journal_root"] == str(tmp_path)
        assert "boards" in payload["status"]
        assert journal.exists()
        await service.close()

    asyncio.run(scenario())
