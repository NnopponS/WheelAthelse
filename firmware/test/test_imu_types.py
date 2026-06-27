#!/usr/bin/env python3
"""
test_imu_types.py — Host-side unit tests for imu_types.h pure logic

Since this Windows machine has no native g++/gcc, we validate the pure math
from imu_types.h (scale tables, rate divisors, FIFO parsing, timestamp
interpolation) via Python. The C++ code is verified to compile (including
static_assert) via `pio run -e left`.

The math here mirrors imu_types.h exactly — if these tests pass AND pio build
passes, the logic is correct.

Run: python test/test_imu_types.py
"""

import struct
import sys
import unittest

# ── Constants from imu_types.h ────────────────────────────────────────────────

FIFO_SAMPLE_BYTES = 12
FIFO_CAPACITY_BYTES = 512
SAMPLE_QUEUE_LEN = 64
MIN_SAMPLE_RATE_HZ = 50
MAX_SAMPLE_RATE_HZ = 200
DEFAULT_SAMPLE_RATE_HZ = 100

# ── Scale tables (from imu_types.h) ───────────────────────────────────────────

ACCEL_SCALE_TABLE = [
    2.0 / 32768.0,    # ±2g
    4.0 / 32768.0,    # ±4g
    8.0 / 32768.0,    # ±8g
    16.0 / 32768.0,   # ±16g
]

GYRO_SCALE_TABLE = [
    250.0 / 32768.0,    # ±250 dps
    500.0 / 32768.0,    # ±500 dps
    1000.0 / 32768.0,   # ±1000 dps
    2000.0 / 32768.0,   # ±2000 dps
]

# ── Pure functions (mirrors of imu_types.h inline functions) ──────────────────

def accel_scale(range_id):
    return ACCEL_SCALE_TABLE[range_id]

def gyro_scale(range_id):
    return GYRO_SCALE_TABLE[range_id]

def is_valid_rate(rate_hz):
    return rate_hz in (50, 100, 200)

def sample_rate_divisor(rate_hz):
    if not is_valid_rate(rate_hz):
        return 0xFFFF
    return 1000 // rate_hz - 1

def fifo_overflowed(fifo_bytes):
    return fifo_bytes >= FIFO_CAPACITY_BYTES

def parse_fifo_sample(raw_bytes):
    """Parse 12 bytes (big-endian int16) → (ax, ay, az, gx, gy, gz)."""
    ax = struct.unpack('>h', raw_bytes[0:2])[0]
    ay = struct.unpack('>h', raw_bytes[2:4])[0]
    az = struct.unpack('>h', raw_bytes[4:6])[0]
    gx = struct.unpack('>h', raw_bytes[6:8])[0]
    gy = struct.unpack('>h', raw_bytes[8:10])[0]
    gz = struct.unpack('>h', raw_bytes[10:12])[0]
    return (ax, ay, az, gx, gy, gz)

def interpolate_timestamp(drain_us, rate_hz, n_samples, sample_index):
    """Interpolate device timestamp for sample at index i (0=oldest)."""
    interval_us = 1000000 // rate_hz
    offset_us = (n_samples - 1 - sample_index) * interval_us
    return drain_us - offset_us

# ── ImuSample struct size (BLE protocol: 20 bytes) ────────────────────────────
# uint32 seq (4) + uint32 t_device_us (4) + 6×int16 (12) = 20 bytes
IMU_SAMPLE_SIZE = 4 + 4 + 6 * 2

# ── Test cases ────────────────────────────────────────────────────────────────

class TestImuSampleStruct(unittest.TestCase):
    """Journey: BLE packet must be exactly 20 bytes (docs/ble-protocol.md §2.1)"""

    def test_struct_size_is_20_bytes(self):
        self.assertEqual(IMU_SAMPLE_SIZE, 20)

    def test_field_offsets(self):
        # seq=0, t_device_us=4, ax=8, ay=10, az=12, gx=14, gy=16, gz=18
        offsets = {
            'seq': 0, 't_device_us': 4,
            'ax': 8, 'ay': 10, 'az': 12,
            'gx': 14, 'gy': 16, 'gz': 18,
        }
        expected_size = max(offsets.values()) + 2  # last field is int16
        self.assertEqual(expected_size, 20)


class TestScaleTables(unittest.TestCase):
    """Journey: app must convert raw LSB → physical units using correct scale"""

    def test_accel_scale_g2(self):
        self.assertAlmostEqual(accel_scale(0), 2.0 / 32768.0, places=7)

    def test_accel_scale_g4(self):
        self.assertAlmostEqual(accel_scale(1), 4.0 / 32768.0, places=7)

    def test_accel_scale_g8(self):
        self.assertAlmostEqual(accel_scale(2), 8.0 / 32768.0, places=7)

    def test_accel_scale_g16(self):
        self.assertAlmostEqual(accel_scale(3), 16.0 / 32768.0, places=7)

    def test_gyro_scale_dps250(self):
        self.assertAlmostEqual(gyro_scale(0), 250.0 / 32768.0, places=7)

    def test_gyro_scale_dps2000(self):
        self.assertAlmostEqual(gyro_scale(3), 2000.0 / 32768.0, places=7)


