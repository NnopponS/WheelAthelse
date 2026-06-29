// imu_reader.cpp — MPU6886 IMU acquisition via M5Unified API + esp_timer
//
// Architecture (per .project/architecture.md §1):
//   [MPU6886] → M5.Imu.update() → esp_timer callback → FreeRTOS queue
//
// Implementation note:
//   On M5StickCPlus2 the MPU6886 is powered via the AXP192 PMIC, which must
//   be enabled by M5.begin() → M5.Imu.init() before any I2C traffic.  The
//   raw Wire transactions used in earlier revisions failed with "NULL TX
//   buffer pointer" because M5Unified manages the I2C bus internally and
//   the default Arduino Wire buffer is not allocated.
//
//   This revision uses the M5Unified high-level API:
//     M5.Imu.update()      — returns true when new data is available
//     M5.Imu.getImuData()  — returns float accel (g) + gyro (dps)
//
//   Float values are converted back to raw int16 using our scale factors so
//   the BLE packet format (20-byte ImuSample) is unchanged.  M5Unified's
//   MPU6886 defaults to ±4g / ±2000dps, matching our AccelRange::G4 and
//   GyroRange::DPS2000 defaults.

#include "imu_reader.h"
#include "imu_types.h"

#include <Arduino.h>
#include <M5Unified.h>
#include <esp_timer.h>
#include <freertos/queue.h>

namespace WheelAthlete {

// ── ImuReader methods ────────────────────────────────────────────────────────

bool ImuReader::begin(uint16_t rate_hz, AccelRange ar, GyroRange gr) {
    if (!isValidRate(rate_hz)) {
        Serial.printf("[IMU] Invalid rate %u Hz (must be 50/100/200)\n", rate_hz);
        return false;
    }
    rate_hz_     = rate_hz;
    accel_range_ = ar;
    gyro_range_  = gr;

    // M5.Imu.init() is called from main.cpp's setup() via M5.begin().
    // We don't call M5.Imu.update() here because it returns false until
    // the first sample is ready (which takes a few ms after init). The
    // timer callback handles false returns gracefully.

    // Create FreeRTOS queue
    sample_queue_ = xQueueCreate(SAMPLE_QUEUE_LEN, sizeof(ImuSample));
    if (!sample_queue_) return false;

    // Create esp_timer (periodic, fires at sample interval)
    esp_timer_create_args_t timer_args = {};
    timer_args.callback        = &ImuReader::timerCallback;
    timer_args.arg             = this;
    timer_args.dispatch_method = ESP_TIMER_TASK;
    timer_args.name            = "WheelAthlete_imu";

    const esp_err_t err = esp_timer_create(&timer_args,
                                           reinterpret_cast<esp_timer_handle_t*>(&timer_handle_));
    if (err != ESP_OK) return false;

    Serial.printf("[IMU] MPU6886 init OK — rate=%u Hz, accel=±%ug, gyro=±%u dps\n",
                  rate_hz_,
                  2u << static_cast<uint8_t>(accel_range_),
                  250u << static_cast<uint8_t>(gyro_range_));
    return true;
}

void ImuReader::start() {
    if (running_ || !timer_handle_) return;
    next_seq_      = 0;
    sample_count_  = 0;
    drop_count_    = 0;
    fifo_overflow_count_ = 0;
    last_fifo_depth_ = 0;

    const uint64_t period_us = 1000000ULL / rate_hz_;
    esp_timer_start_periodic(reinterpret_cast<esp_timer_handle_t>(timer_handle_), period_us);
    running_ = true;
}

void ImuReader::stop() {
    if (!running_ || !timer_handle_) return;
    esp_timer_stop(reinterpret_cast<esp_timer_handle_t>(timer_handle_));
    running_ = false;
}

bool ImuReader::setRate(uint16_t rate_hz) {
    if (!isValidRate(rate_hz)) {
        Serial.printf("[IMU] Invalid rate %u Hz (must be 50/100/200)\n", rate_hz);
        return false;
    }
    if (rate_hz == rate_hz_) return true;

    const bool was_running = running_;
    stop();
    rate_hz_ = rate_hz;
    if (was_running) start();
    return true;
}

void ImuReader::setRanges(AccelRange ar, GyroRange gr) {
    const bool was_running = running_;
    stop();
    accel_range_ = ar;
    gyro_range_  = gr;
    // Note: M5.Imu uses its own internal range settings.  We store our
    // configured ranges for the Info characteristic and scale conversion,
    // but the actual sensor range is managed by M5Unified.
    if (was_running) start();
}

float ImuReader::accelScale() const {
    return WheelAthlete::accelScale(accel_range_);
}

float ImuReader::gyroScale() const {
    return WheelAthlete::gyroScale(gyro_range_);
}

bool ImuReader::popSample(ImuSample& out) {
    if (!sample_queue_) return false;
    return xQueueReceive(sample_queue_, &out, 0) == pdTRUE;
}

void ImuReader::acquireSample() {
    // M5.Imu.update() returns true when new data is available.
    if (!M5.Imu.update()) {
        last_fifo_depth_ = 0;
        return;
    }

    const auto imu_data = M5.Imu.getImuData();

    // Convert float g/dps → raw int16 using our scale factors.
    // This keeps the BLE packet format (20-byte ImuSample with int16 fields)
    // unchanged so the Flutter parser and Info characteristic scales work
    // correctly.
    const float a_scale = WheelAthlete::accelScale(accel_range_);
    const float g_scale = WheelAthlete::gyroScale(gyro_range_);

    ImuSample sample{};
    sample.seq = next_seq_++;
    sample.t_device_us = micros();

    // Clamp to int16 range to avoid overflow on extreme values
    auto to_raw = [](float val, float scale) -> int16_t {
        float raw = val / scale;
        if (raw > 32767.0f) return 32767;
        if (raw < -32768.0f) return -32768;
        return static_cast<int16_t>(raw);
    };

    sample.ax = to_raw(imu_data.accel.x, a_scale);
    sample.ay = to_raw(imu_data.accel.y, a_scale);
    sample.az = to_raw(imu_data.accel.z, a_scale);
    sample.gx = to_raw(imu_data.gyro.x, g_scale);
    sample.gy = to_raw(imu_data.gyro.y, g_scale);
    sample.gz = to_raw(imu_data.gyro.z, g_scale);

    if (xQueueSend(sample_queue_, &sample, 0) != pdTRUE) {
        ++drop_count_;   // queue full — BLE hasn't drained fast enough
    } else {
        ++sample_count_;
    }
    last_fifo_depth_ = 1;
}

void ImuReader::timerCallback(void* arg) {
    static_cast<ImuReader*>(arg)->acquireSample();
}

// ── Singleton ────────────────────────────────────────────────────────────────
ImuReader& imu() {
    static ImuReader instance;
    return instance;
}

} // namespace WheelAthlete
