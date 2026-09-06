import asyncio
import struct
from pathlib import Path

from tools.pc_acquisition.service import AcquisitionService
from tools.pc_acquisition.transport import FakeBleTransport
from tools.pc_acquisition.uuids import INFO_UUID


def _info(accel_range: int, gyro_range: int, accel_scale: float, gyro_scale: float) -> bytes:
    return (
        bytes([0x4C, 1, 7, 0, accel_range, gyro_range])
        + struct.pack("<ff", accel_scale, gyro_scale)
        + bytes([2, 1])
    )


def test_configure_range_rereads_firmware_scales_before_success(tmp_path: Path):
    async def scenario() -> None:
        transport = FakeBleTransport()
        transport.read_values[("left", INFO_UUID)] = _info(
            1, 3, 4 / 32768, 2000 / 32768
        )
        transport.mtu["left"] = 247
        service = AcquisitionService(transport, journal_root=tmp_path)
        await service.handle_command("connect", {"device_id": "left"})

        # Model the firmware's authoritative Info characteristic after the
        # SET_RANGE command has taken effect. The service must re-read it rather
        # than changing only the range codes while retaining stale scales.
        transport.read_values[("left", INFO_UUID)] = _info(
            2, 1, 8 / 32768, 500 / 32768
        )
        result = await service.handle_command(
            "configure",
            {"side": "L", "accel_range": 2, "gyro_range": 1},
        )
        assert result == {"side": "L", "configured": True}

        board = (await service.handle_command("status", {}))["boards"]["L"]
        info = board["info"]
        assert info["accel_range"] == 2
        assert info["gyro_range"] == 1
        assert abs(info["accel_scale"] - (8 / 32768)) < 1e-9
        assert abs(info["gyro_scale"] - (500 / 32768)) < 1e-9
        await service.close()

    asyncio.run(scenario())
