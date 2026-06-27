// test/test_imu_types.cpp — Host-side unit tests for imu_types.h pure logic
//
// Tests: struct size, scale tables, rate validation, FIFO overflow detection,
// FIFO byte parsing, timestamp interpolation.
//
// Run: pio test -e native
// These tests run on the host (no ESP32 hardware needed).

#include <unity.h>
#include <cstring>
#include <cmath>
#include "../src/imu_types.h"

using namespace wheelsense;

void setUp(void) {}
void tearDown(void) {}

// ── 1. ImuSample struct size (BLE protocol §2.1: must be 20 bytes) ──────────

void test_imu_sample_is_20_bytes(void) {
    TEST_ASSERT_EQUAL(20, sizeof(ImuSample));
}

void test_imu_sample_field_offsets(void) {
    ImuSample s{};
    TEST_ASSERT_EQUAL(0,  offsetof(ImuSample, seq));
    TEST_ASSERT_EQUAL(4,  offsetof(ImuSample, t_device_us));
    TEST_ASSERT_EQUAL(8,  offsetof(ImuSample, ax));
    TEST_ASSERT_EQUAL(10, offsetof(ImuSample, ay));
    TEST_ASSERT_EQUAL(12, offsetof(ImuSample, az));
    TEST_ASSERT_EQUAL(14, offsetof(ImuSample, gx));
    TEST_ASSERT_EQUAL(16, offsetof(ImuSample, gy));
    TEST_ASSERT_EQUAL(18, offsetof(ImuSample, gz));
}

// ── 2. Scale factor tables ───────────────────────────────────────────────────

void test_accel_scale_g2(void) {
    TEST_ASSERT_FLOAT_WITHIN(1e-7, 2.0f / 32768.0f, accelScale(AccelRange::G2));
}

void test_accel_scale_g4(void) {
    TEST_ASSERT_FLOAT_WITHIN(1e-7, 4.0f / 32768.0f, accelScale(AccelRange::G4));
}

void test_accel_scale_g8(void) {
    TEST_ASSERT_FLOAT_WITHIN(1e-7, 8.0f / 32768.0f, accelScale(AccelRange::G8));
}

void test_accel_scale_g16(void) {
    TEST_ASSERT_FLOAT_WITHIN(1e-7, 16.0f / 32768.0f, accelScale(AccelRange::G16));
}

void test_gyro_scale_dps250(void) {
    TEST_ASSERT_FLOAT_WITHIN(1e-7, 250.0f / 32768.0f, gyroScale(GyroRange::DPS250));
}

void test_gyro_scale_dps2000(void) {
    TEST_ASSERT_FLOAT_WITHIN(1e-7, 2000.0f / 32768.0f, gyroScale(GyroRange::DPS2000));
}

// ── 3. Sample rate validation ────────────────────────────────────────────────

void test_valid_rates(void) {
    TEST_ASSERT_TRUE(isValidRate(50));
    TEST_ASSERT_TRUE(isValidRate(100));
    TEST_ASSERT_TRUE(isValidRate(200));
}

void test_invalid_rates(void) {
    TEST_ASSERT_FALSE(isValidRate(0));
    TEST_ASSERT_FALSE(isValidRate(75));
    TEST_ASSERT_FALSE(isValidRate(150));
    TEST_ASSERT_FALSE(isValidRate(201));
    TEST_ASSERT_FALSE(isValidRate(500));
}

void test_rate_divisor_50hz(void) {
    // 1000 / 50 - 1 = 19
    TEST_ASSERT_EQUAL(19, sampleRateDivisor(50));
}

void test_rate_divisor_100hz(void) {
    // 1000 / 100 - 1 = 9
    TEST_ASSERT_EQUAL(9, sampleRateDivisor(100));
}

void test_rate_divisor_200hz(void) {
    // 1000 / 200 - 1 = 4
    TEST_ASSERT_EQUAL(4, sampleRateDivisor(200));
}

void test_rate_divisor_invalid_returns_sentinel(void) {
    TEST_ASSERT_EQUAL(0xFFFF, sampleRateDivisor(75));
    TEST_ASSERT_EQUAL(0xFFFF, sampleRateDivisor(0));
}

// ── 4. FIFO overflow detection ───────────────────────────────────────────────

