// ble_service.cpp — BLE GATT server for WheelAthlete
//
// Implements docs/ble-protocol.md using NimBLE-Arduino.
// BLE task runs on Core 1 (separate from IMU acquisition on Core 0).

#include "ble_service.h"
#include "ble_types.h"
#include "imu_reader.h"
#include "display.h"

#include <Arduino.h>
#include <M5Unified.h>
#include <NimBLEDevice.h>
#include <freertos/queue.h>
#include <freertos/task.h>

namespace WheelAthlete {

// ── NimBLE characteristic callbacks ──────────────────────────────────────────

class ControlCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar) override {
        const size_t len = pChar->getValue().length();
        const uint8_t* data = reinterpret_cast<const uint8_t*>(pChar->getValue().data());
        BleService::onControlWrite(data, len);
    }
};

class InfoCallbacks : public NimBLECharacteristicCallbacks {
    void onRead(NimBLECharacteristic* /*pChar*/) override {
        // Info is updated dynamically — nothing to do here, value is set in begin()
    }
};

// ── Server callbacks (connect/disconnect/MTU) ────────────────────────────────

class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* /*server*/) override {
        BleService::onConnect();
    }
    void onDisconnect(NimBLEServer* /*server*/) override {
        BleService::onDisconnect();
    }
    void onMTUChange(uint16_t MTU, ble_gap_conn_desc* /*desc*/) override {
        BleService::onMtuExchange(MTU);
    }
};

// ── Static members for singleton access ──────────────────────────────────────

static NimBLEServer*       s_server       = nullptr;
static NimBLEService*       s_service      = nullptr;
static NimBLECharacteristic* s_char_imu    = nullptr;
static NimBLECharacteristic* s_char_control = nullptr;
static NimBLECharacteristic* s_char_sync    = nullptr;
static NimBLECharacteristic* s_char_info    = nullptr;
static NimBLECharacteristic* s_char_config  = nullptr;

// ── Battery Service (standard BLE 0x180F) ──
static NimBLEService*          s_batt_service  = nullptr;
static NimBLECharacteristic*   s_char_battery  = nullptr;

// ── BleService methods ───────────────────────────────────────────────────────

