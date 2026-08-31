import asyncio
import struct

import pytest

from tools.pc_acquisition.clock_sync import ClockObservation, ClockModel, Uint32Unwrapper
from tools.pc_acquisition.control import CMD_START, CMD_STOP, CMD_SYNC_PING
from tools.pc_acquisition.engine import DualBoardEngine
from tools.pc_acquisition.lifecycle import SyncLifecycleController
from tools.pc_acquisition.models import WheelSide
from tools.pc_acquisition.sync_protocol import (
    AcqHealthEvent,
    PacketFormatError,
    StartFiredEvent,
    StopFiredEvent,
    SyncResponseEvent,
    parse_sync_event,
)
from tools.pc_acquisition.transport import FakeBleTransport
from tools.pc_acquisition.uuids import CONTROL_UUID


def test_sync_parser_is_strict_and_reads_v17_health():
    sync = parse_sync_event(b"\x00" + struct.pack("<III", 7, 1234, 2))
    assert sync == SyncResponseEvent(t_app_ms=7, t_device_us=1234, seq_ping=2)

    start = parse_sync_event(b"\x30" + struct.pack("<IQ", 5000, 123456789))
    assert start == StartFiredEvent(t_device_us=5000, utc_start_ms=123456789)

    stop = parse_sync_event(b"\x40" + struct.pack("<II", 9000, 399))
    assert stop == StopFiredEvent(t_device_us=9000, last_seq=399)

    health = parse_sync_event(
        b"\x60" + struct.pack("<BIIIIHII", 2, 400, 400, 0, 0, 0, 0, 0)
    )
    assert health == AcqHealthEvent(
        state=2,
        produced=400,
        notified=400,
        queue_drops=0,
        transport_failures=0,
        queue_depth=0,
        fifo_faults=0,
        fifo_dropped_samples=0,
    )

    with pytest.raises(PacketFormatError):
        parse_sync_event(b"\x00" + struct.pack("<III", 7, 1234, 2) + b"\x00")
    with pytest.raises(PacketFormatError):
        parse_sync_event(b"\x40\x00")


def test_clock_unwrap_and_low_rtt_affine_fit_round_trip():
    unwrap = Uint32Unwrapper()
    assert unwrap.unwrap(0xFFFFFF00) == 0xFFFFFF00
    assert unwrap.unwrap(0x00000100) == 0x100000100

    # Device clock is 20 ppm fast relative to nominal 1000 ns/us.
    slope = 999.98
    intercept = 5_000_000_000.0
    observations = []
    for index, device_us in enumerate((1_000_000, 2_000_000, 3_000_000, 4_000_000)):
        rtt = (2, 20, 3, 4)[index] * 1_000_000
        observations.append(
            ClockObservation(
                device_us=device_us,
                pc_midpoint_ns=round(slope * device_us + intercept),
                rtt_ns=rtt,
            )
        )
    model = ClockModel.fit(observations)
    mapped = model.device_to_pc_ns(2_500_000)
    assert abs(mapped - round(slope * 2_500_000 + intercept)) < 100_000
    assert abs(model.drift_ppm + 20.0) < 2.0
    assert model.best_rtt_ns == 2_000_000
    device_back = model.pc_to_device_us(mapped)
    assert abs(device_back - 2_500_000) <= 1