void test_fifo_not_overflowed_under_capacity(void) {
    TEST_ASSERT_FALSE(fifoOverflowed(0));
    TEST_ASSERT_FALSE(fifoOverflowed(120));    // 10 samples
    TEST_ASSERT_FALSE(fifoOverflowed(504));    // 42 samples
    TEST_ASSERT_FALSE(fifoOverflowed(511));    // just under
}

void test_fifo_overflowed_at_capacity(void) {
    TEST_ASSERT_TRUE(fifoOverflowed(512));     // exactly capacity
    TEST_ASSERT_TRUE(fifoOverflowed(1024));    // way over
}

// ── 5. FIFO byte parsing (big-endian int16) ──────────────────────────────────

void test_parse_fifo_sample_positive_values(void) {
    uint8_t raw[12] = {
        0x00, 0x64,   // ax = 100
        0x00, 0xC8,   // ay = 200
        0x01, 0x2C,   // az = 300
        0x00, 0x0A,   // gx = 10
        0x00, 0x14,   // gy = 20
        0x00, 0x1E,   // gz = 30
    };
    ImuSample s{};
    parseFifoSample(raw, s);
    TEST_ASSERT_EQUAL(100,  s.ax);
    TEST_ASSERT_EQUAL(200,  s.ay);
    TEST_ASSERT_EQUAL(300,  s.az);
    TEST_ASSERT_EQUAL(10,   s.gx);
    TEST_ASSERT_EQUAL(20,   s.gy);
    TEST_ASSERT_EQUAL(30,   s.gz);
}

void test_parse_fifo_sample_negative_values(void) {
    uint8_t raw[12] = {
        0xFF, 0x9C,   // ax = -100
        0xFF, 0x38,   // ay = -200
        0xFE, 0xD4,   // az = -300
        0xFF, 0xF6,   // gx = -10
        0xFF, 0xEC,   // gy = -20
        0xFF, 0xE2,   // gz = -30
    };
    ImuSample s{};
    parseFifoSample(raw, s);
    TEST_ASSERT_EQUAL(-100, s.ax);
    TEST_ASSERT_EQUAL(-200, s.ay);
    TEST_ASSERT_EQUAL(-300, s.az);
    TEST_ASSERT_EQUAL(-10,  s.gx);
    TEST_ASSERT_EQUAL(-20,  s.gy);
    TEST_ASSERT_EQUAL(-30,  s.gz);
}

void test_parse_fifo_sample_max_min(void) {
    uint8_t raw[12] = {
        0x7F, 0xFF,   // ax = 32767 (max int16)
        0x80, 0x00,   // ay = -32768 (min int16)
        0x00, 0x00,   // az = 0
        0x7F, 0xFF,   // gx = 32767
        0x80, 0x00,   // gy = -32768
        0x00, 0x00,   // gz = 0
    };
    ImuSample s{};
    parseFifoSample(raw, s);
    TEST_ASSERT_EQUAL(32767,  s.ax);
    TEST_ASSERT_EQUAL(-32768, s.ay);
    TEST_ASSERT_EQUAL(0,      s.az);
    TEST_ASSERT_EQUAL(32767,  s.gx);
    TEST_ASSERT_EQUAL(-32768, s.gy);
    TEST_ASSERT_EQUAL(0,      s.gz);
}

// ── 6. Timestamp interpolation ───────────────────────────────────────────────
// Critical for clock sync (#7): each sample in a batch must get a distinct
// timestamp reflecting when it was actually captured, not the drain time.

void test_interpolate_timestamp_single_sample(void) {
    // 1 sample: timestamp = drain time (no offset)
    TEST_ASSERT_EQUAL(1000000u, interpolateTimestamp(1000000u, 100, 1, 0));
}

void test_interpolate_timestamp_oldest_in_batch(void) {
    // 5 samples at 100 Hz (interval = 10000 us), oldest (index 0):
    // drain - (5-1-0) * 10000 = drain - 40000
    const uint32_t drain = 5000000u;
    const uint32_t expected = drain - 40000u;
    TEST_ASSERT_EQUAL(expected, interpolateTimestamp(drain, 100, 5, 0));
}

void test_interpolate_timestamp_newest_in_batch(void) {
    // 5 samples at 100 Hz, newest (index 4):
    // drain - (5-1-4) * 10000 = drain - 0 = drain
    const uint32_t drain = 5000000u;
    TEST_ASSERT_EQUAL(drain, interpolateTimestamp(drain, 100, 5, 4));
}

