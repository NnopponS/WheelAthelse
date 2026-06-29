#pragma once
// imu_reader.h — MPU6886 IMU acquisition via hardware FIFO + esp_timer
//
// Subtask #2: reads accel+gyro from MPU6886 FIFO at a configurable sample rate,
// wraps each sample with seq + device micros() timestamp, and pushes to a
// FreeRTOS queue so subtask #3 can feed a BLE task on the other core.
//
// Pure types/constants/math live in imu_types.h (host-testable, no Arduino deps).
// This header contains the hardware-dependent ImuReader class.
//
// Architecture reference: .project/architecture.md §1 (Firmware)
// BLE packet format:      docs/ble-protocol.md §2 (IMU Data)

#include "imu_types.h"

// ── FreeRTOS queue handle (forward-declared to avoid pulling esp_timer.h here) ──
struct QueueDefinition;
using QueueHandle = QueueDefinition*;

namespace WheelAthlete {

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

    // Change sample rate (stops acquisition first).
    // Returns false if rate_hz is not 50/100/200.
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
    uint32_t    fifoOverflowCount() const { return fifo_overflow_count_; }
    uint16_t    fifoDepth()   const { return last_fifo_depth_; }
    bool        running()     const { return running_; }

private:
    // Acquire one sample from M5.Imu and push to queue (called by esp_timer)
    void     acquireSample();

    // esp_timer callback (static → forwards to instance)
    static void timerCallback(void* arg);

    // ── State ──
    uint16_t    rate_hz_       = DEFAULT_SAMPLE_RATE_HZ;
    AccelRange  accel_range_   = AccelRange::G4;
    GyroRange   gyro_range_    = GyroRange::DPS2000;
    bool        running_       = false;
    uint32_t    sample_count_  = 0;
    uint32_t    drop_count_    = 0;
    uint32_t    fifo_overflow_count_ = 0;
    uint16_t    last_fifo_depth_ = 0;
    uint32_t    next_seq_      = 0;

    QueueHandle sample_queue_  = nullptr;
    void*       timer_handle_  = nullptr;   // esp_timer_handle_t
};

// Global singleton (embedded pattern: one IMU per device)
ImuReader& imu();

} // namespace WheelAthlete
