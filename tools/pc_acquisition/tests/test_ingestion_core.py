import asyncio
import struct

import pytest

from tools.pc_acquisition.engine import BoardIngestor, DualBoardEngine
from tools.pc_acquisition.models import NotificationKind, WheelSide
from tools.pc_acquisition.protocol import PacketFormatError, parse_imu_batch
from tools.pc_acquisition.sequence import SequenceClass, SequenceTracker
from tools.pc_acquisition.transport import FakeBleTransport


def _sample(seq: int, t_us: int, base: int = 1) -> bytes:
    return struct.pack(
        "<IIhhhhhh",
        seq & 0xFFFFFFFF,
        t_us & 0xFFFFFFFF,
        base,
        base + 1,
        base + 2,
        base + 3,
        base + 4,
        base + 5,
    )


def _batch(*samples: bytes) -> bytes:
    return bytes([len(samples)]) + b"".join(samples)


def test_strict_batch_parser_rejects_zero_count_truncation_and_trailing_bytes():
    parsed = parse_imu_batch(_batch(_sample(1, 10), _sample(2, 20)))
    assert [sample.seq for sample in parsed] == [1, 2]

    with pytest.raises(PacketFormatError):
        parse_imu_batch(b"\x00")
    with pytest.raises(PacketFormatError):
        parse_imu_batch(b"\x01" + _sample(1, 10)[:-1])
    with pytest.raises(PacketFormatError):
        parse_imu_batch(_batch(_sample(1, 10)) + b"\x00")
    with pytest.raises(PacketFormatError):
        parse_imu_batch(bytes([13]) + b"\x00" * (13 * 20))


def test_sequence_tracker_classifies_wrap_gap_duplicate_and_out_of_order():
    tracker = SequenceTracker(recent_window=8)
    assert tracker.observe(0xFFFFFFFE).classification is SequenceClass.FIRST
    assert tracker.observe(0xFFFFFFFF).classification is SequenceClass.CONTIGUOUS
    assert tracker.observe(0).classification is SequenceClass.CONTIGUOUS

    gap = tracker.observe(3)
    assert gap.classification is SequenceClass.GAP
    assert gap.missing == 2

    duplicate = tracker.observe(3)
    assert duplicate.classification is SequenceClass.DUPLICATE

    late = tracker.observe(2)
    assert late.classification is SequenceClass.OUT_OF_ORDER


def test_bounded_ingestion_queue_never_overwrites_unread_notifications():
    async def scenario():
        ingestor = BoardIngestor(WheelSide.LEFT, queue_capacity=2)
        assert ingestor.enqueue_notification(
            NotificationKind.IMU, _batch(_sample(0, 0)), arrival_ns=1
        )
        assert ingestor.enqueue_notification(
            NotificationKind.IMU, _batch(_sample(1, 10)), arrival_ns=2
        )
        assert not ingestor.enqueue_notification(
            NotificationKind.IMU, _batch(_sample(2, 20)), arrival_ns=3
        )
        assert ingestor.metrics.queue_high_water == 2
        assert ingestor.metrics.queue_overflow_faults == 1
        assert ingestor.fatal_fault is not None
        assert ingestor.pending_notifications == 2

    asyncio.run(scenario())


def test_preview_is_throttled_but_authoritative_sink_receives_every_sample():
    async def scenario():
        raw = []
        preview = []
        ingestor = BoardIngestor(
            WheelSide.LEFT,
            queue_capacity=32,
            preview_interval_ns=100_000_000,
            sample_sink=raw.append,
            preview_sink=preview.append,
        )
        await ingestor.start()
        for i in range(20):
            assert ingestor.enqueue_notification(
                NotificationKind.IMU,
                _batch(_sample(i, i * 10_000)),
                arrival_ns=i * 10_000_000,
            )
        await ingestor.join()
        await ingestor.stop()

        assert len(raw) == 20
        assert len(preview) == 2
        assert [item.sample.seq for item in preview] == [0, 10]
        assert ingestor.metrics.samples_received == 20
        assert ingestor.metrics.sequence_gaps == 0

    asyncio.run(scenario())


def test_dual_board_engine_keeps_left_and_right_ingestion_independent():
    async def scenario():
        transport = FakeBleTransport()
        samples = []
        engine = DualBoardEngine(
            transport,
            queue_capacity=8,
            sample_sink=samples.append,
        )
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left-device")
        await engine.connect(WheelSide.RIGHT, "right-device")

        transport.emit_imu("left-device", _batch(_sample(0, 100, 10)), arrival_ns=10)
        transport.emit_imu("right-device", _batch(_sample(0, 200, 20)), arrival_ns=20)
        transport.emit_imu("left-device", _batch(_sample(1, 110, 11)), arrival_ns=30)
        transport.emit_imu("right-device", _batch(_sample(1, 210, 21)), arrival_ns=40)

        await engine.join()
        left = [s.sample.seq for s in samples if s.side is WheelSide.LEFT]
        right = [s.sample.seq for s in samples if s.side is WheelSide.RIGHT]
        assert left == [0, 1]
        assert right == [0, 1]
        assert engine.metrics(WheelSide.LEFT).samples_received == 2
        assert engine.metrics(WheelSide.RIGHT).samples_received == 2
        assert engine.metrics(WheelSide.LEFT).sequence_gaps == 0
        assert engine.metrics(WheelSide.RIGHT).sequence_gaps == 0

        await engine.stop()

    asyncio.run(scenario())
