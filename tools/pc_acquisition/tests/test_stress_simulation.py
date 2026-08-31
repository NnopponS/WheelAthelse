import asyncio
import struct
import time
from pathlib import Path

import pytest

from tools.pc_acquisition.engine import DualBoardEngine
from tools.pc_acquisition.journal import JournalReader, JournalRecorder
from tools.pc_acquisition.models import ImuSample, ReceivedSample, WheelSide
from tools.pc_acquisition.transport import FakeBleTransport


BATCH_SIZE = 12
LOGICAL_DURATION_S = 30 * 60


def _batch(start_seq: int, rate_hz: int, count: int = BATCH_SIZE) -> bytes:
    period_us = 1_000_000 // rate_hz
    payload = bytearray(1 + count * 20)
    payload[0] = count
    for index in range(count):
        seq = start_seq + index
        base = (seq % 2000) - 1000
        struct.pack_into(
            "<IIhhhhhh",
            payload,
            1 + index * 20,
            seq & 0xFFFFFFFF,
            (seq * period_us) & 0xFFFFFFFF,
            base,
            base + 1,
            base + 2,
            -base,
            -base - 1,
            -base - 2,
        )
    return bytes(payload)


@pytest.mark.parametrize("rate_hz", [50, 100, 200])
def test_dual_wheel_30_min_equivalent_has_exact_counts_and_bounded_preview(rate_hz: int):
    async def scenario():
        raw_counts = {WheelSide.LEFT: 0, WheelSide.RIGHT: 0}
        preview_counts = {WheelSide.LEFT: 0, WheelSide.RIGHT: 0}

        def on_sample(sample: ReceivedSample) -> None:
            raw_counts[sample.side] += 1

        def on_preview(sample: ReceivedSample) -> None:
            preview_counts[sample.side] += 1

        transport = FakeBleTransport()
        engine = DualBoardEngine(
            transport,
            queue_capacity=512,
            preview_interval_ns=100_000_000,
            sample_sink=on_sample,
            preview_sink=on_preview,
        )
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left")
        await engine.connect(WheelSide.RIGHT, "right")

        samples_per_side = rate_hz * LOGICAL_DURATION_S
        assert samples_per_side % BATCH_SIZE == 0
        notifications_per_side = samples_per_side // BATCH_SIZE
        batch_interval_ns = round(BATCH_SIZE / rate_hz * 1_000_000_000)
        base_arrival_ns = 10_000_000_000
        started = time.perf_counter()

        for packet_index in range(notifications_per_side):
            seq = packet_index * BATCH_SIZE
            arrival_ns = base_arrival_ns + packet_index * batch_interval_ns
            transport.emit_imu("left", _batch(seq, rate_hz), arrival_ns=arrival_ns)
            transport.emit_imu(
                "right",
                _batch(seq, rate_hz),
                arrival_ns=arrival_ns + 500_000,
            )
            if packet_index % 128 == 127:
                await engine.join()
        await engine.join()
        wall_s = time.perf_counter() - started

        for side in WheelSide:
            metrics = engine.metrics(side)
            assert raw_counts[side] == samples_per_side
            assert metrics.samples_received == samples_per_side
            assert metrics.notifications_received == notifications_per_side
            assert metrics.sequence_gaps == 0
            assert metrics.duplicate_samples == 0
            assert metrics.out_of_order_samples == 0
            assert metrics.malformed_packets == 0
            assert metrics.queue_overflow_faults == 0
            assert engine.fatal_fault(side) is None
            assert engine.pending_notifications(side) == 0
            assert 0 < preview_counts[side] <= LOGICAL_DURATION_S * 10 + 1

        assert wall_s < LOGICAL_DURATION_S
        await engine.stop()

    asyncio.run(scenario())


def test_dual_wheel_400_notification_burst_is_lossless_within_queue_budget():
    async def scenario():
        counts = {WheelSide.LEFT: 0, WheelSide.RIGHT: 0}

        def sink(sample: ReceivedSample) -> None:
            counts[sample.side] += 1

        transport = FakeBleTransport()
        engine = DualBoardEngine(transport, queue_capacity=512, sample_sink=sink)
        await engine.start()
        await engine.connect(WheelSide.LEFT, "left")
        await engine.connect(WheelSide.RIGHT, "right")

        for packet_index in range(400):
            seq = packet_index * BATCH_SIZE
            payload = _batch(seq, 200)
            transport.emit_imu("left", payload, arrival_ns=packet_index * 60_000_000)
            transport.emit_imu(
                "right",
                payload,
                arrival_ns=packet_index * 60_000_000 + 500_000,
            )

        await engine.join()
        expected = 400 * BATCH_SIZE
        assert counts == {WheelSide.LEFT: expected, WheelSide.RIGHT: expected}
        for side in WheelSide:
            metrics = engine.metrics(side)
            assert metrics.queue_high_water == 400
            assert metrics.queue_overflow_faults == 0
            assert metrics.sequence_gaps == 0
            assert engine.fatal_fault(side) is None
        await engine.stop()

    asyncio.run(scenario())
