#!/usr/bin/env python3
"""
test_ble_types.py — Host-side unit tests for ble_types.h pure logic

Tests: packet packing (sample, batch, sync response, events, info),
batch size calculation, beep schedule, scheduled start, command parsing.

Run: python -m pytest test/test_ble_types.py -v
"""

import struct
import unittest

# ── Constants from ble_types.h ────────────────────────────────────────────────

IMU_SAMPLE_SIZE = 20
SYNC_RESPONSE_SIZE = 12
INFO_SIZE = 16

# Control commands
CMD_START = 0x01
CMD_STOP = 0x02
CMD_SET_RATE = 0x03
CMD_SYNC_PING = 0x04
CMD_SET_RANGE = 0x05
CMD_BEEP = 0x06
CMD_SET_NAME = 0x07
CMD_SET_WHEEL = 0x08
CMD_RESET_SEQ = 0xFF

# Battery Service (standard BLE)
BATTERY_SERVICE_UUID_SHORT = 0x180F
BATTERY_LEVEL_CHAR_UUID_SHORT = 0x2A19
BATTERY_LEVEL_SIZE = 1   # uint8 0-100

# Sync events
EVENT_SYNC_RESPONSE = 0x00
EVENT_DROP_COUNT = 0x10
EVENT_CMD_NACK = 0x20
EVENT_START_FIRED = 0x30
EVENT_STOP_FIRED = 0x40

# Beep schedule
BEEP_SCHEDULE = [
    (-3_000_000, 880, 150),   # T-3s
    (-2_000_000, 880, 150),   # T-2s
    (-1_000_000, 880, 150),   # T-1s
    (0,           1320, 500), # T-0
]

# ── Pure functions (mirrors of ble_types.h) ───────────────────────────────────

def pack_sample(seq, t_device_us, ax, ay, az, gx, gy, gz):
    """Pack ImuSample → 20 bytes little-endian."""
    return struct.pack('<IIhhhhhh', seq, t_device_us, ax, ay, az, gx, gy, gz)

def pack_batch(samples):
    """Pack batch: [uint8 count][sample_0]..."""
    buf = struct.pack('<B', len(samples))
    for s in samples:
        buf += pack_sample(*s)
    return buf

def max_batch_count(mtu):
    """Max samples per notify given MTU."""
    if mtu <= 4:
        return 0
    payload = mtu - 3
    if payload <= 1:
        return 0
    return (payload - 1) // IMU_SAMPLE_SIZE

def pack_sync_response(t_app_ms, t_device_us, seq_ping):
    return struct.pack('<III', t_app_ms, t_device_us, seq_ping)

def pack_start_fired(t_device_us):
    return struct.pack('<BI', EVENT_START_FIRED, t_device_us)

def pack_stop_fired(t_device_us, last_seq):
    return struct.pack('<BII', EVENT_STOP_FIRED, t_device_us, last_seq)

def pack_drop_count_event(count):
    return struct.pack('<BI', EVENT_DROP_COUNT, count)

def pack_cmd_nack(cmd):
    return struct.pack('<BB', EVENT_CMD_NACK, cmd)

def pack_info(wheel_id, fw_major, fw_minor, fw_patch,
              accel_range, gyro_range, accel_scale, gyro_scale):
    return struct.pack('<BBBBBBffH', wheel_id, fw_major, fw_minor, fw_patch,
                       accel_range, gyro_range, accel_scale, gyro_scale, 0)

def check_beep_schedule(target_start_us, current_us, last_beep_fired):
    """Returns index of beep to fire, or -1."""
    for i in range(last_beep_fired + 1, len(BEEP_SCHEDULE)):
        beep_time = target_start_us + BEEP_SCHEDULE[i][0]
        if current_us >= beep_time:
            return i
    return -1

def should_start_now(target_start_us, current_us):
    if target_start_us == 0:
        return True
    return current_us >= target_start_us

def clamp_battery_level(raw):
    """Clamp raw battery reading to valid BLE Battery Level range [0, 100].
    M5.Power.getBatteryLevel() may return -1 (unknown) or values > 100.
    Returns 0 for negative/unknown, caps at 100."""
    if raw < 0:
        return 0
    if raw > 100:
        return 100
    return raw

# ── Test cases ────────────────────────────────────────────────────────────────

class TestPackSample(unittest.TestCase):
    """AC-2: IMU sample must be 20 bytes little-endian"""

    def test_sample_size(self):
        buf = pack_sample(1, 2000, 100, 200, 300, 10, 20, 30)
        self.assertEqual(len(buf), 20)

    def test_sample_fields(self):
        buf = pack_sample(42, 999999, 100, -200, 300, -10, 20, -30)
        seq, t_us, ax, ay, az, gx, gy, gz = struct.unpack('<IIhhhhhh', buf)
        self.assertEqual(seq, 42)
        self.assertEqual(t_us, 999999)
        self.assertEqual(ax, 100)
        self.assertEqual(ay, -200)
        self.assertEqual(az, 300)
        self.assertEqual(gx, -10)
        self.assertEqual(gy, 20)
        self.assertEqual(gz, -30)

    def test_sample_max_values(self):
        buf = pack_sample(0xFFFFFFFF, 0xFFFFFFFF, 32767, -32768, 0, 32767, -32768, 0)
        seq, t_us, ax, ay, az, gx, gy, gz = struct.unpack('<IIhhhhhh', buf)
        self.assertEqual(seq, 0xFFFFFFFF)
        self.assertEqual(ax, 32767)
        self.assertEqual(ay, -32768)


