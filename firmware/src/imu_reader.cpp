// imu_reader.cpp - MPU6886 acquisition via hardware FIFO + optional IRQ.
//
// Flow:
//   MPU6886 FIFO -> data-ready IRQ or FIFO fallback wake -> FreeRTOS queue
//
// If WheelAthlete_IMU_INT_PIN is defined to a valid GPIO, the FIFO task is
// woken by the sensor data-ready interrupt. M5StickC variants do not always
// expose that interrupt pin, so the default build uses the same FIFO path with
// a short timeout wake as a safe fallback. No I2C work is done in the ISR.

#include "imu_reader.h"

#include <Arduino.h>
#include <M5Unified.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

#ifndef WheelAthlete_IMU_INT_PIN
#define WheelAthlete_IMU_INT_PIN -1
#endif

namespace WheelAthlete {
namespace {

constexpr uint32_t I2C_FREQ_HZ = 400000;
constexpr uint32_t FIFO_TASK_STACK_BYTES = 4096;
constexpr UBaseType_t FIFO_TASK_PRIORITY = 3;
constexpr BaseType_t FIFO_TASK_CORE = 0;
constexpr uint32_t FIFO_FALLBACK_WAKE_MS = 5;
constexpr uint32_t FIFO_IRQ_SAFETY_WAKE_MS = 100;
constexpr uint32_t FIFO_RESET_DELAY_US = 100;
constexpr uint32_t FIFO_ALIGNMENT_SETTLE_US = 200;

constexpr uint8_t REG_SMPLRT_DIV = 0x19;
constexpr uint8_t REG_CONFIG = 0x1A;
constexpr uint8_t REG_GYRO_CONFIG = 0x1B;
constexpr uint8_t REG_ACCEL_CONFIG = 0x1C;
constexpr uint8_t REG_FIFO_EN = 0x23;
constexpr uint8_t REG_INT_PIN_CFG = 0x37;
constexpr uint8_t REG_INT_ENABLE = 0x38;
constexpr uint8_t REG_INT_STATUS = 0x3A;
constexpr uint8_t REG_USER_CTRL = 0x6A;
constexpr uint8_t REG_PWR_MGMT_1 = 0x6B;
constexpr uint8_t REG_PWR_MGMT_2 = 0x6C;
constexpr uint8_t REG_FIFO_COUNTH = 0x72;
constexpr uint8_t REG_FIFO_R_W = 0x74;

constexpr uint8_t CONFIG_DLPF_176HZ = 0x01;
constexpr uint8_t PWR_CLOCK_PLL_XGYRO = 0x01;
constexpr uint8_t USER_CTRL_FIFO_EN = 0x40;
constexpr uint8_t USER_CTRL_FIFO_RST = 0x04;
constexpr uint8_t FIFO_EN_ACCEL_TEMP_GYRO = 0xF8;
constexpr uint8_t INT_ENABLE_DATA_RDY = 0x01;
constexpr uint8_t INT_STATUS_FIFO_OFLOW = 0x10;
constexpr uint8_t INT_PIN_CFG_CLEAR_ON_ANY_READ = 0x10;

uint8_t rangeIndex(AccelRange range) {
    return static_cast<uint8_t>(range);
}

uint8_t rangeIndex(GyroRange range) {
    return static_cast<uint8_t>(range);
}

} // namespace

bool ImuReader::begin(uint16_t rate_hz, AccelRange ar, GyroRange gr) {
    if (!isValidRate(rate_hz)) {
        Serial.printf("[IMU] Invalid rate %u Hz (must be 50/100/200)\n", rate_hz);
        return false;
    }

    rate_hz_ = rate_hz;
    accel_range_ = ar;
    gyro_range_ = gr;

    sample_queue_ = xQueueCreate(SAMPLE_QUEUE_LEN, sizeof(ImuSample));
    data_ready_sem_ = xSemaphoreCreateBinary();
    if (!sample_queue_ || !data_ready_sem_) {
        Serial.println("[IMU] Failed to allocate queue/semaphore");
        return false;
    }

    if (!configureFifo()) {
        Serial.println("[IMU] Failed to configure MPU6886 FIFO");
        return false;
    }
    disableFifo();

    if (!createFifoTask()) {
        Serial.println("[IMU] Failed to create FIFO task");
        return false;
    }

#if WheelAthlete_IMU_INT_PIN >= 0
    pinMode(WheelAthlete_IMU_INT_PIN, INPUT);
    attachInterrupt(digitalPinToInterrupt(WheelAthlete_IMU_INT_PIN),
                    &ImuReader::irqThunk,
                    RISING);
    interrupt_enabled_ = true;
#else
    interrupt_enabled_ = false;
#endif

    Serial.printf("[IMU] MPU6886 FIFO init OK - rate=%u Hz, accel=+/%ug, gyro=+/%u dps, mode=%s\n",
                  rate_hz_,
                  2u << rangeIndex(accel_range_),
                  250u << rangeIndex(gyro_range_),
                  interrupt_enabled_ ? "irq+fifo" : "fifo-fallback");
    return true;
}

void ImuReader::start() {
    if (running_ || !sample_queue_ || !data_ready_sem_) {
        return;
    }

    if (!configureFifo()) {
        Serial.println("[IMU] Cannot start: FIFO configure failed");
        return;
    }

    xQueueReset(sample_queue_);
    next_seq_ = 0;
    sample_count_ = 0;
    drop_count_ = 0;
    fifo_overflow_count_ = 0;
    last_fifo_depth_ = 0;
    last_fifo_fault_log_ms_ = 0;

    running_ = true;
    notifyFifoTask();
    Serial.printf("[IMU] START fifo frame=%uB rate=%u Hz\n",
                  static_cast<unsigned>(FIFO_SAMPLE_BYTES),
                  rate_hz_);
}

void ImuReader::stop() {
    if (!running_) {
        return;
    }

    running_ = false;
    disableFifo();
    last_fifo_depth_ = 0;
    Serial.println("[IMU] STOP");
}

bool ImuReader::setRate(uint16_t rate_hz) {
    if (!isValidRate(rate_hz)) {
        Serial.printf("[IMU] Invalid rate %u Hz (must be 50/100/200)\n", rate_hz);
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

bool ImuReader::configureFifo() {
    if (!writeRegister(REG_PWR_MGMT_1, PWR_CLOCK_PLL_XGYRO)) {
        return false;
    }
    delay(10);

    const uint8_t sample_divisor = static_cast<uint8_t>(sampleRateDivisor(rate_hz_));
    const uint8_t accel_cfg = ACCEL_CONFIG_VAL[rangeIndex(accel_range_)];
    const uint8_t gyro_cfg = GYRO_CONFIG_VAL[rangeIndex(gyro_range_)];

    if (!writeRegister(REG_PWR_MGMT_2, 0x00) ||
        !writeRegister(REG_CONFIG, CONFIG_DLPF_176HZ) ||
        !writeRegister(REG_SMPLRT_DIV, sample_divisor) ||
        !writeRegister(REG_ACCEL_CONFIG, accel_cfg) ||
        !writeRegister(REG_GYRO_CONFIG, gyro_cfg) ||
        !writeRegister(REG_INT_PIN_CFG, INT_PIN_CFG_CLEAR_ON_ANY_READ) ||
        !writeRegister(REG_INT_ENABLE, INT_ENABLE_DATA_RDY)) {
        return false;
    }

    fifo_configured_ = resetFifo();
    return fifo_configured_;
}

bool ImuReader::resetFifo() {
    if (!writeRegister(REG_FIFO_EN, 0x00) ||
        !writeRegister(REG_USER_CTRL, USER_CTRL_FIFO_EN | USER_CTRL_FIFO_RST)) {
        return false;
    }

    delayMicroseconds(FIFO_RESET_DELAY_US);

    return writeRegister(REG_USER_CTRL, USER_CTRL_FIFO_EN) &&
           writeRegister(REG_FIFO_EN, FIFO_EN_ACCEL_TEMP_GYRO);
}

void ImuReader::disableFifo() {
    writeRegister(REG_FIFO_EN, 0x00);
    writeRegister(REG_INT_ENABLE, 0x00);
    writeRegister(REG_USER_CTRL, 0x00);
    fifo_configured_ = false;
}

void ImuReader::drainFifo() {
    if (!running_ || !fifo_configured_) {
        return;
    }

    uint8_t status = 0;
    if (readRegister(REG_INT_STATUS, &status, sizeof(status)) &&
        (status & INT_STATUS_FIFO_OFLOW) != 0) {
        uint16_t fifo_bytes = 0;
        readFifoCount(fifo_bytes);
        handleFifoFault(fifo_bytes);
        return;
    }

    uint16_t fifo_bytes = 0;
    if (!readFifoCount(fifo_bytes)) {
        return;
    }
    last_fifo_depth_ = fifo_bytes;

    if (fifo_bytes == 0) {
        return;
    }

    if (!fifoOverflowed(fifo_bytes) && fifoRemainderBytes(fifo_bytes) != 0) {
        delayMicroseconds(FIFO_ALIGNMENT_SETTLE_US);
        if (!readFifoCount(fifo_bytes)) {
            return;
        }
        last_fifo_depth_ = fifo_bytes;
    }

    if (fifoOverflowed(fifo_bytes) || fifoRemainderBytes(fifo_bytes) != 0) {
        handleFifoFault(fifo_bytes);
        return;
    }

    const uint16_t sample_count = fifoSampleCount(fifo_bytes);
    if (sample_count == 0) {
        return;
    }

    const uint32_t drain_us = micros();
    uint8_t raw[FIFO_SAMPLE_BYTES] = {};

    for (uint16_t i = 0; i < sample_count; ++i) {
        if (!readRegister(REG_FIFO_R_W, raw, sizeof(raw))) {
            handleFifoFault(fifo_bytes);
            return;
        }
        pushSample(raw, drain_us, sample_count, i);
    }
}

void ImuReader::pushSample(const uint8_t* raw_sample,
                           uint32_t drain_us,
                           uint16_t sample_count,
                           uint16_t sample_index) {
    ImuSample sample{};
    parseFifoSample(raw_sample, sample);
    sample.seq = next_seq_++;
    sample.t_device_us = interpolateTimestamp(drain_us, rate_hz_, sample_count, sample_index);

    if (xQueueSend(sample_queue_, &sample, 0) != pdTRUE) {
        ++drop_count_;
    } else {
        ++sample_count_;
    }
}

void ImuReader::handleFifoFault(uint16_t fifo_bytes) {
    ++fifo_overflow_count_;
    drop_count_ += estimatedDroppedSamplesFromFifoBytes(fifo_bytes);
    last_fifo_depth_ = fifo_bytes;
    const uint32_t now_ms = millis();
    if (fifo_overflow_count_ <= 5 || now_ms - last_fifo_fault_log_ms_ >= 1000) {
        Serial.printf("[IMU] FIFO fault bytes=%u remainder=%u drops=%lu faults=%lu\n",
                      fifo_bytes,
                      fifoRemainderBytes(fifo_bytes),
                      static_cast<unsigned long>(drop_count_),
                      static_cast<unsigned long>(fifo_overflow_count_));
        last_fifo_fault_log_ms_ = now_ms;
    }
    resetFifo();
}

bool ImuReader::readRegister(uint8_t reg, uint8_t* data, size_t length) const {
    return M5.In_I2C.readRegister(MPU6886_ADDR, reg, data, length, I2C_FREQ_HZ);
}

bool ImuReader::writeRegister(uint8_t reg, uint8_t value) const {
    return M5.In_I2C.writeRegister8(MPU6886_ADDR, reg, value, I2C_FREQ_HZ);
}

bool ImuReader::readFifoCount(uint16_t& fifo_bytes) const {
    uint8_t raw[2] = {};
    if (!readRegister(REG_FIFO_COUNTH, raw, sizeof(raw))) {
        return false;
    }
    fifo_bytes = static_cast<uint16_t>((static_cast<uint16_t>(raw[0]) << 8) | raw[1]);
    return true;
}

bool ImuReader::createFifoTask() {
    if (fifo_task_) {
        return true;
    }

    TaskHandle_t task_handle = nullptr;
    const BaseType_t result = xTaskCreatePinnedToCore(&ImuReader::fifoTaskThunk,
                                                      "WheelAthlete_fifo",
                                                      FIFO_TASK_STACK_BYTES,
                                                      this,
                                                      FIFO_TASK_PRIORITY,
                                                      &task_handle,
                                                      FIFO_TASK_CORE);
    if (result != pdPASS) {
        return false;
    }
    fifo_task_ = task_handle;
    return true;
}

void ImuReader::fifoTaskLoop() {
    auto* semaphore = static_cast<SemaphoreHandle_t>(data_ready_sem_);

    for (;;) {
        const TickType_t wait_ticks = pdMS_TO_TICKS(
            interrupt_enabled_ ? FIFO_IRQ_SAFETY_WAKE_MS : FIFO_FALLBACK_WAKE_MS);
        xSemaphoreTake(semaphore, wait_ticks);

        if (running_) {
            drainFifo();
        }
    }
}

void ImuReader::fifoTaskThunk(void* arg) {
    static_cast<ImuReader*>(arg)->fifoTaskLoop();
}

void ImuReader::notifyFifoTask() {
    auto* semaphore = static_cast<SemaphoreHandle_t>(data_ready_sem_);
    if (semaphore) {
        xSemaphoreGive(semaphore);
    }
}

void ImuReader::signalDataReadyFromIsr() {
    auto* semaphore = static_cast<SemaphoreHandle_t>(data_ready_sem_);
    if (!semaphore) {
        return;
    }

    BaseType_t higher_priority_task_woken = pdFALSE;
    xSemaphoreGiveFromISR(semaphore, &higher_priority_task_woken);
    if (higher_priority_task_woken == pdTRUE) {
        portYIELD_FROM_ISR();
    }
}

void IRAM_ATTR ImuReader::irqThunk() {
    imu().signalDataReadyFromIsr();
}

ImuReader& imu() {
    static ImuReader instance;
    return instance;
}

} // namespace WheelAthlete