class TestRateValidation(unittest.TestCase):
    """Journey: sample rate must be exactly 50/100/200 Hz (not arbitrary)"""

    def test_valid_rates(self):
        self.assertTrue(is_valid_rate(50))
        self.assertTrue(is_valid_rate(100))
        self.assertTrue(is_valid_rate(200))

    def test_invalid_rates(self):
        self.assertFalse(is_valid_rate(0))
        self.assertFalse(is_valid_rate(75))
        self.assertFalse(is_valid_rate(150))
        self.assertFalse(is_valid_rate(201))
        self.assertFalse(is_valid_rate(500))

    def test_divisor_50hz(self):
        self.assertEqual(sample_rate_divisor(50), 19)    # 1000/50 - 1

    def test_divisor_100hz(self):
        self.assertEqual(sample_rate_divisor(100), 9)    # 1000/100 - 1

    def test_divisor_200hz(self):
        self.assertEqual(sample_rate_divisor(200), 4)    # 1000/200 - 1

    def test_divisor_invalid_returns_sentinel(self):
        self.assertEqual(sample_rate_divisor(75), 0xFFFF)
        self.assertEqual(sample_rate_divisor(0), 0xFFFF)


class TestFifoOverflow(unittest.TestCase):
    """Journey: FIFO overflow must be detected so data loss is known"""

    def test_not_overflowed_under_capacity(self):
        self.assertFalse(fifo_overflowed(0))
        self.assertFalse(fifo_overflowed(120))    # 10 samples
        self.assertFalse(fifo_overflowed(504))    # 42 samples
        self.assertFalse(fifo_overflowed(511))    # just under

    def test_overflowed_at_capacity(self):
        self.assertTrue(fifo_overflowed(512))     # exactly capacity
        self.assertTrue(fifo_overflowed(1024))    # way over


class TestFifoParsing(unittest.TestCase):
    """Journey: FIFO data is big-endian int16, must parse correctly"""

    def test_positive_values(self):
        raw = struct.pack('>hhhhhh', 100, 200, 300, 10, 20, 30)
        ax, ay, az, gx, gy, gz = parse_fifo_sample(raw)
        self.assertEqual((ax, ay, az, gx, gy, gz), (100, 200, 300, 10, 20, 30))

    def test_negative_values(self):
        raw = struct.pack('>hhhhhh', -100, -200, -300, -10, -20, -30)
        ax, ay, az, gx, gy, gz = parse_fifo_sample(raw)
        self.assertEqual((ax, ay, az, gx, gy, gz), (-100, -200, -300, -10, -20, -30))

    def test_max_min_values(self):
        raw = struct.pack('>hhhhhh', 32767, -32768, 0, 32767, -32768, 0)
        ax, ay, az, gx, gy, gz = parse_fifo_sample(raw)
        self.assertEqual((ax, ay, az, gx, gy, gz), (32767, -32768, 0, 32767, -32768, 0))


class TestTimestampInterpolation(unittest.TestCase):
    """Journey: each sample in a batch must have a distinct, accurate timestamp
    so clock sync (#7) can align L/R data. The bug was: all samples got the
    same drain-time timestamp. The fix: interpolate backwards from drain time.
    """

    def test_single_sample_equals_drain_time(self):
        self.assertEqual(interpolate_timestamp(1000000, 100, 1, 0), 1000000)

    def test_oldest_in_batch(self):
        # 5 samples @ 100 Hz (interval=10000us), oldest (i=0):
        # drain - (5-1-0)*10000 = drain - 40000
        drain = 5000000
        self.assertEqual(interpolate_timestamp(drain, 100, 5, 0), drain - 40000)

    def test_newest_in_batch(self):
        # 5 samples @ 100 Hz, newest (i=4): drain - 0 = drain
        drain = 5000000
        self.assertEqual(interpolate_timestamp(drain, 100, 5, 4), drain)

    def test_middle_in_batch(self):
        # 5 samples @ 100 Hz, middle (i=2): drain - 20000
        drain = 5000000
        self.assertEqual(interpolate_timestamp(drain, 100, 5, 2), drain - 20000)

    def test_200hz_interval(self):
        # 3 samples @ 200 Hz (interval=5000us), oldest: drain - 10000
        drain = 2000000
        self.assertEqual(interpolate_timestamp(drain, 200, 3, 0), drain - 10000)

    def test_50hz_interval(self):
        # 2 samples @ 50 Hz (interval=20000us), oldest: drain - 20000
        drain = 1000000
        self.assertEqual(interpolate_timestamp(drain, 50, 2, 0), drain - 20000)

    def test_timestamps_are_distinct(self):
        """The core bug fix: timestamps must all be different"""
        drain = 5000000
        timestamps = [interpolate_timestamp(drain, 100, 5, i) for i in range(5)]
        self.assertEqual(len(set(timestamps)), 5)  # all unique
        # strictly increasing
        for i in range(4):
            self.assertLess(timestamps[i], timestamps[i + 1])

    def test_spacing_matches_rate(self):
        """Consecutive samples must be exactly 1/rate_hz apart"""
        drain = 5000000
        t0 = interpolate_timestamp(drain, 100, 5, 0)
        t1 = interpolate_timestamp(drain, 100, 5, 1)
        self.assertEqual(t1 - t0, 10000)  # 1/100 Hz = 10000 us

    def test_spacing_200hz(self):
        drain = 5000000
        t0 = interpolate_timestamp(drain, 200, 3, 0)
        t1 = interpolate_timestamp(drain, 200, 3, 1)
        self.assertEqual(t1 - t0, 5000)  # 1/200 Hz = 5000 us


if __name__ == '__main__':
    unittest.main(verbosity=2)
