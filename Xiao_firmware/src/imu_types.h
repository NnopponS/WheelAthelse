#pragma once
// imu_types.h — Pure logic for IMU data types, scale factors, rate math,
// and timestamp interpolation.
//
// This header is HARDWARE-FREE so it can be easily shared.
//
// BLE packet format:      docs/ble-protocol.md §2 (IMU Data)

#include <cstdint>
#include <cstddef>

namespace WheelAthlete {

// FreeRTOS queue depth — enough for ~1.28 s at 200 Hz.
constexpr size_t   SAMPLE_QUEUE_LEN = 256;

// Supported sample rates (Hz) — only these three are valid
constexpr uint16_t MIN_SAMPLE_RATE_HZ = 50;
constexpr uint16_t MAX_SAMPLE_RATE_HZ = 200;
constexpr uint16_t DEFAULT_SAMPLE_RATE_HZ = 100;

// ── Enum class for IMU ranges ──
enum class AccelRange : uint8_t {
    G2   = 0,   // ±2g
    G4   = 1,   // ±4g
    G8   = 2,   // ±8g
    G16  = 3,   // ±16g
};

enum class GyroRange : uint8_t {
    DPS250  = 0,   // ±250 dps
    DPS500  = 1,   // ±500 dps
    DPS1000 = 2,   // ±1000 dps
    DPS2000 = 3,   // ±2000 dps
};

// ── ImuSample — matches BLE protocol §2.1 (20 bytes) ──
struct ImuSample {
    uint32_t seq;            // sample sequence number (wraps at 2^32)
    uint32_t t_device_us;    // micros() at sample time
    int16_t  ax, ay, az;     // accel raw (LSB)
    int16_t  gx, gy, gz;     // gyro raw (LSB)
};

static_assert(sizeof(ImuSample) == 20, "ImuSample must be 20 bytes per BLE protocol §2.1");

// ── Scale factor tables ──
constexpr float ACCEL_SCALE_TABLE[] = {
    2.0f  / 32768.0f,   // ±2g
    4.0f  / 32768.0f,   // ±4g
    8.0f  / 32768.0f,   // ±8g
    16.0f / 32768.0f,   // ±16g
};

constexpr float GYRO_SCALE_TABLE[] = {
    250.0f  / 32768.0f,   // ±250 dps
    500.0f  / 32768.0f,   // ±500 dps
    1000.0f / 32768.0f,   // ±1000 dps
    2000.0f / 32768.0f,   // ±2000 dps
};

// Get accel scale factor (LSB → g) for a given range
inline float accelScale(AccelRange r) {
    return ACCEL_SCALE_TABLE[static_cast<size_t>(r)];
}

// Get gyro scale factor (LSB → dps) for a given range
inline float gyroScale(GyroRange r) {
    return GYRO_SCALE_TABLE[static_cast<size_t>(r)];
}

// Check if a sample rate is one of the supported values (50/100/200 Hz)
inline bool isValidRate(uint16_t rate_hz) {
    return rate_hz == 50 || rate_hz == 100 || rate_hz == 200;
}

// Interpolate device timestamp for a sample within a batch.
inline uint32_t interpolateTimestamp(uint32_t drain_us,
                                     uint16_t rate_hz,
                                     uint16_t n_samples,
                                     uint16_t sample_index) {
    const uint32_t interval_us = 1000000u / rate_hz;
    const uint32_t offset_us   = static_cast<uint32_t>(n_samples - 1 - sample_index) * interval_us;
    return drain_us - offset_us;
}

} // namespace WheelAthlete
