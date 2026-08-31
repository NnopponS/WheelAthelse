from __future__ import annotations

import asyncio
import time
from collections.abc import Callable
from contextlib import suppress

from .models import (
    AcquisitionFault,
    IngestionMetrics,
    NotificationEnvelope,
    NotificationKind,
    ReceivedSample,
    WheelSide,
)
from .protocol import PacketFormatError, parse_imu_batch
from .sequence import SequenceClass, SequenceTracker
from .transport import BleTransport
from .uuids import IMU_DATA_UUID, SYNC_UUID


SampleSink = Callable[[ReceivedSample], None]
SyncSink = Callable[[WheelSide, NotificationEnvelope], None]


class BoardIngestor:
    """Lossless-side ingestion worker for one wheel.

    The BLE callback calls :meth:`enqueue_notification`, which performs no
    parsing or disk/UI work.  A bounded queue provides an explicit backpressure
    boundary; overflow is fatal and never overwrites unread data.
    """

    def __init__(
        self,
        side: WheelSide,
        *,
        queue_capacity: int = 512,
        preview_interval_ns: int = 100_000_000,
        sample_sink: SampleSink | None = None,
        preview_sink: SampleSink | None = None,
        sync_sink: SyncSink | None = None,
    ) -> None:
        if queue_capacity < 1:
            raise ValueError("queue_capacity must be >= 1")
        if preview_interval_ns < 0:
            raise ValueError("preview_interval_ns must be >= 0")
        self.side = side
        self.metrics = IngestionMetrics()
        self.fatal_fault: AcquisitionFault | None = None
        self._queue: asyncio.Queue[NotificationEnvelope] = asyncio.Queue(
            maxsize=queue_capacity
        )
        self._preview_interval_ns = preview_interval_ns
        self._last_preview_ns: int | None = None
        self._sample_sink = sample_sink
        self._preview_sink = preview_sink
        self._sync_sink = sync_sink
        self._sequence = SequenceTracker()
        self._next_packet_id = 0
        self._worker: asyncio.Task[None] | None = None

    @property
    def pending_notifications(self) -> int:
        return self._queue.qsize()

    async def start(self) -> None:
        if self._worker is None or self._worker.done():
            self._worker = asyncio.create_task(
                self._run(), name=f"wheelathlete-ingest-{self.side.value}"
            )

    def enqueue_notification(
        self,
        kind: NotificationKind,
        payload: bytes,
        *,
        arrival_ns: int | None = None,
    ) -> bool:
        envelope = NotificationEnvelope(
            kind=kind,
            payload=bytes(payload),
            arrival_ns=time.monotonic_ns() if arrival_ns is None else int(arrival_ns),
            packet_id=self._next_packet_id,
        )
        self._next_packet_id += 1
        try:
            self._queue.put_nowait(envelope)
        except asyncio.QueueFull:
            self.metrics.queue_overflow_faults += 1
            if self.fatal_fault is None:
                self.fatal_fault = AcquisitionFault(
                    code="host_ingestion_queue_overflow",
                    message=(
                        f"{self.side.value} notification queue reached capacity; "
                        "unread data was not overwritten"
                    ),
                )
            return False

        self.metrics.notifications_received += 1
        self.metrics.queue_high_water = max(
            self.metrics.queue_high_water, self._queue.qsize()
        )
        return True

    async def join(self) -> None:
        await self._queue.join()

    async def stop(self) -> None:
        await self.join()
        worker = self._worker
        self._worker = None
        if worker is not None and not worker.done():
            worker.cancel()
            with suppress(asyncio.CancelledError):
                await worker

    async def _run(self) -> None:
        while True:
            envelope = await self._queue.get()
            try:
                self._process(envelope)
            finally:
                self._queue.task_done()

    def _process(self, envelope: NotificationEnvelope) -> None:
        if envelope.kind is NotificationKind.SYNC:
            if self._sync_sink is not None:
                self._sync_sink(self.side, envelope)
            return

        try:
            samples = parse_imu_batch(envelope.payload)
        except PacketFormatError as exc:
            self.metrics.malformed_packets += 1
            if self.fatal_fault is None:
                self.fatal_fault = AcquisitionFault(
                    code="malformed_imu_packet",
                    message=f"{self.side.value}: {exc}",
                )
            return

        for sample in samples:
            observed = self._sequence.observe(sample.seq)
            if observed.classification is SequenceClass.GAP:
                self.metrics.sequence_gaps += observed.missing
            elif observed.classification is SequenceClass.DUPLICATE:
                self.metrics.duplicate_samples += 1
            elif observed.classification is SequenceClass.OUT_OF_ORDER:
                self.metrics.out_of_order_samples += 1

            received = ReceivedSample(
                side=self.side,
                sample=sample,
                arrival_ns=envelope.arrival_ns,
                packet_id=envelope.packet_id,
                sequence_class=observed.classification.value,
                missing_before=observed.missing,
            )
            self.metrics.samples_received += 1
            if self._sample_sink is not None:
                self._sample_sink(received)

            if self._preview_sink is not None and self._preview_due(
                envelope.arrival_ns
            ):
                self._preview_sink(received)

    def _preview_due(self, arrival_ns: int) -> bool:
        last = self._last_preview_ns
        if last is None or self._preview_interval_ns == 0:
            self._last_preview_ns = arrival_ns
            return True
        if arrival_ns - last >= self._preview_interval_ns:
            self._last_preview_ns = arrival_ns
            return True
        return False


