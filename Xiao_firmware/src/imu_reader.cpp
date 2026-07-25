// imu_reader.cpp - LSM6DS3 acquisition via FreeRTOS polling task.

#include "imu_reader.h"
#include "imu_types.h"

#include <Arduino.h>
#include <LSM6DS3.h>
#include <FreeRTOS.h>
#include <queue.h>
#include <task.h>

namespace WheelAthlete {

// Global IMU instance
static LSM6DS3 lsm_imu(I2C_MODE, 0x6A);

bool ImuReader::begin(uint16_t rate_hz, AccelRange ar, GyroRange gr) {
    if (!isValidRate(rate_hz)) {
        Serial.printf("[IMU] Invalid rate %u Hz (must be 50/100/200)\n", rate_hz);
        return false;
    }

    rate_hz_ = rate_hz;
    accel_range_ = ar;
    gyro_range_ = gr;

    sample_queue_ = xQueueCreate(SAMPLE_QUEUE_LEN, sizeof(ImuSample));
    if (!sample_queue_) {
        Serial.println("[IMU] Failed to allocate queue");
        return false;
    }

    if (!configureImu()) {
        Serial.println("[IMU] Failed to configure LSM6DS3");
        return false;
    }

    Serial.printf("[IMU] LSM6DS3 init OK - rate=%u Hz, accel=%u, gyro=%u\n",
                  rate_hz_, static_cast<unsigned>(accel_range_), static_cast<unsigned>(gyro_range_));
    return true;
}

void ImuReader::start() {
    if (running_ || !sample_queue_) {
        return;
    }

    if (!configureImu()) {
        Serial.println("[IMU] Cannot start: IMU configure failed");
        return;
    }

    xQueueReset(sample_queue_);
    next_seq_ = 0;
    sample_count_ = 0;
    drop_count_ = 0;

    running_ = true;

    // Create polling task on FreeRTOS
    BaseType_t ret = xTaskCreate(
        ImuReader::imuTaskThunk,
        "IMU_Task",
        1024, // 1024 words = 4KB stack
        this,
        3,    // priority 3
        reinterpret_cast<TaskHandle_t*>(&imu_task_)
    );

    if (ret != pdPASS) {
        running_ = false;
        Serial.println("[IMU] Failed to create polling task");
    } else {
        Serial.printf("[IMU] START polling task at rate=%u Hz\n", rate_hz_);
    }
}

void ImuReader::stop() {
    if (!running_) {
        return;
    }

    running_ = false;
    // Task deletes itself when running_ is false
    imu_task_ = nullptr;
    Serial.println("[IMU] STOP");
}

bool ImuReader::setRate(uint16_t rate_hz) {
    if (!isValidRate(rate_hz)) {
        Serial.printf("[IMU] Invalid rate %u Hz\n", rate_hz);
        return false;
    }
    if (rate_hz == rate_hz_) {
        return true;
    }

    const bool was_running = running_;
    stop();
    rate_hz_ = rate_hz;

    if (was_running) {
        start();
        return running_;
    }
    return true;
}

void ImuReader::setRanges(AccelRange ar, GyroRange gr) {
    const bool was_running = running_;
    stop();
    accel_range_ = ar;
    gyro_range_ = gr;
    if (was_running) {
        start();
    }
}

float ImuReader::accelScale() const {
    return WheelAthlete::accelScale(accel_range_);
}

float ImuReader::gyroScale() const {
    return WheelAthlete::gyroScale(gyro_range_);
}

bool ImuReader::popSample(ImuSample& out) {
    if (!sample_queue_) {
        return false;
    }
    return xQueueReceive(sample_queue_, &out, 0) == pdTRUE;
}

uint16_t ImuReader::queueDepth() const {
    return sample_queue_
        ? static_cast<uint16_t>(uxQueueMessagesWaiting(sample_queue_))
        : 0;
}

bool ImuReader::configureImu() {
    int a_range = 4;
    switch (accel_range_) {
        case AccelRange::G2:  a_range = 2; break;
        case AccelRange::G4:  a_range = 4; break;
        case AccelRange::G8:  a_range = 8; break;
        case AccelRange::G16: a_range = 16; break;
    }

    int g_range = 2000;
    switch (gyro_range_) {
        case GyroRange::DPS250:  g_range = 245; break;
        case GyroRange::DPS500:  g_range = 500; break;
        case GyroRange::DPS1000: g_range = 1000; break;
        case GyroRange::DPS2000: g_range = 2000; break;
    }

    int sample_rate = 104;
    switch (rate_hz_) {
        case 50:  sample_rate = 52; break;
        case 100: sample_rate = 104; break;
        case 200: sample_rate = 208; break;
    }

    lsm_imu.settings.accelRange = a_range;
    lsm_imu.settings.gyroRange = g_range;
    lsm_imu.settings.accelSampleRate = sample_rate;
    lsm_imu.settings.gyroSampleRate = sample_rate;

    return (lsm_imu.begin() == 0);
}

void ImuReader::imuTaskLoop() {
    TickType_t xLastWakeTime = xTaskGetTickCount();

    while (running_) {
        TickType_t xFrequency = pdMS_TO_TICKS(1000 / rate_hz_);
        vTaskDelayUntil(&xLastWakeTime, xFrequency);

        if (!running_) {
            break;
        }

        // Read raw data from registers
        int16_t ax = lsm_imu.readRawAccelX();
        int16_t ay = lsm_imu.readRawAccelY();
        int16_t az = lsm_imu.readRawAccelZ();
        int16_t gx = lsm_imu.readRawGyroX();
        int16_t gy = lsm_imu.readRawGyroY();
        int16_t gz = lsm_imu.readRawGyroZ();

        ImuSample s;
        s.seq = next_seq_++;
        s.t_device_us = micros();
        s.ax = ax;
        s.ay = ay;
        s.az = az;
        s.gx = gx;
        s.gy = gy;
        s.gz = gz;

        if (sample_queue_) {
            if (xQueueSend(sample_queue_, &s, 0) == pdTRUE) {
                sample_count_++;
            } else {
                drop_count_++;
            }
        }
    }

    vTaskDelete(NULL);
}

void ImuReader::resetQueueAndSeq() {
    if (sample_queue_) {
        xQueueReset(sample_queue_);
    }
    next_seq_ = 0;
    sample_count_ = 0;
    drop_count_ = 0;
}

void ImuReader::imuTaskThunk(void* arg) {
    static_cast<ImuReader*>(arg)->imuTaskLoop();
}

ImuReader& imu() {
    static ImuReader instance;
    return instance;
}

} // namespace WheelAthlete
