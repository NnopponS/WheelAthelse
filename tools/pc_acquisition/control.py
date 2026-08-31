from __future__ import annotations

import struct


CMD_START = 0x01
CMD_STOP = 0x02
CMD_SET_RATE = 0x03
CMD_SYNC_PING = 0x04
CMD_SET_RANGE = 0x05
CMD_SET_UTC = 0x09


def sync_ping(token: int) -> bytes:
    return struct.pack("<BI", CMD_SYNC_PING, token & 0xFFFFFFFF)


def scheduled_start(target_device_us: int) -> bytes:
    return struct.pack("<BI", CMD_START, target_device_us & 0xFFFFFFFF)


def stop() -> bytes:
    return bytes([CMD_STOP])
