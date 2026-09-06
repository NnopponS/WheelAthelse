import asyncio
import struct

from tools.pc_acquisition.clock_sync import ClockModel
from tools.pc_acquisition.engine import DualBoardEngine
from tools.pc_acquisition.lifecycle import SyncLifecycleController
from tools.pc_acquisition.models import WheelSide
from tools.pc_acquisition.transport import FakeBleTransport


def test_scheduled_start_ack_timeout_includes_remaining_lead_time():
    async def scenario():
        transport = FakeBleTransport()
        engine = DualBoardEngine(transport)
        controller = SyncLifecycleController(engine, transport)
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left")
        now = asyncio.get_running_loop().time()
        now_ns = int(now * 1_000_000_000)
        controller.install_clock_model(
            WheelSide.LEFT,
            ClockModel.nominal(device_us=1_000_000, pc_ns=now_ns, rtt_ns=1_000_000),
        )

        t0_ns = now_ns + 80_000_000  # 80 ms future start
        task = asyncio.create_task(
            controller.scheduled_start(
                (WheelSide.LEFT,), pc_start_ns=t0_ns, ack_timeout_s=0.04
            )
        )
        await asyncio.sleep(0.09)
        # This ACK arrives after the 40 ms post-write margin, but still within
        # T0 + 40 ms. A timeout measured only from command-write time would fail.
        target = struct.unpack_from("<I", transport.writes[-1][2], 1)[0]
        transport.emit_sync(
            "left",
            b"\x30" + struct.pack("<IQ", target, 0),
            arrival_ns=t0_ns,
        )
        await engine.join()
        result = await task
        assert result.acknowledged == {WheelSide.LEFT}
        await engine.stop()

    asyncio.run(scenario())
