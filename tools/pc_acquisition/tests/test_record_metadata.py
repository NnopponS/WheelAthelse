import asyncio
import struct
import time
from pathlib import Path
from unittest.mock import AsyncMock

from tools.pc_acquisition.clock_sync import ClockModel
from tools.pc_acquisition.journal import JournalReader, RecordKind
from tools.pc_acquisition.lifecycle import StartResult
from tools.pc_acquisition.models import WheelSide
from tools.pc_acquisition.service import AcquisitionService
from tools.pc_acquisition.transport import FakeBleTransport
from tools.pc_acquisition.uuids import BATTERY_LEVEL_UUID, CONFIG_UUID, INFO_UUID


def _info() -> bytes:
    return (
        bytes([0x4C, 1, 7, 0, 1, 3])
        + struct.pack("<ff", 4 / 32768, 2000 / 32768)
        + bytes([2, 1])
    )


def _config() -> bytes:
    return (
        b"Research-L".ljust(24, b"\x00")
        + bytes([0x4C])
        + struct.pack("<H", 200)
        + bytes([1, 7, 0, 1])
    )


def test_start_record_preserves_protocol_template_and_tags_in_authoritative_metadata(
    tmp_path: Path,
):
    async def scenario():
        transport = FakeBleTransport()
        transport.read_values[("left", INFO_UUID)] = _info()
        transport.read_values[("left", CONFIG_UUID)] = _config()
        transport.read_values[("left", BATTERY_LEVEL_UUID)] = bytes([91])
        transport.mtu["left"] = 247
        service = AcquisitionService(transport, journal_root=tmp_path)
        await service.handle_command("connect", {"device_id": "left"})

        now_ns = time.monotonic_ns()
        model = ClockModel.nominal(
            device_us=1_000_000,
            pc_ns=now_ns,
            rtt_ns=1_000_000,
        )
        service.lifecycle.synchronize = AsyncMock(return_value=model)
        service.lifecycle.scheduled_start = AsyncMock(
            return_value=StartResult(
                pc_start_ns=now_ns + 1_000_000,
                acknowledged=frozenset({WheelSide.LEFT}),
                mapped_start_ns={WheelSide.LEFT: now_ns + 1_000_000},
                target_device_us={WheelSide.LEFT: 1_001_000},
                start_skew_ns=0,
            )
        )

        result = await service.handle_command(
            "start_record",
            {
                "athlete": "Athlete A",
                "topic": "Sprint",
                "trial_number": 3,
                "sample_rate_hz": 200,
                "protocol_template_id": "template-sprint-v2",
                "tags": ["baseline", "indoors"],
            },
        )
        records = JournalReader(Path(result["journal_path"])).read_all()
        metadata = next(
            record.json_value
            for record in records
            if record.kind is RecordKind.SESSION_META
        )
        assert metadata is not None
        assert metadata["protocol_template_id"] == "template-sprint-v2"
        assert metadata["tags"] == ["baseline", "indoors"]
        assert metadata["sample_rate_hz"] == 200
        assert metadata["boards"]["L"]["sample_rate_hz"] == 200
        assert metadata["boards"]["L"]["battery_percent"] == 91
        await service.close()

    asyncio.run(scenario())
