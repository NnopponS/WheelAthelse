from __future__ import annotations

import csv
import json
import os
import queue
import struct
import threading
import time
import uuid
import zlib
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import Any

from .models import AcquisitionFault, ImuSample, ReceivedSample, WheelSide


MAGIC = b"WATHJNL1"
JOURNAL_VERSION = 1
_HEADER = struct.Struct("<8sH6x")
_FRAME_HEADER = struct.Struct("<BI")
_CRC = struct.Struct("<I")
_SAMPLE = struct.Struct("<16sBIIQhhhhhhQBI")
_MAX_RECORD_BYTES = 16 * 1024 * 1024
_STOP = object()

_SEQUENCE_TO_CODE = {
    "first": 0,
    "contiguous": 1,
    "gap": 2,
    "duplicate": 3,
    "out_of_order": 4,
}
_CODE_TO_SEQUENCE = {value: key for key, value in _SEQUENCE_TO_CODE.items()}


class RecordKind(IntEnum):
    SESSION_META = 1
    SAMPLE = 2
    SYNC = 3
    HEALTH = 4
    EVENT = 5
    ERROR = 6
    FINALIZE = 7


@dataclass(slots=True)
class JournalWriterMetrics:
    records_written: int = 0
    samples_written: int = 0
    queue_high_water: int = 0
    queue_overflow_faults: int = 0
    max_write_latency_ns: int = 0


@dataclass(frozen=True, slots=True)
class JournalValidation:
    valid_records: int
    valid_bytes: int
    truncated_tail: bool
    checksum_error: bool
    finalized: bool


@dataclass(frozen=True, slots=True)
class JournalRecord:
    kind: RecordKind
    payload: bytes
    sample: ReceivedSample | None = None
    json_value: dict[str, Any] | None = None


class JournalFormatError(ValueError):
    pass


def _json_payload(value: dict[str, Any]) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _frame(kind: RecordKind, payload: bytes) -> bytes:
    if len(payload) > _MAX_RECORD_BYTES:
        raise ValueError("journal record exceeds maximum size")
    crc = zlib.crc32(bytes([int(kind)]) + payload) & 0xFFFFFFFF
    return _FRAME_HEADER.pack(int(kind), len(payload)) + payload + _CRC.pack(crc)


