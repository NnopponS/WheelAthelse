from __future__ import annotations

import struct
from typing import Tuple

from .models import ImuSample


IMU_SAMPLE_SIZE = 20
MAX_BATCH_SAMPLES = 12
_IMU_STRUCT = struct.Struct("<IIhhhhhh")


class PacketFormatError(ValueError):
    """Raised when a BLE packet violates the versioned wire contract."""


def parse_imu_batch(payload: bytes) -> Tuple[ImuSample, ...]:
    """Strictly parse one IMU notification.

    Wire format: ``[uint8 count][count * 20-byte ImuSample]``.  Unlike the old
    diagnostic PC scripts, this parser rejects both truncation *and* trailing
    bytes so malformed transport data cannot be silently accepted.
    """

    if not payload:
        raise PacketFormatError("empty IMU notification")
    count = payload[0]
    if not 1 <= count <= MAX_BATCH_SAMPLES:
        raise PacketFormatError(f"invalid IMU batch count {count}")
    expected = 1 + count * IMU_SAMPLE_SIZE
    if len(payload) != expected:
        raise PacketFormatError(
            f"IMU batch length {len(payload)} does not match count {count} "
            f"(expected {expected})"
        )

    samples = []
    for index in range(count):
        offset = 1 + index * IMU_SAMPLE_SIZE
        values = _IMU_STRUCT.unpack_from(payload, offset)
        samples.append(ImuSample(*values))
    return tuple(samples)