class TestPackBatch(unittest.TestCase):
    """AC-2: Batch packet = [count][sample_0]..."""

    def test_single_sample_batch(self):
        s = (1, 1000, 10, 20, 30, 40, 50, 60)
        buf = pack_batch([s])
        self.assertEqual(buf[0], 1)
        self.assertEqual(len(buf), 1 + 20)

    def test_multi_sample_batch(self):
        samples = [(i, i*100, 10, 20, 30, 40, 50, 60) for i in range(5)]
        buf = pack_batch(samples)
        self.assertEqual(buf[0], 5)
        self.assertEqual(len(buf), 1 + 5 * 20)

    def test_batch_count_byte(self):
        samples = [(0, 0, 0, 0, 0, 0, 0, 0)] * 12
        buf = pack_batch(samples)
        self.assertEqual(buf[0], 12)


class TestMaxBatchCount(unittest.TestCase):
    """AC-2: batch count = floor((MTU-3-1)/20)"""

    def test_mtu_247(self):
        # (247-3-1)/20 = 243/20 = 12
        self.assertEqual(max_batch_count(247), 12)

    def test_mtu_23(self):
        # (23-3-1)/20 = 19/20 = 0
        self.assertEqual(max_batch_count(23), 0)

    def test_mtu_24(self):
        # (24-3-1)/20 = 20/20 = 1
        self.assertEqual(max_batch_count(24), 1)

    def test_mtu_too_small(self):
        self.assertEqual(max_batch_count(3), 0)
        self.assertEqual(max_batch_count(4), 0)

    def test_mtu_185(self):
        # (185-3-1)/20 = 181/20 = 9
        self.assertEqual(max_batch_count(185), 9)


class TestSyncResponse(unittest.TestCase):
    """AC-4: Sync response = 12 bytes [t_app_ms][t_device_us][seq_ping]"""

    def test_size(self):
        buf = pack_sync_response(1000, 2000000, 5)
        self.assertEqual(len(buf), 12)

    def test_fields(self):
        buf = pack_sync_response(123456, 789012, 3)
        t_app, t_dev, seq = struct.unpack('<III', buf)
        self.assertEqual(t_app, 123456)
        self.assertEqual(t_dev, 789012)
        self.assertEqual(seq, 3)


class TestSyncEvents(unittest.TestCase):
    """AC-7: Event notifications with event_id in byte 0"""

    def test_start_fired(self):
        buf = pack_start_fired(5000000)
        self.assertEqual(buf[0], EVENT_START_FIRED)
        t_dev = struct.unpack('<I', buf[1:5])[0]
        self.assertEqual(t_dev, 5000000)
        self.assertEqual(len(buf), 5)

    def test_stop_fired(self):
        buf = pack_stop_fired(6000000, 9999)
        self.assertEqual(buf[0], EVENT_STOP_FIRED)
        t_dev, last_seq = struct.unpack('<II', buf[1:9])
        self.assertEqual(t_dev, 6000000)
        self.assertEqual(last_seq, 9999)
        self.assertEqual(len(buf), 9)

    def test_drop_count(self):
        buf = pack_drop_count_event(42)
        self.assertEqual(buf[0], EVENT_DROP_COUNT)
        count = struct.unpack('<I', buf[1:5])[0]
        self.assertEqual(count, 42)

    def test_cmd_nack(self):
        buf = pack_cmd_nack(0x99)
        self.assertEqual(buf[0], EVENT_CMD_NACK)
        self.assertEqual(buf[1], 0x99)


