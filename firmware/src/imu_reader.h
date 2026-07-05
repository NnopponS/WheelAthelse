#pragma once
// imu_reader.h - MPU6886 acquisition via hardware FIFO + optional data-ready IRQ.
//
// The hardware-independent sample types and FIFO math live in imu_types.h.
// This class owns the ESP32/Arduino/M5Unified integration: sensor register
// setup, a FreeRTOS queue for BLE, and a small task that drains the MPU FIFO.

#include "imu_types.h"

struct QueueDefinition;
using QueueHandle = QueueDefinition*;

namespace WheelAthlete {

class ImuReader {
public:
    // Must be called once after M5.begin() and M5.Imu.init().
    bool begin(uint16_t rate_hz = DEFAULT_SAMPLE_RATE_HZ,
               AccelRange ar   = AccelRange::G4,
               GyroRange  gr   = GyroRange::DPS2000);

    void start();
    void stop();

    bool setRate(uint16_t rate_hz);
    void setRanges(AccelRange ar, GyroRange gr);

    bool popSample(ImuSample& out);

    uint16_t    rateHz()      const { return rate_hz_; }
    AccelRange  accelRange()  const { return accel_range_; }
    GyroRange   gyroRange()   const { return gyro_range_; }
    float       accelScale()  const;
    float       gyroScale()   const;
    uint32_t    sampleCount() const { return sample_count_; }
    uint32_t    dropCount()   const { return drop_count_; }
    uint32_t    fifoOverflowCount() const { return fifo_overflow_count_; }
    uint16_t    fifoDepth()   const { return last_fifo_depth_; }
    bool        running()     const { return running_; }

private:
    bool configureFifo();
    bool resetFifo();
    void disableFifo();
    void drainFifo();
    void pushSample(const uint8_t* raw_sample,
                    uint32_t drain_us,
                    uint16_t sample_count,
                    uint16_t sample_index);
    void handleFifoFault(uint16_t fifo_bytes);

    bool readRegister(uint8_t reg, uint8_t* data, size_t length) const;
    bool writeRegister(uint8_t reg, uint8_t value) const;
    bool readFifoCount(uint16_t& fifo_bytes) const;

    bool createFifoTask();
    void fifoTaskLoop();
    static void fifoTaskThunk(void* arg);
    void notifyFifoTask();
    void signalDataReadyFromIsr();
    static void irqThunk();

    uint16_t    rate_hz_       = DEFAULT_SAMPLE_RATE_HZ;
    AccelRange  accel_range_   = AccelRange::G4;
    GyroRange   gyro_range_    = GyroRange::DPS2000;
    bool        running_       = false;
    bool        fifo_configured_ = false;
    bool        interrupt_enabled_ = false;
    uint32_t    sample_count_  = 0;
    uint32_t    drop_count_    = 0;
    uint32_t    fifo_overflow_count_ = 0;
    uint16_t    last_fifo_depth_ = 0;
    uint32_t    last_fifo_fault_log_ms_ = 0;
    uint32_t    next_seq_      = 0;

    QueueHandle sample_queue_  = nullptr;
    void*       data_ready_sem_ = nullptr;  // SemaphoreHandle_t
    void*       fifo_task_      = nullptr;  // TaskHandle_t
};

ImuReader& imu();

} // namespace WheelAthlete
