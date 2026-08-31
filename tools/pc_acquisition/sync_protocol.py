from __future__ import annotations

import struct
from dataclasses import dataclass

from .protocol import PacketFormatError


@dataclass(frozen=True, slots=True)
class SyncResponseEvent:
    t_app_ms: int
    t_device_us: int
    seq_ping: int


@dataclass(frozen=True, slots=True)
class DropCountEvent:
    count: int


@dataclass(frozen=True, slots=True)
class CmdNackEvent:
    cmd: int


@dataclass(frozen=True, slots=True)
class StartFiredEvent:
    t_device_us: int
    utc_start_ms: int = 0


@dataclass(frozen=True, slots=True)
class CountdownCueEvent:
    index: int
    total: int
    duration_ms: int


@dataclass(frozen=True, slots=True)
class StopFiredEvent:
    t_device_us: int
    last_seq: int


@dataclass(frozen=True, slots=True)
class UtcSetEvent:
    utc_epoch_ms: int


@dataclass(frozen=True, slots=True)
class AcqHealthEvent:
    state: int
    produced: int
    notified: int
    queue_drops: int
    transport_failures: int
    queue_depth: int
    fifo_faults: int = 0
    fifo_dropped_samples: int = 0


@dataclass(frozen=True, slots=True)
class ReplayResultEvent:
    start_seq: int
    requested: int
    replayed: int
    status: int


SyncEvent = (
    SyncResponseEvent
    | DropCountEvent
    | CmdNackEvent
    | StartFiredEvent
    | CountdownCueEvent
    | StopFiredEvent
    | UtcSetEvent
    | AcqHealthEvent
    | ReplayResultEvent
)


def _require_exact(payload: bytes, allowed: tuple[int, ...], name: str) -> None:
    if len(payload) not in allowed:
        expected = " or ".join(str(length) for length in allowed)
        raise PacketFormatError(
            f"{name} length {len(payload)} is invalid (expected {expected})"
        )


def parse_sync_event(payload: bytes) -> SyncEvent:
    if not payload:
        raise PacketFormatError("empty Sync notification")
    event_id = payload[0]
    if event_id == 0x00:
        _require_exact(payload, (13,), "SYNC_RESPONSE")
        return SyncResponseEvent(*struct.unpack_from("<III", payload, 1))
    if event_id == 0x10:
        _require_exact(payload, (5,), "DROP_COUNT")
        return DropCountEvent(struct.unpack_from("<I", payload, 1)[0])
    if event_id == 0x20:
        _require_exact(payload, (2,), "CMD_NACK")
        return CmdNackEvent(payload[1])
    if event_id == 0x30:
        _require_exact(payload, (5, 13), "START_FIRED")
        t_device_us = struct.unpack_from("<I", payload, 1)[0]
        utc_start_ms = struct.unpack_from("<Q", payload, 5)[0] if len(payload) == 13 else 0
        return StartFiredEvent(t_device_us=t_device_us, utc_start_ms=utc_start_ms)
    if event_id == 0x31:
        _require_exact(payload, (5,), "COUNTDOWN_CUE")
        index, total, duration_ms = struct.unpack_from("<BBH", payload, 1)
        return CountdownCueEvent(index=index, total=total, duration_ms=duration_ms)
    if event_id == 0x40:
        _require_exact(payload, (9,), "STOP_FIRED")
        return StopFiredEvent(*struct.unpack_from("<II", payload, 1))
    if event_id == 0x50:
        _require_exact(payload, (9,), "UTC_SET")
        return UtcSetEvent(struct.unpack_from("<Q", payload, 1)[0])
    if event_id == 0x60:
        if len(payload) == 10:  # protocol 1.5 legacy replay result
            return ReplayResultEvent(*struct.unpack_from("<IHHB", payload, 1))
        _require_exact(payload, (20, 28), "ACQ_HEALTH")
        state, produced, notified, queue_drops, failures, depth = struct.unpack_from(
            "<BIIIIH", payload, 1
        )
        fifo_faults = struct.unpack_from("<I", payload, 20)[0] if len(payload) == 28 else 0
        fifo_drops = struct.unpack_from("<I", payload, 24)[0] if len(payload) == 28 else 0
        return AcqHealthEvent(
            state=state,
            produced=produced,
            notified=notified,
            queue_drops=queue_drops,
            transport_failures=failures,
            queue_depth=depth,
            fifo_faults=fifo_faults,
            fifo_dropped_samples=fifo_drops,
        )
    if event_id == 0x61:
        _require_exact(payload, (10,), "REPLAY_RESULT")
        return ReplayResultEvent(*struct.unpack_from("<IHHB", payload, 1))
    raise PacketFormatError(f"unknown Sync event id 0x{event_id:02X}")