class TestInfoCharacteristic(unittest.TestCase):
    """AC-5: Info = 16 bytes with wheel_id, fw version, ranges, scales"""

    def test_size(self):
        buf = pack_info(0x4C, 0, 2, 0, 1, 3, 4.0/32768.0, 2000.0/32768.0)
        self.assertEqual(len(buf), 16)

    def test_wheel_id_L(self):
        buf = pack_info(0x4C, 0, 2, 0, 1, 3, 0.0001, 0.06)
        self.assertEqual(buf[0], 0x4C)  # 'L'

    def test_wheel_id_R(self):
        buf = pack_info(0x52, 0, 2, 0, 1, 3, 0.0001, 0.06)
        self.assertEqual(buf[0], 0x52)  # 'R'

    def test_fw_version(self):
        buf = pack_info(0x4C, 0, 2, 0, 1, 3, 0.0001, 0.06)
        self.assertEqual(buf[1], 0)   # major
        self.assertEqual(buf[2], 2)   # minor
        self.assertEqual(buf[3], 0)   # patch

    def test_ranges(self):
        buf = pack_info(0x4C, 0, 2, 0, 1, 3, 0.0001, 0.06)
        self.assertEqual(buf[4], 1)   # accel_range = ±4g
        self.assertEqual(buf[5], 3)   # gyro_range = ±2000 dps

    def test_scales(self):
        accel_scale = 4.0 / 32768.0
        gyro_scale = 2000.0 / 32768.0
        buf = pack_info(0x4C, 0, 2, 0, 1, 3, accel_scale, gyro_scale)
        a_scale = struct.unpack('<f', buf[6:10])[0]
        g_scale = struct.unpack('<f', buf[10:14])[0]
        self.assertAlmostEqual(a_scale, accel_scale, places=7)
        self.assertAlmostEqual(g_scale, gyro_scale, places=7)

    def test_reserved_is_zero(self):
        buf = pack_info(0x4C, 0, 2, 0, 1, 3, 0.0001, 0.06)
        reserved = struct.unpack('<H', buf[14:16])[0]
        self.assertEqual(reserved, 0)


class TestBeepSchedule(unittest.TestCase):
    """AC-6: Beep at T-3s, T-2s, T-1s, T-0"""

    def test_no_beep_before_t_minus_3(self):
        target = 10_000_000
        current = 10_000_000 - 4_000_000  # T-4s
        self.assertEqual(check_beep_schedule(target, current, -1), -1)

    def test_beep_at_t_minus_3(self):
        target = 10_000_000
        current = 10_000_000 - 3_000_000  # T-3s
        self.assertEqual(check_beep_schedule(target, current, -1), 0)

    def test_beep_at_t_minus_2(self):
        target = 10_000_000
        current = 10_000_000 - 2_000_000  # T-2s
        # beep 0 already fired, now beep 1
        self.assertEqual(check_beep_schedule(target, current, 0), 1)

    def test_beep_at_t_minus_1(self):
        target = 10_000_000
        current = 10_000_000 - 1_000_000  # T-1s
        self.assertEqual(check_beep_schedule(target, current, 1), 2)

    def test_beep_at_t_zero(self):
        target = 10_000_000
        current = 10_000_000  # T-0
        self.assertEqual(check_beep_schedule(target, current, 2), 3)

    def test_no_beep_after_all_fired(self):
        target = 10_000_000
        current = 10_000_000 + 5_000_000  # T+5s
        self.assertEqual(check_beep_schedule(target, current, 3), -1)

    def test_beeps_fire_in_order(self):
        """All 4 beeps must fire in sequence, never skip or repeat"""
        target = 10_000_000
        fired = []
        last = -1
        # Simulate time from T-4s to T+1s in 100ms steps
        for t_offset in range(-4_000_000, 1_000_000, 100_000):
            current = target + t_offset
            result = check_beep_schedule(target, current, last)
            if result >= 0:
                fired.append(result)
                last = result
        self.assertEqual(fired, [0, 1, 2, 3])


class TestScheduledStart(unittest.TestCase):
    """AC-6: Scheduled start — wait until micros >= target_start_us"""

    def test_start_immediately_when_target_zero(self):
        self.assertTrue(should_start_now(0, 12345))

    def test_start_when_time_reached(self):
        self.assertTrue(should_start_now(5_000_000, 5_000_000))
        self.assertTrue(should_start_now(5_000_000, 5_000_001))

    def test_wait_when_not_yet(self):
        self.assertFalse(should_start_now(5_000_000, 4_999_999))


class TestBatteryLevel(unittest.TestCase):
    """AC: Battery Service 0x180F + 0x2A19 — battery % must be uint8 0-100"""

    def test_clamp_normal_value(self):
        self.assertEqual(clamp_battery_level(75), 75)

    def test_clamp_zero(self):
        self.assertEqual(clamp_battery_level(0), 0)

    def test_clamp_full(self):
        self.assertEqual(clamp_battery_level(100), 100)

    def test_clamp_negative_unknown(self):
        """M5.Power.getBatteryLevel() returns -1 when unknown → 0"""
        self.assertEqual(clamp_battery_level(-1), 0)

    def test_clamp_above_100(self):
        """Some power ICs report >100 when fully charged + USB power"""
        self.assertEqual(clamp_battery_level(101), 100)
        self.assertEqual(clamp_battery_level(255), 100)

    def test_battery_level_is_single_byte(self):
        """0x2A19 Battery Level is a single uint8"""
        level = clamp_battery_level(50)
        self.assertEqual(level, 50)
        self.assertTrue(0 <= level <= 100)
        self.assertEqual(level.to_bytes(1, 'little'), b'\x32')


if __name__ == '__main__':
    unittest.main(verbosity=2)