void BleService::begin(char wheel_id) {
    // Use config store values (loaded from NVS before begin)
    wheel_id_ = configStore().wheelChar();
    const char* device_name = configStore().name();

    // If config store has default name, build from wheel_id
    char default_name[24];
    if (strlen(device_name) == 0) {
        snprintf(default_name, sizeof(default_name), "WheelAthlete-%c", wheel_id_);
        device_name = default_name;
    }

    NimBLEDevice::init(device_name);
    NimBLEDevice::setMTU(247);   // request larger MTU for bigger batches

    s_server = NimBLEDevice::createServer();
    s_server->setCallbacks(new ServerCallbacks());

    s_service = s_server->createService(SERVICE_UUID);

    // IMU Data (Notify)
    s_char_imu = s_service->createCharacteristic(
        CHAR_IMU_DATA_UUID,
        NIMBLE_PROPERTY::NOTIFY
    );

    // Control (Write + Write Without Response)
    s_char_control = s_service->createCharacteristic(
        CHAR_CONTROL_UUID,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    s_char_control->setCallbacks(new ControlCallbacks());

    // Sync (Notify + Indicate)
    s_char_sync = s_service->createCharacteristic(
        CHAR_SYNC_UUID,
        NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::INDICATE
    );

    // Info (Read)
    s_char_info = s_service->createCharacteristic(
        CHAR_INFO_UUID,
        NIMBLE_PROPERTY::READ
    );
    s_char_info->setCallbacks(new InfoCallbacks());

    // Config (Read) — v1.1.0: board name/wheel/rate/fw version
    s_char_config = s_service->createCharacteristic(
        CHAR_CONFIG_UUID,
        NIMBLE_PROPERTY::READ
    );

    // Set initial Info + Config values
    updateInfoCharacteristic();
    updateConfigCharacteristic();

    s_service->start();

    // ── Standard Battery Service (0x180F) — second GATT service ──
    s_batt_service = s_server->createService(BATTERY_SERVICE_UUID);
    s_char_battery = s_batt_service->createCharacteristic(
        BATTERY_LEVEL_CHAR_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );
    // Set initial battery level (averaged + rounded to 5%, same as updateBatteryLevel)
    {
        int32_t mv_sum = 0;
        int sc = 0;
        for (int i = 0; i < 8; i++) {
            const int16_t mv = M5.Power.getBatteryVoltage();
            if (mv > 0) { mv_sum += mv; sc++; }
            delay(2);
        }
        if (sc > 0) {
            int level = ((mv_sum / sc) - 3200) * 100 / (4150 - 3200);
            if (level < 0) level = 0;
            if (level > 100) level = 100;
            level = ((level + 2) / 5) * 5;
            if (level > 100) level = 100;
            if (M5.Power.isCharging() && level >= 100) level = 99;
            battery_level_ = static_cast<uint8_t>(level);
        } else {
            battery_level_ = clampBatteryLevel(M5.Power.getBatteryLevel());
        }
    }
    s_char_battery->setValue(&battery_level_, BATTERY_LEVEL_SIZE);
    s_batt_service->start();

    // Start advertising — advertise both services
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(SERVICE_UUID);
    adv->addServiceUUID(BATTERY_SERVICE_UUID);
    adv->setScanResponse(true);
    adv->start();

    state_ = BleState::Advertising;
    Serial.printf("[BLE] Advertising as '%s'\n", device_name);
}

void BleService::updateInfoCharacteristic() {
    uint8_t info_buf[INFO_SIZE];
    packInfo(static_cast<uint8_t>(wheel_id_),
             WheelAthlete_FW_MAJOR, WheelAthlete_FW_MINOR, WheelAthlete_FW_PATCH,
             static_cast<uint8_t>(imu().accelRange()),
             static_cast<uint8_t>(imu().gyroRange()),
             imu().accelScale(), imu().gyroScale(),
             info_buf);
    s_char_info->setValue(info_buf, INFO_SIZE);
}

void BleService::updateConfigCharacteristic() {
    uint8_t config_buf[CONFIG_SIZE];
    packConfig(configStore().name(),
               configStore().wheelId(),
               configStore().rateHz(),
               WheelAthlete_FW_MAJOR, WheelAthlete_FW_MINOR, WheelAthlete_FW_PATCH,
               config_buf);
    if (s_char_config) {
        s_char_config->setValue(config_buf, CONFIG_SIZE);
    }
}

void BleService::updateAdvertisedName() {
    // Update the BLE device name after SET_NAME or SET_WHEEL
    NimBLEDevice::setDeviceName(configStore().name());
}

void BleService::updateBatteryLevel() {
    // Throttle: only update every ~10 seconds (longer interval reduces
    // noise from transient load spikes during BLE TX).
    const uint32_t now_ms = millis();
    if (now_ms - last_battery_ms_ < 10000 && last_battery_ms_ != 0) {
        return;
    }

    // Skip battery ADC reads while recording. The AXP192 ADC read sequence
    // (8 samples × 2 ms delay = 16 ms blocking) stalls the main loop and
    // can cause IMU queue buildup at high sample rates. Battery level is
    // only useful between sessions, not during active recording.
    if (imu().running()) return;

    last_battery_ms_ = now_ms;

    // Sample battery voltage multiple times and average to reduce ADC noise.
    // The AXP192 ADC has significant sample-to-sample jitter (±20-30 mV),
    // which maps to ±2-3% in the level calculation — enough to make the
    // reading bounce between e.g. 89% and 97%.
    const bool charging = (M5.Power.isCharging() != 0);
    int32_t mv_sum = 0;
    int sample_count = 0;
    for (int i = 0; i < 8; i++) {
        const int16_t mv = M5.Power.getBatteryVoltage();
        if (mv > 0) {
            mv_sum += mv;
            sample_count++;
        }
        delay(2); // small delay between ADC reads
    }

    uint8_t new_level;
    if (sample_count == 0) {
        // Voltage not available — fall back to getBatteryLevel().
        new_level = clampBatteryLevel(M5.Power.getBatteryLevel());
    } else {
        const int32_t avg_mv = mv_sum / sample_count;
        // Voltage-based mapping: 3200 mV = 0%, 4150 mV = 100%.
        int level = (avg_mv - 3200) * 100 / (4150 - 3200);
        if (level < 0) level = 0;
        if (level > 100) level = 100;
        // Round to nearest 5% to eliminate residual jitter. The AXP192
        // ADC doesn't have enough resolution to distinguish 1% steps
        // reliably, so rounding to 5% gives a stable display.
        level = ((level + 2) / 5) * 5;
        if (level > 100) level = 100;
        // When charging, cap at 99% so the user can tell it's not
        // actually full (the voltage is inflated by the charger).
        if (charging && level >= 100) level = 99;
        new_level = static_cast<uint8_t>(level);
    }

    // Deadband: only notify if the level changed by >= 5% (one rounded
    // step). This prevents spurious notifications from noise that
    // survives the averaging + rounding.
    const int8_t delta = (int8_t)new_level - (int8_t)battery_level_;
    if (delta >= 5 || delta <= -5) {
        battery_level_ = new_level;
        if (s_char_battery) {
            s_char_battery->setValue(&battery_level_, BATTERY_LEVEL_SIZE);
            s_char_battery->notify();
            Serial.printf("[BLE] Battery level: %u%% (avg_V=%dmV, charging=%d)\n",
                          battery_level_,
                          sample_count > 0 ? (int)(mv_sum / sample_count) : 0,
                          charging ? 1 : 0);
        }
    }
}

// ── Static callback forwarders ───────────────────────────────────────────────

void BleService::onConnect() {
    ble().state_ = BleState::Connected;
    Serial.println("[BLE] Central connected");
}

void BleService::onDisconnect() {
    ble().state_ = BleState::Advertising;
    // Stop acquisition if running
    if (imu().running()) {
        imu().stop();
    }
    ble().pending_start_ = false;
    // Persist config to NVS on disconnect (limit wear)
    configStore().save();
    // Apply the advertised name right before re-advertising so the new
    // name/wheel is visible in the next scan.
    ble().updateAdvertisedName();
    NimBLEDevice::startAdvertising();
    Serial.println("[BLE] Disconnected — resuming advertising");
}

void BleService::onMtuExchange(uint16_t mtu) {
    ble().mtu_ = mtu;
    Serial.printf("[BLE] MTU exchange: %u\n", mtu);
}

void BleService::onControlWrite(const uint8_t* data, size_t len) {
    uint8_t payload[32] = {};
    size_t payload_len = 0;
    const Cmd cmd = parseCommand(data, len, payload, payload_len);
    ble().handleCommand(cmd, payload, payload_len);
}

// ── Command handlers ─────────────────────────────────────────────────────────

void BleService::handleCommand(Cmd cmd, const uint8_t* payload, size_t len) {
    switch (cmd) {
        case Cmd::Start: {
            if (len >= 4) {
                uint32_t target_us;
                std::memcpy(&target_us, payload, 4);
                handleStart(target_us);
            } else {
                handleStart(0);  // immediate
            }
            break;
        }
        case Cmd::Stop:
            handleStop();
            break;
        case Cmd::SetRate: {
            if (len >= 2) {
                uint16_t rate_hz;
                std::memcpy(&rate_hz, payload, 2);
                handleSetRate(rate_hz);
            }
            break;
        }
        case Cmd::SyncPing: {
            if (len >= 4) {
                uint32_t t_app_ms;
                std::memcpy(&t_app_ms, payload, 4);
                handleSyncPing(t_app_ms);
            }
            break;
        }
        case Cmd::SetRange: {
            if (len >= 2) {
                handleSetRange(payload[0], payload[1]);
            }
            break;
        }
        case Cmd::Beep: {
            if (len >= 3) {
                uint16_t period_ms;
                std::memcpy(&period_ms, payload + 1, 2);
                handleBeep(payload[0], period_ms);
            }
            break;
        }
        case Cmd::SetName: {
            handleSetName(payload, len);
            break;
        }
        case Cmd::SetWheel: {
            if (len >= 1) {
                handleSetWheel(payload[0]);
            }
            break;
        }
        case Cmd::SetUtc: {
            if (len >= 8) {
                uint64_t utc_epoch;
                std::memcpy(&utc_epoch, payload, 8);
                handleSetUtc(utc_epoch);
            }
            break;
        }
        case Cmd::ResetSeq:
            handleResetSeq();
            break;
        default:
            sendCmdNack(static_cast<uint8_t>(cmd));
            Serial.printf("[BLE] Unknown cmd: 0x%02X\n", static_cast<uint8_t>(cmd));
            break;
    }
}

void BleService::handleStart(uint32_t target_start_us) {
    target_start_us_ = target_start_us;
    last_beep_fired_ = -1;

    if (target_start_us == 0) {
        // Immediate start
        imu().start();
        state_ = BleState::Recording;
        sendStartFired();
        Serial.println("[BLE] START (immediate)");
    } else {
        // Scheduled start — wait in tick()
        pending_start_ = true;
        state_ = BleState::Countdown;
        Serial.printf("[BLE] START scheduled at %u us\n", target_start_us);
    }
}

void BleService::handleStop() {
    display().clearCountdown();
    if (imu().running()) {
        imu().stop();
        flushBatch();   // send remaining samples
        sendStopFired();
    }
    pending_start_ = false;
    state_ = BleState::Connected;
    Serial.println("[BLE] STOP");
}

void BleService::handleSetRate(uint16_t rate_hz) {
    if (imu().setRate(rate_hz)) {
        configStore().setRate(rate_hz);   // cache in RAM, persist on disconnect
        updateInfoCharacteristic();
        updateConfigCharacteristic();
        Serial.printf("[BLE] SET_RATE: %u Hz\n", rate_hz);
    } else {
        sendCmdNack(static_cast<uint8_t>(Cmd::SetRate));
    }
}

void BleService::handleSyncPing(uint32_t t_app_ms) {
    // Capture device time IMMEDIATELY in the callback path (lowest latency)
    const uint32_t t_device_us = micros();
    ++sync_ping_count_;

    // Pack and send sync response
    uint8_t buf[SYNC_RESPONSE_SIZE];
    packSyncResponse(t_app_ms, t_device_us, sync_ping_count_, buf);

    // Prepend event_id for Sync characteristic
    uint8_t event_buf[1 + SYNC_RESPONSE_SIZE];
    packSyncEvent(SyncEvent::SyncResponse, buf, SYNC_RESPONSE_SIZE, event_buf);
    s_char_sync->setValue(event_buf, 1 + SYNC_RESPONSE_SIZE);
    s_char_sync->notify();
}

void BleService::handleSetRange(uint8_t accel_range, uint8_t gyro_range) {
    if (accel_range > 3 || gyro_range > 3) {
        sendCmdNack(static_cast<uint8_t>(Cmd::SetRange));
        return;
    }
    imu().setRanges(static_cast<AccelRange>(accel_range),
                    static_cast<GyroRange>(gyro_range));
    updateInfoCharacteristic();
    Serial.printf("[BLE] SET_RANGE: accel=%u, gyro=%u\n", accel_range, gyro_range);
}

void BleService::handleBeep(uint8_t count, uint16_t period_ms) {
    for (uint8_t i = 0; i < count; ++i) {
        doBeep(880, 150);
        delay(period_ms);
    }
}

void BleService::handleResetSeq() {
    // Reset seq by stopping and starting
    if (imu().running()) {
        imu().stop();
        imu().start();
    }
    Serial.println("[BLE] RESET_SEQ");
}

void BleService::handleSetName(const uint8_t* name_data, size_t len) {
    if (!name_data || len == 0) {
        sendCmdNack(static_cast<uint8_t>(Cmd::SetName));
        return;
    }
    // Build a null-terminated name from the payload (up to 16 bytes)
    char name_buf[NAME_MAX_LEN + 1] = {};
    size_t copy_len = len < NAME_MAX_LEN ? len : NAME_MAX_LEN;
    std::memcpy(name_buf, name_data, copy_len);
    name_buf[NAME_MAX_LEN] = '\0';

    configStore().setName(name_buf);
    updateConfigCharacteristic();
    // Note: advertised name is updated on disconnect (before re-advertising).
    // Calling updateAdvertisedName() here disrupts the BLE stack during an
    // active connection and causes subsequent writes to fail.
    Serial.printf("[BLE] SET_NAME: '%s'\n", configStore().name());
}

void BleService::handleSetWheel(uint8_t wheel_id) {
    if (!isValidWheel(wheel_id)) {
        sendCmdNack(static_cast<uint8_t>(Cmd::SetWheel));
        return;
    }
    configStore().setWheel(wheel_id);
    wheel_id_ = static_cast<char>(wheel_id);

    // If current name is the default name format (WheelAthlete-L or WheelAthlete-R),
    // update the name to match the new wheel ID.
    if (std::strcmp(configStore().name(), "WheelAthlete-L") == 0 ||
        std::strcmp(configStore().name(), "WheelAthlete-R") == 0) {
        if (wheel_id == 0x52) {
            configStore().setName("WheelAthlete-R");
        } else {
            configStore().setName("WheelAthlete-L");
        }
    }

    updateInfoCharacteristic();
    updateConfigCharacteristic();
    // Save to NVS
    configStore().save();
    // Note: advertised name is updated on disconnect (before re-advertising).
    Serial.printf("[BLE] SET_WHEEL: %c\n", wheel_id_);
}

void BleService::handleSetUtc(uint64_t utc_epoch_ms) {
    utc_epoch_ms_ = utc_epoch_ms;
    utc_set_ = true;
    // Emit UTC_SET echo event: [0x50][uint64 utc_epoch_ms]
    uint8_t buf[9];
    packUtcSet(utc_epoch_ms, buf);
    s_char_sync->setValue(buf, 9);
    s_char_sync->notify();
    Serial.printf("[BLE] SET_UTC: %llu ms\n",
                  static_cast<unsigned long long>(utc_epoch_ms));
}

// ── Event senders ────────────────────────────────────────────────────────────

void BleService::sendStartFired() {
    // Extended START_FIRED (v1.1.0): [0x30][uint32 t_device_us][uint64 utc_start_ms]
    const uint32_t now_us = micros();
    uint64_t utc_start_ms = 0;
    if (utc_set_ && pending_start_) {
        // utc_start_ms = utc_epoch + (target_start_us - now_us) / 1000
        // Keep the math in signed 64-bit until the final store so a slightly
        // late start (negative delta) does not wrap through an unsigned cast.
        const int64_t delta_us = static_cast<int64_t>(target_start_us_) -
                                 static_cast<int64_t>(now_us);
        const int64_t delta_ms = delta_us / 1000;
        const int64_t utc_start_ms_signed =
            static_cast<int64_t>(utc_epoch_ms_) + delta_ms;
        utc_start_ms = static_cast<uint64_t>(utc_start_ms_signed);
    } else if (utc_set_) {
        // Immediate start: UTC = epoch + (now - fire_time)/1000 ≈ epoch
        utc_start_ms = utc_epoch_ms_;
    }
    uint8_t buf[13];
    packStartFired(now_us, utc_start_ms, buf);
    s_char_sync->setValue(buf, 13);
    s_char_sync->notify();
}

void BleService::sendStopFired() {
    uint8_t buf[9];
    packStopFired(micros(), imu().sampleCount(), buf);
    s_char_sync->setValue(buf, 9);
    s_char_sync->notify();
}

void BleService::sendDropCountEvent() {
    const uint32_t new_drops = imu().dropCount() - last_drop_count_;
    if (new_drops > 0) {
        uint8_t buf[5];
        packDropCountEvent(new_drops, buf);
        s_char_sync->setValue(buf, 5);
        s_char_sync->notify();
        last_drop_count_ = imu().dropCount();
    }
}

void BleService::sendCmdNack(uint8_t cmd) {
    uint8_t buf[2];
    packCmdNack(cmd, buf);
    s_char_sync->setValue(buf, 2);
    s_char_sync->notify();
}

// ── Beep ─────────────────────────────────────────────────────────────────────

void BleService::doBeep(uint16_t freq_hz, uint16_t duration_ms) {
    // M5StickCPlus2 built-in buzzer via M5Unified Speaker
    M5.Speaker.setVolume(255);   // maximum volume (0-255)
    M5.Speaker.tone(freq_hz, duration_ms);
}

// ── Tick: called from main loop (Core 1) ─────────────────────────────────────

void BleService::tick() {
    // Handle countdown beeps + scheduled start
    if (pending_start_) {
        const uint32_t now = micros();

        // Calculate remaining seconds to display
        const int32_t remaining_ms = static_cast<int32_t>(target_start_us_ - now) / 1000;
        const int8_t seconds = static_cast<int8_t>((remaining_ms + 999) / 1000);
        if (seconds >= 0 && seconds <= 5) {
            display().showCountdown(seconds);
        }

        // Check for beep
        const int8_t beep_idx = checkBeepSchedule(target_start_us_, now, last_beep_fired_);
        if (beep_idx >= 0) {
            const BeepEvent& bp = BEEP_SCHEDULE[beep_idx];
            doBeep(bp.freq_hz, bp.duration_ms);
            last_beep_fired_ = beep_idx;
            Serial.printf("[BLE] Beep %d/4 (T%+ds)\n", beep_idx + 1,
                          bp.offset_us / 1000000);
        }

        // Check if it's time to start
        if (shouldStartNow(target_start_us_, now)) {
            display().clearCountdown(); // Clear countdown overlay
            imu().start();
            pending_start_ = false;
            state_ = BleState::Recording;
            sendStartFired();
            Serial.println("[BLE] Scheduled START fired");
        }
    }

    // Send DROP_COUNT event if new drops occurred
    if (imu().dropCount() > last_drop_count_) {
        sendDropCountEvent();
    }

    // Update battery level periodically (~5s) + notify on change
    updateBatteryLevel();
}

// ── BLE task: drain queue → batch → notify ──────────────────────────────────

void BleService::bleTask() {
    if (!connected() || !imu().running()) return;

    const uint8_t max_count = maxBatchCount(mtu_);
    if (max_count == 0) return;

    // Send exactly ONE batch per call and return. This keeps notify() from
    // blocking the Arduino loop for too long. A dedicated FreeRTOS task on
    // Core 1 calls this repeatedly, so the queue is drained at high frequency
    // without starving M5.update() / display / button handling.
    ImuSample samples[12];   // max 12 at MTU 247
    uint8_t count = 0;

    ImuSample s;
    while (count < max_count && imu().popSample(s)) {
        samples[count++] = s;
    }

    if (count == 0) return;

    const size_t batch_len = packBatch(samples, count, batch_buf_);
    s_char_imu->setValue(batch_buf_, batch_len);
    s_char_imu->notify();
    ++notify_count_;
}

void BleService::flushBatch() {
    // Send any remaining samples in the queue as a final batch
    bleTask();
    // Call again until queue is empty
    ImuSample s;
    while (imu().popSample(s)) {
        ImuSample single[1] = {s};
        const size_t len = packBatch(single, 1, batch_buf_);
        s_char_imu->setValue(batch_buf_, len);
        s_char_imu->notify();
        ++notify_count_;
    }
}

// ── Singleton ────────────────────────────────────────────────────────────────

BleService& ble() {
    static BleService instance;
    return instance;
}

} // namespace WheelAthlete
