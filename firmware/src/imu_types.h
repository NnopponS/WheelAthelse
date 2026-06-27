#pragma once
// imu_types.h — Pure logic for IMU data types, scale factors, rate math,
// FIFO byte parsing, and timestamp interpolation.
//
// This header is HARDWARE-FREE (no Arduino/Wire/esp_timer) so it can be
// unit-tested on the host via `pio test -e native`.
// The hardware-dependent ImuReader class in imu_reader.h/.cpp uses these types.
//
// Architecture reference: .project/architecture.md §1 (Firmware)
// BLE packet format:      docs/ble-protocol.md §2 (IMU Data)

#include <cstdint>
#include <cstddef>

namespace WheelAthlete {

// ── Constants (constexpr per ES.45 / ES.25) ──────────────────────────────────

// MPU6886 I2C address on M5StickCPlus2 internal bus (AD0 = 0)
constexpr uint8_t  MPU6886_ADDR = 0x68;

// FIFO sample size: 6 bytes accel + 6 bytes gyro = 12 bytes (big-endian int16)
constexpr size_t   FIFO_SAMPLE_BYTES = 12;

// MPU6886 FIFO capacity in bytes
constexpr size_t   FIFO_CAPACITY_BYTES = 512;

// FreeRTOS queue depth — enough for ~0.3 s at 200 Hz
constexpr size_t   SAMPLE_QUEUE_LEN = 64;

// Supported sample rates (Hz) — only these three are valid
constexpr uint16_t MIN_SAMPLE_RATE_HZ = 50;
constexpr uint16_t MAX_SAMPLE_RATE_HZ = 200;
constexpr uint16_t DEFAULT_SAMPLE_RATE_HZ = 100;

// ── Enum class for IMU ranges (Enum.3: typed) ────────────────────────────────

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

// ── ImuSample — matches BLE protocol §2.1 (20 bytes) ─────────────────────────

struct ImuSample {
    uint32_t seq;            // sample sequence number (wraps at 2^32)
    uint32_t t_device_us;    // micros() at sample time
    int16_t  ax, ay, az;     // accel raw (LSB)
    int16_t  gx, gy, gz;     // gyro raw (LSB)
};

// Compile-time guarantee: BLE packet must be exactly 20 bytes.
// If this fails, the struct has padding and the BLE packet will be wrong.
static_assert(sizeof(ImuSample) == 20, "ImuSample must be 20 bytes per BLE protocol §2.1");

// ── Scale factor tables (constexpr, ES.45) ───────────────────────────────────
// accel_scale[range] = full_scale_g / 32768
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

// ACCEL_CONFIG register bits: AFS_SEL << 3
constexpr uint8_t ACCEL_CONFIG_VAL[] = { 0x00, 0x08, 0x10, 0x18 };
constexpr uint8_t GYRO_CONFIG_VAL[]  = { 0x00, 0x08, 0x10, 0x18 };

// ── Pure functions (testable on host) ────────────────────────────────────────

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

// Compute SMPLRT_DIV register value for a given rate.
// MPU6886: output_rate = 1000 / (1 + SMPLRT_DIV) when DLPF=0x03 (1 kHz internal)
// Returns the divider, or 0xFFFF if the rate is invalid.
inline uint16_t sampleRateDivisor(uint16_t rate_hz) {
    if (!isValidRate(rate_hz)) return 0xFFFF;
    return static_cast<uint16_t>(1000u / rate_hz - 1u);
}

// Check if FIFO byte count indicates overflow.
// MPU6886 FIFO is 512 bytes; if fifo_bytes >= capacity, data was lost.
inline bool fifoOverflowed(uint16_t fifo_bytes) {
    return fifo_bytes >= FIFO_CAPACITY_BYTES;
}

// Parse one FIFO sample (12 bytes, big-endian int16) into ImuSample fields.
// Fills ax..gz from the raw bytes. Does NOT set seq or t_device_us.
inline void parseFifoSample(const uint8_t* p, ImuSample& out) {
    out.ax = static_cast<int16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
    out.ay = static_cast<int16_t>((static_cast<uint16_t>(p[2]) << 8) | p[3]);
    out.az = static_cast<int16_t>((static_cast<uint16_t>(p[4]) << 8) | p[5]);
    out.gx = static_cast<int16_t>((static_cast<uint16_t>(p[6]) << 8) | p[7]);
    out.gy = static_cast<int16_t>((static_cast<uint16_t>(p[8]) << 8) | p[9]);
    out.gz = static_cast<int16_t>((static_cast<uint16_t>(p[10]) << 8) | p[11]);
}

// Interpolate device timestamp for a sample within a batch.
//
// When draining the FIFO, we read N samples that were captured at different
// times but we only know the current micros() at drain time.  The oldest
// sample was captured approximately (N-1) * sample_interval_us before the
// newest.  This function computes the timestamp for sample at index `i`
// (0 = oldest) given the drain time and sample count.
//
// sample_interval_us = 1e6 / rate_hz
// t_sample[i] = drain_us - (n - 1 - i) * sample_interval_us
//
// This is critical for clock sync (#7): if every sample gets the same
// timestamp, the sync engine cannot align L/R data accurately.
inline uint32_t interpolateTimestamp(uint32_t drain_us,
                                     uint16_t rate_hz,
                                     uint16_t n_samples,
                                     uint16_t sample_index) {
    const uint32_t interval_us = 1000000u / rate_hz;
    const uint32_t offset_us   = static_cast<uint32_t>(n_samples - 1 - sample_index) * interval_us;
    return drain_us - offset_us;
}

} // namespace WheelAthlete
