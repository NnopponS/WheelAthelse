#!/usr/bin/env python3
"""
test_config_store.py — Host-side unit tests for config_store.h pure logic

Tests: config encoding/decoding (name/wheel/rate), Config characteristic
packing (22B layout), name validation, wheel validation.

Run: python -m pytest test/test_config_store.py -v
"""

import struct
import unittest

# ── Constants from config_store.h ─────────────────────────────────────────────

CONFIG_SIZE = 22       # [name 16B][wheel_id 1B][rate_hz 2B LE][fw 3B]
NAME_MAX_LEN = 16      # board name max bytes (fixed-width, null-padded)
NVS_NAMESPACE = "wacfg"

WHEEL_LEFT = 0x4C   # 'L'
WHEEL_RIGHT = 0x52  # 'R'

VALID_RATES = (50, 100, 200)

# ── Pure functions (mirrors of config_store.h) ────────────────────────────────

def pack_config(name, wheel_id, rate_hz, fw_major, fw_minor, fw_patch):
    """Pack Config characteristic: [name 16B][wheel_id 1B][rate_hz 2B LE][fw 3B] = 22B."""
    name_bytes = name.encode('ascii')[:NAME_MAX_LEN]
    name_buf = name_bytes.ljust(NAME_MAX_LEN, b'\x00')
    return name_buf + struct.pack('<BHB', wheel_id, rate_hz, fw_major) + \
           struct.pack('<BB', fw_minor, fw_patch)


def parse_config(buf):
    """Parse 22-byte Config characteristic → (name, wheel_id, rate_hz, fw_major, fw_minor, fw_patch)."""
    if len(buf) < CONFIG_SIZE:
        raise ValueError(f"Config needs {CONFIG_SIZE} bytes, got {len(buf)}")
    name_raw = buf[0:NAME_MAX_LEN]
    name = name_raw.rstrip(b'\x00').decode('ascii')
    wheel_id = buf[16]
    rate_hz = struct.unpack('<H', buf[17:19])[0]
    fw_major = buf[19]
    fw_minor = buf[20]
    fw_patch = buf[21]
    return (name, wheel_id, rate_hz, fw_major, fw_minor, fw_patch)


def is_valid_wheel(wheel_id):
    """Check if wheel_id is valid (0x4C='L' or 0x52='R')."""
    return wheel_id == WHEEL_LEFT or wheel_id == WHEEL_RIGHT


def is_valid_rate(rate_hz):
    """Check if rate is valid (50/100/200)."""
    return rate_hz in VALID_RATES


def sanitize_name(name_str):
    """Sanitize board name: truncate to 16 bytes, ASCII only, null-pad.
    Returns 16-byte buffer."""
    name_bytes = name_str.encode('ascii', errors='replace')[:NAME_MAX_LEN]
    return name_bytes.ljust(NAME_MAX_LEN, b'\x00')


# ── Test cases ────────────────────────────────────────────────────────────────

class TestPackConfig(unittest.TestCase):
    """AC: Config char = 22 bytes [name 16B][wheel 1B][rate 2B LE][fw 3B]"""

    def test_size_is_22(self):
        buf = pack_config("WheelAthlete-L", WHEEL_LEFT, 100, 0, 2, 0)
        self.assertEqual(len(buf), CONFIG_SIZE)

    def test_name_field(self):
        buf = pack_config("MyBoard", WHEEL_LEFT, 100, 0, 2, 0)
        name_raw = buf[0:NAME_MAX_LEN]
        self.assertEqual(name_raw.rstrip(b'\x00'), b'MyBoard')

    def test_wheel_id_field(self):
        buf = pack_config("Test", WHEEL_RIGHT, 200, 1, 0, 0)
        self.assertEqual(buf[16], WHEEL_RIGHT)

    def test_rate_field_little_endian(self):
        buf = pack_config("Test", WHEEL_LEFT, 200, 0, 0, 0)
        rate = struct.unpack('<H', buf[17:19])[0]
        self.assertEqual(rate, 200)

    def test_fw_version_fields(self):
        buf = pack_config("Test", WHEEL_LEFT, 50, 1, 2, 3)
        self.assertEqual(buf[19], 1)  # major
        self.assertEqual(buf[20], 2)  # minor
        self.assertEqual(buf[21], 3)  # patch

    def test_name_null_padded(self):
        buf = pack_config("AB", WHEEL_LEFT, 100, 0, 0, 0)
        # bytes 2-15 should be 0
        for i in range(2, NAME_MAX_LEN):
            self.assertEqual(buf[i], 0)

    def test_name_truncated_to_16(self):
        long_name = "A" * 20
        buf = pack_config(long_name, WHEEL_LEFT, 100, 0, 0, 0)
        name_raw = buf[0:NAME_MAX_LEN]
        self.assertEqual(len(name_raw), NAME_MAX_LEN)
        self.assertEqual(name_raw.rstrip(b'\x00'), b'A' * NAME_MAX_LEN)


