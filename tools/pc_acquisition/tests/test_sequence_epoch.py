import asyncio
import struct

from tools.pc_acquisition.engine import DualBoardEngine
from tools.pc_acquisition.models import NotificationKind, WheelSide
from tools.pc_acquisition.transport import FakeBleTransport


def _batch(*seqs: int) -> bytes:
    payload = bytearray(1 + 20 * len(seqs))
    payload[0] = len(seqs)
    for index, seq in enumerate(seqs):
        struct.pack_into(
            "<IIhhhhhh",
            payload,
            1 + 20 * index,
            seq,
            seq * 10_000,
            1,
            2,
            3,
            4,
            5,
            6,
        )
    return bytes(payload)


def test_new_recording_sequence_epoch_accepts_firmware_restart_at_zero():
    async def scenario():
        transport = FakeBleTransport()
        engine = DualBoardEngine(transport)
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left")
        await engine.connect(WheelSide.RIGHT, "right")

        # First acquisition epoch.
        transport.emit_imu("left", _batch(0, 1, 2), arrival_ns=1_000_000)
        transport.emit_imu("right", _batch(0, 1, 2), arrival_ns=1_500_000)
        await engine.join()

        # Firmware resetQueueAndSeq() runs on every START. The PC must reset its
        # classifier at the same boundary or seq=0 becomes a false duplicate.
        await engine.reset_sequences((WheelSide.LEFT, WheelSide.RIGHT))
        transport.emit_imu("left", _batch(0, 1, 2), arrival_ns=2_000_000)
        transport.emit_imu("right", _batch(0, 1, 2), arrival_ns=2_500_000)
        await engine.join()

        for side in WheelSide:
            metrics = engine.metrics(side)
            assert metrics.samples_received == 6
            assert metrics.sequence_gaps == 0
            assert metrics.duplicate_samples == 0
            assert metrics.out_of_order_samples == 0

        await engine.stop()

    asyncio.run(scenario())


def test_sequence_reset_refuses_an_unread_previous_epoch():
    ingestor_transport = FakeBleTransport()
    engine = DualBoardEngine(ingestor_transport)
    ingestor = engine._ingestors[WheelSide.LEFT]
    assert ingestor.enqueue_notification(
        NotificationKind.IMU,
        _batch(0),
        arrival_ns=1,
    )
    try:
        ingestor.reset_sequence()
    except RuntimeError as exc:
        assert "pending notifications" in str(exc)
    else:
        raise AssertionError("sequence reset must fail with an unread old epoch")