class DualBoardEngine:
    """Own two independent board ingestors behind one BLE transport."""

    def __init__(
        self,
        transport: BleTransport,
        *,
        queue_capacity: int = 512,
        preview_interval_ns: int = 100_000_000,
        sample_sink: SampleSink | None = None,
        preview_sink: SampleSink | None = None,
        sync_sink: SyncSink | None = None,
    ) -> None:
        self.transport = transport
        self._device_by_side: dict[WheelSide, str] = {}
        self._ingestors = {
            side: BoardIngestor(
                side,
                queue_capacity=queue_capacity,
                preview_interval_ns=preview_interval_ns,
                sample_sink=sample_sink,
                preview_sink=preview_sink,
                sync_sink=sync_sink,
            )
            for side in WheelSide
        }

    async def start(self) -> None:
        await asyncio.gather(*(ing.start() for ing in self._ingestors.values()))

    async def connect(self, side: WheelSide, device_id: str) -> None:
        if side in self._device_by_side:
            raise RuntimeError(f"{side.value} is already connected")
        await self.transport.connect(device_id)
        ingestor = self._ingestors[side]
        try:
            await self.transport.subscribe(
                device_id,
                IMU_DATA_UUID,
                lambda payload, arrival_ns: ingestor.enqueue_notification(
                    NotificationKind.IMU, payload, arrival_ns=arrival_ns
                ),
            )
            await self.transport.subscribe(
                device_id,
                SYNC_UUID,
                lambda payload, arrival_ns: ingestor.enqueue_notification(
                    NotificationKind.SYNC, payload, arrival_ns=arrival_ns
                ),
            )
        except BaseException:
            await self.transport.disconnect(device_id)
            raise
        self._device_by_side[side] = device_id

    async def disconnect(self, side: WheelSide) -> None:
        device_id = self._device_by_side.pop(side, None)
        if device_id is None:
            return
        await self.transport.unsubscribe(device_id, IMU_DATA_UUID)
        await self.transport.unsubscribe(device_id, SYNC_UUID)
        await self.transport.disconnect(device_id)

    async def join(self) -> None:
        await asyncio.gather(*(ing.join() for ing in self._ingestors.values()))

    async def stop(self) -> None:
        for side in list(self._device_by_side):
            await self.disconnect(side)
        await asyncio.gather(*(ing.stop() for ing in self._ingestors.values()))

    def metrics(self, side: WheelSide) -> IngestionMetrics:
        return self._ingestors[side].metrics

    def fatal_fault(self, side: WheelSide) -> AcquisitionFault | None:
        return self._ingestors[side].fatal_fault

    def device_id(self, side: WheelSide) -> str | None:
        return self._device_by_side.get(side)