class TestParseConfig(unittest.TestCase):
    """AC: Parse 22-byte Config → typed fields"""

    def test_roundtrip(self):
        original = ("WheelAthlete-R", WHEEL_RIGHT, 200, 0, 2, 1)
        buf = pack_config(*original)
        parsed = parse_config(buf)
        self.assertEqual(parsed, original)

    def test_short_name_roundtrip(self):
        original = ("L1", WHEEL_LEFT, 50, 1, 0, 0)
        buf = pack_config(*original)
        parsed = parse_config(buf)
        self.assertEqual(parsed, original)

    def test_empty_name(self):
        buf = pack_config("", WHEEL_LEFT, 100, 0, 0, 0)
        name, wheel, rate, _, _, _ = parse_config(buf)
        self.assertEqual(name, "")

    def test_truncated_buffer_raises(self):
        with self.assertRaises(ValueError):
            parse_config(b'\x00' * 21)


class TestWheelValidation(unittest.TestCase):
    """AC: SET_WHEEL accepts only 0x4C (L) or 0x52 (R)"""

    def test_valid_left(self):
        self.assertTrue(is_valid_wheel(WHEEL_LEFT))

    def test_valid_right(self):
        self.assertTrue(is_valid_wheel(WHEEL_RIGHT))

    def test_invalid_other(self):
        self.assertFalse(is_valid_wheel(0x41))  # 'A'
        self.assertFalse(is_valid_wheel(0x00))
        self.assertFalse(is_valid_wheel(0xFF))


class TestRateValidation(unittest.TestCase):
    """AC: SET_RATE accepts only 50/100/200"""

    def test_valid_rates(self):
        for r in VALID_RATES:
            self.assertTrue(is_valid_rate(r))

    def test_invalid_rates(self):
        self.assertFalse(is_valid_rate(0))
        self.assertFalse(is_valid_rate(75))
        self.assertFalse(is_valid_rate(500))


class TestSanitizeName(unittest.TestCase):
    """AC: Board name sanitized to 16-byte ASCII null-padded buffer"""

    def test_short_name_padded(self):
        buf = sanitize_name("Hello")
        self.assertEqual(len(buf), NAME_MAX_LEN)
        self.assertEqual(buf[0:5], b'Hello')
        self.assertEqual(buf[5:], b'\x00' * 11)

    def test_exact_16_chars(self):
        name = "A" * 16
        buf = sanitize_name(name)
        self.assertEqual(len(buf), NAME_MAX_LEN)
        self.assertEqual(buf, b'A' * 16)

    def test_truncated(self):
        buf = sanitize_name("A" * 30)
        self.assertEqual(len(buf), NAME_MAX_LEN)
        self.assertEqual(buf, b'A' * 16)

    def test_empty_name(self):
        buf = sanitize_name("")
        self.assertEqual(len(buf), NAME_MAX_LEN)
        self.assertEqual(buf, b'\x00' * 16)


if __name__ == '__main__':
    unittest.main(verbosity=2)
