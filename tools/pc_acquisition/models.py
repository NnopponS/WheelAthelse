from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional


class WheelSide(str, Enum):
    LEFT = "L"
    RIGHT = "R"


class NotificationKind(str, Enum):
    IMU = "imu"
    SYNC = "sync"


@dataclass(frozen=True, slots=True)
class ImuSample:
    seq: int
    t_device_us: int
    ax: int
    ay: int
    az: int
    gx: int
    gy: int
    gz: int


@dataclass(frozen=True, slots=True)
class NotificationEnvelope:
    kind: NotificationKind
    payload: bytes
    arrival_ns: int
    packet_id: int


@dataclass(frozen=True, slots=True)
class ReceivedSample:
    side: WheelSide
    sample: ImuSample
    arrival_ns: int
    packet_id: int
    sequence_class: str
    missing_before: int = 0


@dataclass(frozen=True, slots=True)
class DeviceCandidate:
    device_id: str
    name: str
    rssi: Optional[int] = None


@dataclass(slots=True)
class IngestionMetrics:
    notifications_received: int = 0
    samples_received: int = 0
    malformed_packets: int = 0
    sequence_gaps: int = 0
    duplicate_samples: int = 0
    out_of_order_samples: int = 0
    queue_high_water: int = 0
    queue_overflow_faults: int = 0


@dataclass(frozen=True, slots=True)
class AcquisitionFault:
    code: str
    message: str
