#pragma once
// imu_reader.h — MPU6886 IMU acquisition via hardware FIFO + data-ready
//
// Subtask #2: reads accel+gyro from MPU6886 FIFO at a configurable sample rate,
// wraps each sample with seq + device micros() timestamp, and pushes to a
// FreeRTOS queue so subtask #3 can feed a BLE task on the other core.
//
// Architecture reference: .project/architecture.md §1 (Firmware)
// BLE packet format:      docs/ble-protocol.md §2 (IMU Data)

#include <cstdint>
#include <cstddef>

// ── FreeRTOS queue handle (forward-declared to avoid pulling esp_timer.h here) ──
struct QueueDefinition;
using QueueHandle = QueueDefinition*;

namespace wheelsense {

// ── Constants (constexpr per ES.45 / ES.25) ──────────────────────────────────

// MPU6886 I2C address on M5StickCPlus2 internal bus (AD0 = 0)
constexpr uint8_t  MPU6886_ADDR = 0x68;

// FIFO sample size: 6 bytes accel + 6 bytes gyro = 12 bytes (big-endian int16)
constexpr size_t   FIFO_SAMPLE_BYTES = 12;

// FreeRTOS queue depth — enough for ~0.3 s at 200 Hz
constexpr size_t   SAMPLE_QUEUE_LEN = 64;

// Supported sample rates (Hz)
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

// ── ImuReader — singleton managing MPU6886 + FIFO + queue ────────────────────

class ImuReader {
public:
    // Initialize I2C, configure MPU6886 registers, create queue + esp_timer.
    // Must be called once after M5.begin().
    bool begin(uint16_t rate_hz = DEFAULT_SAMPLE_RATE_HZ,
               AccelRange ar   = AccelRange::G4,
               GyroRange  gr   = GyroRange::DPS2000);

    // Start / stop acquisition (timer on/off)
    void start();
    void stop();

    // Change sample rate (stops acquisition first)
    bool setRate(uint16_t rate_hz);

    // Change IMU ranges (stops acquisition first)
    void setRanges(AccelRange ar, GyroRange gr);

    // Pop one sample from the queue (non-blocking).
    // Returns false if queue is empty.
    bool popSample(ImuSample& out);

    // ── Accessors for display / Info characteristic ──
    uint16_t    rateHz()      const { return rate_hz_; }
    AccelRange  accelRange()  const { return accel_range_; }
    GyroRange   gyroRange()   const { return gyro_range_; }
    float       accelScale()  const;   // LSB → g
    float       gyroScale()   const;   // LSB → dps
    uint32_t    sampleCount() const { return sample_count_; }
    uint32_t    dropCount()   const { return drop_count_; }
    uint16_t    fifoDepth()   const { return last_fifo_depth_; }
    bool        running()     const { return running_; }

private:
    // MPU6886 register helpers
    void     writeReg(uint8_t reg, uint8_t val) const;
    uint8_t  readReg(uint8_t reg) const;
    void     readRegs(uint8_t reg, uint8_t* buf, size_t len) const;

    // Configure sensor registers for current rate + ranges + FIFO
    void     configureSensor() const;

    // Drain FIFO → push samples to queue (called by esp_timer callback)
    void     drainFifo();

    // esp_timer callback (static → forwards to instance)
    static void timerCallback(void* arg);

    // ── State ──
    uint16_t    rate_hz_       = DEFAULT_SAMPLE_RATE_HZ;
    AccelRange  accel_range_   = AccelRange::G4;
    GyroRange   gyro_range_    = GyroRange::DPS2000;
    bool        running_       = false;
    uint32_t    sample_count_  = 0;
    uint32_t    drop_count_    = 0;
    uint16_t    last_fifo_depth_ = 0;
    uint32_t    next_seq_      = 0;

    QueueHandle sample_queue_  = nullptr;
    void*       timer_handle_  = nullptr;   // esp_timer_handle_t
};

// Global singleton (embedded pattern: one IMU per device)
ImuReader& imu();

} // namespace wheelsense
