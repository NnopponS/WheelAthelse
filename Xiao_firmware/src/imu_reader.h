#pragma once
// imu_reader.h - LSM6DS3 acquisition via high-precision polling task on FreeRTOS.

#include "imu_types.h"

using QueueHandle = void*;

namespace WheelAthlete {

class ImuReader {
public:
    bool begin(uint16_t rate_hz = DEFAULT_SAMPLE_RATE_HZ,
               AccelRange ar   = AccelRange::G4,
               GyroRange  gr   = GyroRange::DPS2000);

    void start();
    void stop();

    bool setRate(uint16_t rate_hz);
    void setRanges(AccelRange ar, GyroRange gr);

    bool popSample(ImuSample& out);
    void resetQueueAndSeq();

    uint16_t    rateHz()      const { return rate_hz_; }
    AccelRange  accelRange()  const { return accel_range_; }
    GyroRange   gyroRange()   const { return gyro_range_; }
    float       accelScale()  const;
    float       gyroScale()   const;
    uint32_t    sampleCount() const { return sample_count_; }
    uint32_t    queueDropCount() const { return drop_count_; }
    uint32_t    dropCount()   const { return drop_count_; }
    uint32_t    fifoOverflowCount() const { return 0; }
    uint32_t    fifoDroppedSampleCount() const { return 0; }
    uint16_t    fifoDepth()   const { return 0; }
    uint16_t    queueDepth()  const;
    bool        running()     const { return running_; }

private:
    bool configureImu();
    void imuTaskLoop();
    static void imuTaskThunk(void* arg);

    uint16_t    rate_hz_       = DEFAULT_SAMPLE_RATE_HZ;
    AccelRange  accel_range_   = AccelRange::G4;
    GyroRange   gyro_range_    = GyroRange::DPS2000;
    bool        running_       = false;
    uint32_t    sample_count_  = 0;
    uint32_t    drop_count_    = 0;
    uint32_t    next_seq_      = 0;

    QueueHandle sample_queue_  = nullptr;
    void*       imu_task_      = nullptr;  // TaskHandle_t
};

ImuReader& imu();

} // namespace WheelAthlete
