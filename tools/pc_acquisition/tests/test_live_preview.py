import asyncio
import struct
import time
from pathlib import Path
from unittest.mock import AsyncMock

from tools.pc_acquisition.clock_sync import ClockModel
from tools.pc_acquisition.lifecycle import StartResult, StopResult
from tools.pc_acquisition.models import DeviceCandidate, WheelSide
from tools.pc_acquisition.service import AcquisitionService
from tools.pc_acquisition.transport import FakeBleTransport
from tools.pc_acquisition.uuids import INFO_UUID


def _info(side: str) -> bytes:
    return (
        bytes([ord(side), 1, 7, 0, 1, 3])
        + struct.pack("<ff", 4 / 32768, 2000 / 32768)
        + bytes([2, 1])
    )


def test_scan_merges_two_short_windows_when_windows_discovers_one_wheel_at_a_time(
    tmp_path: Path,
):
    class OneAtATimeTransport(FakeBleTransport):
        def __init__(self):
            super().__init__()
            self.calls = 0

        async def scan(self, timeout_s: float = 5.0):
            assert timeout_s == 4.0
            self.calls += 1
            side = "L" if self.calls == 1 else "R"
            return [DeviceCandidate(side, f"WheelAthlete-XIAO-{side}", -50)]

    async def scenario():
        transport = OneAtATimeTransport()
        service = AcquisitionService(transport, journal_root=tmp_path)
        try:
            result = await service.handle_command(
                "scan", {"timeout_s": 8.0, "attempts": 2}
            )
            assert [item["device_id"] for item in result["devices"]] == ["L", "R"]
            assert transport.calls == 2
        finally:
            await service.close()

    asyncio.run(scenario())


def test_live_preview_has_explicit_start_stop_state_without_opening_a_journal(
    tmp_path: Path,
):
    async def scenario():
        transport = FakeBleTransport()
        for side, device_id in (("L", "left"), ("R", "right")):
            transport.read_values[(device_id, INFO_UUID)] = _info(side)
            transport.mtu[device_id] = 247

        service = AcquisitionService(transport, journal_root=tmp_path)
        try:
            await service.handle_command("connect", {"device_id": "left"})
            await service.handle_command("connect", {"device_id": "right"})

            now_ns = time.monotonic_ns()
            model = ClockModel.nominal(device_us=1_000_000, pc_ns=now_ns, rtt_ns=1_000_000)
            service.lifecycle.synchronize = AsyncMock(return_value=model)
            service.lifecycle.scheduled_start = AsyncMock(
                return_value=StartResult(
                    pc_start_ns=now_ns + 1_000_000,
                    acknowledged=frozenset(WheelSide),
                    mapped_start_ns={side: now_ns + 1_000_000 for side in WheelSide},
                    target_device_us={side: 1_001_000 for side in WheelSide},
                    start_skew_ns=0,
                )
            )
            service.lifecycle.stop_all = AsyncMock(
                return_value={
                    side: StopResult(True, 1, None, None) for side in WheelSide
                }
            )

            started = await service.handle_command(
                "start_live", {"sides": ["L", "R"], "sync_count": 5}
            )
            assert started["live"]
            assert service.status()["live"]
            assert service.status()["live_sides"] == ["L", "R"]
            assert not service.status()["recording"]
            assert service.status()["journal"] is None

            stopped = await service.handle_command("stop_live", {})
            assert not stopped["live"]
            assert not service.status()["live"]
        finally:
            await service.close()

    asyncio.run(scenario())
