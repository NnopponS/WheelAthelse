import asyncio
import struct
import time

from tools.pc_acquisition.clock_sync import ClockModel
from tools.pc_acquisition.control import CMD_SET_UTC, CMD_START, set_utc
from tools.pc_acquisition.engine import DualBoardEngine
from tools.pc_acquisition.lifecycle import SyncLifecycleController
from tools.pc_acquisition.models import WheelSide
from tools.pc_acquisition.transport import FakeBleTransport


def test_set_utc_command_encodes_uint64_epoch_ms():
    epoch_ms = 1_788_877_234_567
    payload = set_utc(epoch_ms)
    assert payload[0] == CMD_SET_UTC
    assert len(payload) == 9
    assert struct.unpack_from("<Q", payload, 1)[0] == epoch_ms


def test_scheduled_record_start_pushes_same_utc_t0_before_start():
    async def scenario():
        transport = FakeBleTransport()
        engine = DualBoardEngine(transport)
        controller = SyncLifecycleController(engine, transport)
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left")

        now_ns = time.monotonic_ns()
        controller.install_clock_model(
            WheelSide.LEFT,
            ClockModel.nominal(
                device_us=1_000_000,
                pc_ns=now_ns,
                rtt_ns=1_000_000,
            ),
        )
        pc_t0_ns = now_ns + 100_000_000
        utc_t0_ms = 1_788_877_234_567

        task = asyncio.create_task(
            controller.scheduled_start(
                (WheelSide.LEFT,),
                pc_start_ns=pc_t0_ns,
                utc_start_ms=utc_t0_ms,
                ack_timeout_s=1.0,
            )
        )
        await asyncio.sleep(0)

        utc_writes = [w for w in transport.writes if w[2][0] == CMD_SET_UTC]
        start_writes = [w for w in transport.writes if w[2][0] == CMD_START]
        assert len(utc_writes) == 1
        assert len(start_writes) == 1
        assert struct.unpack_from("<Q", utc_writes[0][2], 1)[0] == utc_t0_ms
        assert transport.writes.index(utc_writes[0]) < transport.writes.index(start_writes[0])

        target_device_us = struct.unpack_from("<I", start_writes[0][2], 1)[0]
        transport.emit_sync(
            "left",
            b"\x30" + struct.pack("<IQ", target_device_us, utc_t0_ms),
            arrival_ns=pc_t0_ns,
        )
        await engine.join()
        result = await task
        assert result.utc_start_ms == utc_t0_ms
        assert result.acknowledged == {WheelSide.LEFT}
        await engine.stop()

    asyncio.run(scenario())