class JournalRecorder:
    """Append-only session journal with a dedicated bounded writer queue."""

    def __init__(
        self,
        root: Path | str,
        *,
        session_id: str | None = None,
        queue_capacity: int = 4096,
        fsync_every_records: int = 256,
        start_thread: bool = True,
    ) -> None:
        if queue_capacity < 1:
            raise ValueError("queue_capacity must be >= 1")
        if fsync_every_records < 1:
            raise ValueError("fsync_every_records must be >= 1")
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.session_id = session_id or str(uuid.uuid4())
        self._session_uuid = uuid.UUID(self.session_id)
        self.open_path = self.root / f"{self.session_id}.open"
        self.final_path = self.root / f"{self.session_id}.waj"
        self.metrics = JournalWriterMetrics()
        self.fatal_fault: AcquisitionFault | None = None
        self._queue: queue.Queue[ReceivedSample | object] = queue.Queue(
            maxsize=queue_capacity
        )
        self._fsync_every_records = fsync_every_records
        self._records_since_sync = 0
        self._lock = threading.Lock()
        self._handle = self.open_path.open("xb", buffering=0)
        self._handle.write(_HEADER.pack(MAGIC, JOURNAL_VERSION))
        self._handle.flush()
        os.fsync(self._handle.fileno())
        self._thread: threading.Thread | None = None
        self._closed = False
        if start_thread:
            self._start_thread()

    def _start_thread(self) -> None:
        if self._thread is not None:
            return
        self._thread = threading.Thread(
            target=self._writer_loop,
            name=f"wheelathlete-journal-{self.session_id}",
            daemon=True,
        )
        self._thread.start()

    def append_metadata(self, metadata: dict[str, Any]) -> None:
        value = dict(metadata)
        value.setdefault("session_id", self.session_id)
        self._append_record(RecordKind.SESSION_META, _json_payload(value))

    def append_json(self, kind: RecordKind, value: dict[str, Any]) -> None:
        if kind is RecordKind.SAMPLE:
            raise ValueError("sample records use submit_sample")
        self._append_record(kind, _json_payload(value))

    def submit_sample(self, sample: ReceivedSample) -> bool:
        if self._closed:
            raise RuntimeError("journal is closed")
        try:
            self._queue.put_nowait(sample)
        except queue.Full:
            self.metrics.queue_overflow_faults += 1
            if self.fatal_fault is None:
                self.fatal_fault = AcquisitionFault(
                    code="journal_queue_overflow",
                    message="journal writer queue reached capacity; unread samples were not overwritten",
                )
            return False
        self.metrics.queue_high_water = max(
            self.metrics.queue_high_water, self._queue.qsize()
        )
        return True

    def wait_until_idle(self) -> None:
        self._queue.join()

    def finalize(self, summary: dict[str, Any]) -> Path:
        if self._closed:
            raise RuntimeError("journal is already closed")
        self.wait_until_idle()
        self._stop_thread()
        value = dict(summary)
        value.setdefault("session_id", self.session_id)
        self._append_record(RecordKind.FINALIZE, _json_payload(value), force_fsync=True)
        self._close_handle()
        os.replace(self.open_path, self.final_path)
        return self.final_path

    def abort_without_finalize_for_test(self) -> None:
        if self._closed:
            return
        if self._thread is not None:
            self.wait_until_idle()
            self._stop_thread()
        with self._lock:
            self._sync_locked()
        self._close_handle()

    def _stop_thread(self) -> None:
        thread = self._thread
        if thread is None:
            return
        self._queue.put(_STOP)
        self._queue.join()
        thread.join(timeout=5.0)
        if thread.is_alive():
            raise RuntimeError("journal writer thread failed to stop")
        self._thread = None

    def _writer_loop(self) -> None:
        while True:
            item = self._queue.get()
            try:
                if item is _STOP:
                    return
                assert isinstance(item, ReceivedSample)
                started = time.monotonic_ns()
                self._append_record(RecordKind.SAMPLE, self._pack_sample(item))
                self.metrics.samples_written += 1
                self.metrics.max_write_latency_ns = max(
                    self.metrics.max_write_latency_ns,
                    time.monotonic_ns() - started,
                )
            except Exception as exc:
                if self.fatal_fault is None:
                    self.fatal_fault = AcquisitionFault(
                        code="journal_write_failure", message=str(exc)
                    )
            finally:
                self._queue.task_done()

    def _pack_sample(self, received: ReceivedSample) -> bytes:
        side = 0 if received.side is WheelSide.LEFT else 1
        sequence_code = _SEQUENCE_TO_CODE.get(received.sequence_class, 255)
        sample = received.sample
        return _SAMPLE.pack(
            self._session_uuid.bytes,
            side,
            sample.seq & 0xFFFFFFFF,
            sample.t_device_us & 0xFFFFFFFF,
            received.arrival_ns,
            sample.ax,
            sample.ay,
            sample.az,
            sample.gx,
            sample.gy,
            sample.gz,
            received.packet_id,
            sequence_code,
            received.missing_before,
        )

    def _append_record(
        self, kind: RecordKind, payload: bytes, *, force_fsync: bool = False
    ) -> None:
        if self._closed:
            raise RuntimeError("journal is closed")
        data = _frame(kind, payload)
        with self._lock:
            self._handle.write(data)
            self.metrics.records_written += 1
            self._records_since_sync += 1
            if force_fsync or self._records_since_sync >= self._fsync_every_records:
                self._sync_locked()

    def _sync_locked(self) -> None:
        self._handle.flush()
        os.fsync(self._handle.fileno())
        self._records_since_sync = 0

    def _close_handle(self) -> None:
        if self._closed:
            return
        with self._lock:
            self._sync_locked()
            self._handle.close()
            self._closed = True