void test_interpolate_timestamp_middle_in_batch(void) {
    // 5 samples at 100 Hz, middle (index 2):
    // drain - (5-1-2) * 10000 = drain - 20000
    const uint32_t drain = 5000000u;
    const uint32_t expected = drain - 20000u;
    TEST_ASSERT_EQUAL(expected, interpolateTimestamp(drain, 100, 5, 2));
}

void test_interpolate_timestamp_200hz_interval(void) {
    // 3 samples at 200 Hz (interval = 5000 us), oldest:
    // drain - (3-1-0) * 5000 = drain - 10000
    const uint32_t drain = 2000000u;
    TEST_ASSERT_EQUAL(drain - 10000u, interpolateTimestamp(drain, 200, 3, 0));
}

void test_interpolate_timestamp_50hz_interval(void) {
    // 2 samples at 50 Hz (interval = 20000 us), oldest:
    // drain - (2-1-0) * 20000 = drain - 20000
    const uint32_t drain = 1000000u;
    TEST_ASSERT_EQUAL(drain - 20000u, interpolateTimestamp(drain, 50, 2, 0));
}

void test_interpolate_timestamps_are_distinct(void) {
    // The bug we fixed: all samples in a batch must NOT have the same timestamp
    const uint32_t drain = 5000000u;
    const uint32_t t0 = interpolateTimestamp(drain, 100, 5, 0);
    const uint32_t t1 = interpolateTimestamp(drain, 100, 5, 1);
    const uint32_t t2 = interpolateTimestamp(drain, 100, 5, 2);
    const uint32_t t3 = interpolateTimestamp(drain, 100, 5, 3);
    const uint32_t t4 = interpolateTimestamp(drain, 100, 5, 4);
    TEST_ASSERT_TRUE(t0 < t1);
    TEST_ASSERT_TRUE(t1 < t2);
    TEST_ASSERT_TRUE(t2 < t3);
    TEST_ASSERT_TRUE(t3 < t4);
}

void test_interpolate_timestamps_spacing_matches_rate(void) {
    // Consecutive samples should be exactly 1/rate_hz apart
    const uint32_t drain = 5000000u;
    const uint32_t t0 = interpolateTimestamp(drain, 100, 5, 0);
    const uint32_t t1 = interpolateTimestamp(drain, 100, 5, 1);
    TEST_ASSERT_EQUAL(10000u, t1 - t0);   // 1/100 Hz = 10000 us
}

// ── Runner ───────────────────────────────────────────────────────────────────

int main() {
    UNITY_BEGIN();

    // 1. Struct size
    RUN_TEST(test_imu_sample_is_20_bytes);
    RUN_TEST(test_imu_sample_field_offsets);

    // 2. Scale tables
    RUN_TEST(test_accel_scale_g2);
    RUN_TEST(test_accel_scale_g4);
    RUN_TEST(test_accel_scale_g8);
    RUN_TEST(test_accel_scale_g16);
    RUN_TEST(test_gyro_scale_dps250);
    RUN_TEST(test_gyro_scale_dps2000);

    // 3. Rate validation
    RUN_TEST(test_valid_rates);
    RUN_TEST(test_invalid_rates);
    RUN_TEST(test_rate_divisor_50hz);
    RUN_TEST(test_rate_divisor_100hz);
    RUN_TEST(test_rate_divisor_200hz);
    RUN_TEST(test_rate_divisor_invalid_returns_sentinel);

    // 4. FIFO overflow
    RUN_TEST(test_fifo_not_overflowed_under_capacity);
    RUN_TEST(test_fifo_overflowed_at_capacity);

    // 5. FIFO parsing
    RUN_TEST(test_parse_fifo_sample_positive_values);
    RUN_TEST(test_parse_fifo_sample_negative_values);
    RUN_TEST(test_parse_fifo_sample_max_min);

    // 6. Timestamp interpolation
    RUN_TEST(test_interpolate_timestamp_single_sample);
    RUN_TEST(test_interpolate_timestamp_oldest_in_batch);
    RUN_TEST(test_interpolate_timestamp_newest_in_batch);
    RUN_TEST(test_interpolate_timestamp_middle_in_batch);
    RUN_TEST(test_interpolate_timestamp_200hz_interval);
    RUN_TEST(test_interpolate_timestamp_50hz_interval);
    RUN_TEST(test_interpolate_timestamps_are_distinct);
    RUN_TEST(test_interpolate_timestamps_spacing_matches_rate);

    return UNITY_END();
}
