import asyncio

from tools.pc_acquisition.control import CMD_STOP
from tools.pc_acquisition.engine import DualBoardEngine
from tools.pc_acquisition.lifecycle import SyncLifecycleController
from tools.pc_acquisition.models import WheelSide
from tools.pc_acquisition.transport import FakeBleTransport


def test_persistent_stop_write_failure_disconnects_and_clears_engine_owner():
    class AlwaysFailStopTransport(FakeBleTransport):
        async def write(self, device_id, characteristic_uuid, payload, *, response=True):
            if payload == bytes([CMD_STOP]):
                raise RuntimeError("persistent GATT failure")
            await super().write(
                device_id, characteristic_uuid, payload, response=response
            )

    async def scenario():
        transport = AlwaysFailStopTransport()
        engine = DualBoardEngine(transport)
        controller = SyncLifecycleController(engine, transport)
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left")

        result = await controller.stop_all(
            (WheelSide.LEFT,),
            max_attempts=3,
            retry_delay_s=0,
            ack_timeout_s=0.01,
        )
        assert not result[WheelSide.LEFT].acknowledged
        assert result[WheelSide.LEFT].write_attempts == 3
        assert "persistent GATT failure" in (result[WheelSide.LEFT].error or "")
        assert engine.device_id(WheelSide.LEFT) is None
        assert "left" not in transport.connected
        await engine.stop()

    asyncio.run(scenario())


def test_missing_stop_ack_disconnects_fail_closed():
    async def scenario():
        transport = FakeBleTransport()
        engine = DualBoardEngine(transport)
        controller = SyncLifecycleController(engine, transport)
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left")

        result = await controller.stop_all(
            (WheelSide.LEFT,),
            max_attempts=1,
            ack_timeout_s=0.001,
        )
        assert not result[WheelSide.LEFT].acknowledged
        assert result[WheelSide.LEFT].error == "STOP_FIRED timeout"
        assert engine.device_id(WheelSide.LEFT) is None
        assert "left" not in transport.connected
        await engine.stop()

    asyncio.run(scenario())