class JournalReader:
    def __init__(self, path: Path | str) -> None:
        self.path = Path(path)

    def validate(self) -> JournalValidation:
        valid_records = 0
        valid_bytes = _HEADER.size
        truncated = False
        checksum_error = False
        finalized = False
        with self.path.open("rb") as handle:
            header = handle.read(_HEADER.size)
            if len(header) != _HEADER.size:
                raise JournalFormatError("journal header is truncated")
            magic, version = _HEADER.unpack(header)
            if magic != MAGIC:
                raise JournalFormatError("journal magic mismatch")
            if version != JOURNAL_VERSION:
                raise JournalFormatError(f"unsupported journal version {version}")

            while True:
                frame_start = handle.tell()
                raw_header = handle.read(_FRAME_HEADER.size)
                if not raw_header:
                    break
                if len(raw_header) != _FRAME_HEADER.size:
                    truncated = True
                    break
                kind_raw, payload_len = _FRAME_HEADER.unpack(raw_header)
                if payload_len > _MAX_RECORD_BYTES:
                    checksum_error = True
                    break
                payload = handle.read(payload_len)
                raw_crc = handle.read(_CRC.size)
                if len(payload) != payload_len or len(raw_crc) != _CRC.size:
                    truncated = True
                    break
                expected_crc = _CRC.unpack(raw_crc)[0]
                actual_crc = zlib.crc32(bytes([kind_raw]) + payload) & 0xFFFFFFFF
                if expected_crc != actual_crc:
                    checksum_error = True
                    break
                try:
                    kind = RecordKind(kind_raw)
                except ValueError:
                    checksum_error = True
                    break
                valid_records += 1
                valid_bytes = handle.tell()
                finalized = finalized or kind is RecordKind.FINALIZE
                assert valid_bytes > frame_start
        return JournalValidation(
            valid_records=valid_records,
            valid_bytes=valid_bytes,
            truncated_tail=truncated,
            checksum_error=checksum_error,
            finalized=finalized,
        )

    def read_all(self) -> list[JournalRecord]:
        validation = self.validate()
        if validation.truncated_tail or validation.checksum_error:
            raise JournalFormatError("journal contains an invalid tail; recover it first")
        records: list[JournalRecord] = []
        with self.path.open("rb") as handle:
            handle.seek(_HEADER.size)
            for _ in range(validation.valid_records):
                kind_raw, payload_len = _FRAME_HEADER.unpack(
                    handle.read(_FRAME_HEADER.size)
                )
                payload = handle.read(payload_len)
                handle.read(_CRC.size)
                kind = RecordKind(kind_raw)
                records.append(self._decode_record(kind, payload))
        return records

    def _decode_record(self, kind: RecordKind, payload: bytes) -> JournalRecord:
        if kind is RecordKind.SAMPLE:
            if len(payload) != _SAMPLE.size:
                raise JournalFormatError("sample record has invalid size")
            (
                session_raw,
                side_raw,
                seq,
                t_device_us,
                arrival_ns,
                ax,
                ay,
                az,
                gx,
                gy,
                gz,
                packet_id,
                sequence_code,
                missing_before,
            ) = _SAMPLE.unpack(payload)
            side = WheelSide.LEFT if side_raw == 0 else WheelSide.RIGHT
            sample = ReceivedSample(
                side=side,
                sample=ImuSample(
                    seq=seq,
                    t_device_us=t_device_us,
                    ax=ax,
                    ay=ay,
                    az=az,
                    gx=gx,
                    gy=gy,
                    gz=gz,
                ),
                arrival_ns=arrival_ns,
                packet_id=packet_id,
                sequence_class=_CODE_TO_SEQUENCE.get(sequence_code, "unknown"),
                missing_before=missing_before,
            )
            # Validate/format the UUID even though the ReceivedSample domain
            # object intentionally remains session-agnostic.
            uuid.UUID(bytes=session_raw)
            return JournalRecord(kind=kind, payload=payload, sample=sample)
        if kind in {
            RecordKind.SESSION_META,
            RecordKind.SYNC,
            RecordKind.HEALTH,
            RecordKind.EVENT,
            RecordKind.ERROR,
            RecordKind.FINALIZE,
        }:
            value = json.loads(payload.decode("utf-8"))
            if not isinstance(value, dict):
                raise JournalFormatError("JSON journal record must be an object")
            return JournalRecord(kind=kind, payload=payload, json_value=value)
        return JournalRecord(kind=kind, payload=payload)

    def export_csv(self, output_path: Path | str) -> Path:
        output = Path(output_path)
        records = self.read_all()
        session_id = ""
        for record in records:
            if record.kind is RecordKind.SESSION_META and record.json_value:
                session_id = str(record.json_value.get("session_id", ""))
                break
        fields = [
            "session_id",
            "wheel",
            "seq",
            "timestamp_device_us",
            "timestamp_pc_monotonic_ns",
            "ax_raw",
            "ay_raw",
            "az_raw",
            "gx_raw",
            "gy_raw",
            "gz_raw",
            "packet_id",
            "sequence_class",
            "missing_before",
        ]
        with output.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            for record in records:
                if record.kind is not RecordKind.SAMPLE or record.sample is None:
                    continue
                received = record.sample
                sample = received.sample
                writer.writerow(
                    {
                        "session_id": session_id,
                        "wheel": received.side.value,
                        "seq": sample.seq,
                        "timestamp_device_us": sample.t_device_us,
                        "timestamp_pc_monotonic_ns": received.arrival_ns,
                        "ax_raw": sample.ax,
                        "ay_raw": sample.ay,
                        "az_raw": sample.az,
                        "gx_raw": sample.gx,
                        "gy_raw": sample.gy,
                        "gz_raw": sample.gz,
                        "packet_id": received.packet_id,
                        "sequence_class": received.sequence_class,
                        "missing_before": received.missing_before,
                    }
                )
        return output


def recover_open_journal(path: Path | str, output_path: Path | str | None = None) -> Path:
    source = Path(path)
    if source.suffix != ".open":
        raise ValueError("recovery source must be a .open journal")
    report = JournalReader(source).validate()
    if output_path is None:
        output = source.with_suffix(".recovered.waj")
    else:
        output = Path(output_path)
    if output.exists():
        raise FileExistsError(output)
    with source.open("rb") as src, output.open("xb") as dst:
        remaining = report.valid_bytes
        while remaining > 0:
            chunk = src.read(min(1024 * 1024, remaining))
            if not chunk:
                break
            dst.write(chunk)
            remaining -= len(chunk)
        dst.flush()
        os.fsync(dst.fileno())
    return output