def test_sync_start_and_stop_use_device_clock_mapping_and_acknowledgements():
    async def scenario():
        transport = FakeBleTransport()
        engine = DualBoardEngine(transport)
        controller = SyncLifecycleController(engine, transport)
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left")
        await engine.connect(WheelSide.RIGHT, "right")

        # Build deterministic clock models without sleeping through a real sync
        # burst. L: pc_ns = device_us*1000 + 1s; R: +1.003s.
        controller.install_clock_model(
            WheelSide.LEFT,
            ClockModel.nominal(device_us=1_000_000, pc_ns=2_000_000_000, rtt_ns=2_000_000),
        )
        controller.install_clock_model(
            WheelSide.RIGHT,
            ClockModel.nominal(device_us=1_000_000, pc_ns=2_003_000_000, rtt_ns=2_000_000),
        )

        pc_t0_ns = 6_000_000_000
        start_task = asyncio.create_task(
            controller.scheduled_start(
                (WheelSide.LEFT, WheelSide.RIGHT),
                pc_start_ns=pc_t0_ns,
                ack_timeout_s=1.0,
            )
        )
        await asyncio.sleep(0)

        start_writes = [write for write in transport.writes if write[2][0] == CMD_START]
        assert len(start_writes) == 2
        targets = {device: struct.unpack_from("<I", payload, 1)[0] for device, _, payload, _ in start_writes}
        assert targets["left"] == 5_000_000
        assert targets["right"] == 4_997_000

        transport.emit_sync("left", b"\x30" + struct.pack("<IQ", 5_000_100, 0), arrival_ns=pc_t0_ns + 100_000)
        transport.emit_sync("right", b"\x30" + struct.pack("<IQ", 4_997_150, 0), arrival_ns=pc_t0_ns + 200_000)
        await engine.join()
        start_result = await start_task
        assert start_result.acknowledged == {WheelSide.LEFT, WheelSide.RIGHT}
        assert start_result.start_skew_ns == 50_000

        # Final health is emitted before STOP_FIRED by firmware.
        stop_task = asyncio.create_task(
            controller.stop_all((WheelSide.LEFT, WheelSide.RIGHT), ack_timeout_s=1.0)
        )
        await asyncio.sleep(0)
        stop_writes = [write for write in transport.writes if write[2] == bytes([CMD_STOP])]
        assert len(stop_writes) == 2
        health = b"\x60" + struct.pack("<BIIIIHII", 0, 200, 200, 0, 0, 0, 0, 0)
        transport.emit_sync("left", health, arrival_ns=7_000_000_000)
        transport.emit_sync("right", health, arrival_ns=7_000_100_000)
        transport.emit_sync("left", b"\x40" + struct.pack("<II", 6_000_000, 199), arrival_ns=7_000_200_000)
        transport.emit_sync("right", b"\x40" + struct.pack("<II", 5_997_000, 199), arrival_ns=7_000_300_000)
        await engine.join()
        stop_result = await stop_task
        assert stop_result[WheelSide.LEFT].acknowledged
        assert stop_result[WheelSide.RIGHT].acknowledged
        assert stop_result[WheelSide.LEFT].health is not None
        assert stop_result[WheelSide.RIGHT].health is not None

        await engine.stop()

    asyncio.run(scenario())


def test_sync_burst_uses_round_trip_midpoint_and_stop_retries_transient_write():
    class FlakyTransport(FakeBleTransport):
        def __init__(self):
            super().__init__()
            self.stop_failures = 1

        async def write(self, device_id, characteristic_uuid, payload, *, response=True):
            if payload == bytes([CMD_STOP]) and self.stop_failures:
                self.stop_failures -= 1
                raise RuntimeError("transient GATT resource error")
            await super().write(
                device_id, characteristic_uuid, payload, response=response
            )

    async def scenario():
        transport = FlakyTransport()
        engine = DualBoardEngine(transport)
        controller = SyncLifecycleController(engine, transport)
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left")

        async def answer_ping():
            while True:
                await asyncio.sleep(0)
                pings = [w for w in transport.writes if w[2][0] == CMD_SYNC_PING]
                if pings:
                    _, _, payload, _ = pings[-1]
                    token = struct.unpack_from("<I", payload, 1)[0]
                    transport.emit_sync(
                        "left",
                        b"\x00" + struct.pack("<III", token, 2_000_000, 1),
                        arrival_ns=4_004_000_000,
                    )
                    await engine.join()
                    return

        answer = asyncio.create_task(answer_ping())
        model = await controller.synchronize(
            WheelSide.LEFT,
            count=1,
            timeout_s=1.0,
            clock_ns=lambda: 4_000_000_000,
        )
        await answer
        assert model.best_rtt_ns == 4_000_000
        # Midpoint is 4.002 s; device is 2.000 s -> +2.002 s offset.
        assert model.device_to_pc_ns(2_000_000) == 4_002_000_000

        controller.install_clock_model(WheelSide.LEFT, model)
        stop_task = asyncio.create_task(
            controller.stop_all(
                (WheelSide.LEFT,),
                max_attempts=3,
                retry_delay_s=0,
                ack_timeout_s=1.0,
            )
        )
        await asyncio.sleep(0)
        await asyncio.sleep(0)
        transport.emit_sync(
            "left",
            b"\x40" + struct.pack("<II", 2_100_000, 9),
            arrival_ns=4_100_000_000,
        )
        await engine.join()
        result = await stop_task
        assert result[WheelSide.LEFT].acknowledged
        assert result[WheelSide.LEFT].write_attempts == 2
        await engine.stop()

    asyncio.run(scenario())
