// imu_reader.cpp — MPU6886 IMU acquisition via hardware FIFO + data-ready
//
// Architecture (per .project/architecture.md §1):
//   [MPU6886] → data-ready INT → ISR (set flag) → drain FIFO → FreeRTOS queue
//
// Implementation note:
//   On M5StickCPlus2 the MPU6886 data-ready interrupt pin is not reliably
//   broken out to a GPIO across hardware revisions.  We therefore use an
//   esp_timer at the sample rate as the acquisition trigger and rely on the
//   MPU6886 hardware FIFO for data integrity.  The timer callback is short
//   (drains FIFO → queue) and runs on the esp_timer task (Core 0 by default),
//   keeping acquisition separate from the Arduino loop (Core 1) — matching the
//   dual-core intent of the architecture and leaving Core 1 free for BLE (#3).

#include "imu_reader.h"

#include <Arduino.h>
#include <Wire.h>
#include <esp_timer.h>
#include <freertos/queue.h>

namespace wheelsense {

// ── MPU6886 register addresses ───────────────────────────────────────────────
namespace reg {
constexpr uint8_t SMPLRT_DIV   = 0x19;
constexpr uint8_t CONFIG        = 0x1A;   // DLPF config
constexpr uint8_t GYRO_CONFIG   = 0x1B;
constexpr uint8_t ACCEL_CONFIG  = 0x1C;
constexpr uint8_t FIFO_EN       = 0x23;
constexpr uint8_t INT_PIN_CFG   = 0x37;
constexpr uint8_t INT_ENABLE    = 0x38;
constexpr uint8_t INT_STATUS    = 0x3A;
constexpr uint8_t USER_CTRL     = 0x6A;   // bit FIFO_EN=0x40, FIFO_RST=0x04
constexpr uint8_t PWR_MGMT_1    = 0x6B;
constexpr uint8_t PWR_MGMT_2    = 0x6C;
constexpr uint8_t FIFO_COUNTH   = 0x72;
constexpr uint8_t FIFO_R_W      = 0x74;
} // namespace reg

// ── Scale tables (constexpr, ES.45) ──────────────────────────────────────────
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

// ── ImuReader methods ────────────────────────────────────────────────────────

void ImuReader::writeReg(uint8_t r, uint8_t v) const {
    Wire.beginTransmission(MPU6886_ADDR);
    Wire.write(r);
    Wire.write(v);
    Wire.endTransmission(true);
}

uint8_t ImuReader::readReg(uint8_t r) const {
    Wire.beginTransmission(MPU6886_ADDR);
    Wire.write(r);
    Wire.endTransmission(false);
    Wire.requestFrom(MPU6886_ADDR, 1u, true);
    return static_cast<uint8_t>(Wire.read());
}

void ImuReader::readRegs(uint8_t r, uint8_t* buf, size_t len) const {
    Wire.beginTransmission(MPU6886_ADDR);
    Wire.write(r);
    Wire.endTransmission(false);
    Wire.requestFrom(MPU6886_ADDR, len, true);
    for (size_t i = 0; i < len && Wire.available(); ++i)
        buf[i] = static_cast<uint8_t>(Wire.read());
}

void ImuReader::configureSensor() const {
    // 1. Wake up: auto-select best clock (PLL), disable sleep
    writeReg(reg::PWR_MGMT_1, 0x01);
    delay(10);

    // 2. DLPF: CONFIG = 0x03 → bandwidth ~44 Hz, internal sample rate = 1 kHz
    //    (needed for SMPLRT_DIV to produce accurate output rates)
    writeReg(reg::CONFIG, 0x03);

    // 3. Sample rate divider: rate = 1000 / (1 + SMPLRT_DIV)
    const uint16_t div = static_cast<uint16_t>(1000u / rate_hz_ - 1u);
    writeReg(reg::SMPLRT_DIV, static_cast<uint8_t>(div));

    // 4. Accel + gyro ranges
    writeReg(reg::ACCEL_CONFIG, ACCEL_CONFIG_VAL[static_cast<size_t>(accel_range_)]);
    writeReg(reg::GYRO_CONFIG,  GYRO_CONFIG_VAL[static_cast<size_t>(gyro_range_)]);

    // 5. Disable all interrupts (we use esp_timer; INT pin not wired reliably)
    writeReg(reg::INT_ENABLE, 0x00);
    writeReg(reg::INT_PIN_CFG, 0x00);

    // 6. FIFO: reset then enable accel+gyro
    writeReg(reg::USER_CTRL, 0x04);    // FIFO_RST
    delay(2);
    writeReg(reg::USER_CTRL, 0x40);    // FIFO_EN bit
    writeReg(reg::FIFO_EN, 0x78);      // accel xyz + gyro xyz → FIFO
}

bool ImuReader::begin(uint16_t rate_hz, AccelRange ar, GyroRange gr) {
    rate_hz_     = constrain(rate_hz, MIN_SAMPLE_RATE_HZ, MAX_SAMPLE_RATE_HZ);
    accel_range_ = ar;
    gyro_range_  = gr;

    // Verify MPU6886 is present (read WHO_AM_I = 0x70)
    const uint8_t whoami = readReg(0x75);
    if (whoami != 0x70) {
        Serial.printf("[IMU] WHO_AM_I=0x%02X (expected 0x70) — MPU6886 not found\n", whoami);
        return false;
    }

    configureSensor();

    // Create FreeRTOS queue
    sample_queue_ = xQueueCreate(SAMPLE_QUEUE_LEN, sizeof(ImuSample));
    if (!sample_queue_) return false;

    // Create esp_timer (periodic, fires at sample interval)
    esp_timer_create_args_t timer_args = {};
    timer_args.callback        = &ImuReader::timerCallback;
    timer_args.arg             = this;
    timer_args.dispatch_method = ESP_TIMER_TASK;
    timer_args.name            = "wheelsense_imu";

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
    // Reset FIFO + seq before starting
    writeReg(reg::USER_CTRL, 0x04);
    delay(2);
    writeReg(reg::USER_CTRL, 0x40);
    next_seq_      = 0;
    sample_count_  = 0;
    drop_count_    = 0;
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
    const uint16_t new_rate = constrain(rate_hz, MIN_SAMPLE_RATE_HZ, MAX_SAMPLE_RATE_HZ);
    if (new_rate == rate_hz_) return true;

    const bool was_running = running_;
    stop();
    rate_hz_ = new_rate;
    configureSensor();
    if (was_running) start();
    return true;
}

void ImuReader::setRanges(AccelRange ar, GyroRange gr) {
    const bool was_running = running_;
    stop();
    accel_range_ = ar;
    gyro_range_  = gr;
    configureSensor();
    if (was_running) start();
}

float ImuReader::accelScale() const {
    return ACCEL_SCALE_TABLE[static_cast<size_t>(accel_range_)];
}

float ImuReader::gyroScale() const {
    return GYRO_SCALE_TABLE[static_cast<size_t>(gyro_range_)];
}

bool ImuReader::popSample(ImuSample& out) {
    if (!sample_queue_) return false;
    return xQueueReceive(sample_queue_, &out, 0) == pdTRUE;
}

void ImuReader::drainFifo() {
    // Read FIFO count (big-endian uint16)
    uint8_t count_buf[2];
    readRegs(reg::FIFO_COUNTH, count_buf, 2);
    const uint16_t fifo_bytes = (static_cast<uint16_t>(count_buf[0]) << 8) | count_buf[1];
    const uint16_t n_samples  = fifo_bytes / FIFO_SAMPLE_BYTES;

    last_fifo_depth_ = n_samples;

    if (n_samples == 0) return;

    // Read all FIFO data in one burst
    // (FIFO_R_W returns all bytes; reading count*12 bytes drains exactly that)
    const size_t read_len = static_cast<size_t>(n_samples) * FIFO_SAMPLE_BYTES;

    // ESP32 Wire buffer default is 128 bytes; for larger reads use chunks
    // FIFO_SAMPLE_BYTES=12, so max ~42 samples = 504 bytes → read in chunks of 10 samples
    constexpr size_t CHUNK_SAMPLES = 10;
    constexpr size_t CHUNK_BYTES   = CHUNK_SAMPLES * FIFO_SAMPLE_BYTES;

    uint8_t chunk[CHUNK_BYTES];

    size_t remaining = read_len;
    while (remaining > 0) {
        const size_t this_chunk = (remaining > CHUNK_BYTES) ? CHUNK_BYTES : remaining;
        const size_t this_n     = this_chunk / FIFO_SAMPLE_BYTES;

        readRegs(reg::FIFO_R_W, chunk, this_chunk);

        for (size_t s = 0; s < this_n; ++s) {
            const uint8_t* p = chunk + s * FIFO_SAMPLE_BYTES;

            // MPU6886 FIFO data is big-endian int16
            ImuSample sample{};
            sample.seq           = next_seq_++;
            sample.t_device_us   = micros();
            sample.ax = static_cast<int16_t>((p[0]  << 8) | p[1]);
            sample.ay = static_cast<int16_t>((p[2]  << 8) | p[3]);
            sample.az = static_cast<int16_t>((p[4]  << 8) | p[5]);
            sample.gx = static_cast<int16_t>((p[6]  << 8) | p[7]);
            sample.gy = static_cast<int16_t>((p[8]  << 8) | p[9]);
            sample.gz = static_cast<int16_t>((p[10] << 8) | p[11]);

            if (xQueueSend(sample_queue_, &sample, 0) != pdTRUE) {
                ++drop_count_;   // queue full — BLE hasn't drained fast enough
            } else {
                ++sample_count_;
            }
        }
        remaining -= this_chunk;
    }
}

void ImuReader::timerCallback(void* arg) {
    static_cast<ImuReader*>(arg)->drainFifo();
}

// ── Singleton ────────────────────────────────────────────────────────────────
ImuReader& imu() {
    static ImuReader instance;
    return instance;
}

} // namespace wheelsense
