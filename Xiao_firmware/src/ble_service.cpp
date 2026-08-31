// ble_service.cpp — BLE GATT server for WheelAthlete using Adafruit Bluefruit nRF52

#include "ble_service.h"
#include "ble_types.h"
#include "imu_reader.h"
#include "config_store.h"

#include <Arduino.h>
#include <bluefruit.h>

namespace WheelAthlete {

// BLE connection intervals use 1.25 ms units; 8 requests 10 ms.
static constexpr uint16_t PREFERRED_CONN_INTERVAL_UNITS = 8;
static constexpr uint16_t SUPERVISION_TIMEOUT_UNITS = 400; // 4 seconds

// Global BLE Characteristic/Service instances
static BLEService        s_service(SERVICE_UUID);
static BLECharacteristic s_char_imu(CHAR_IMU_DATA_UUID);
static BLECharacteristic s_char_control(CHAR_CONTROL_UUID);
static BLECharacteristic s_char_sync(CHAR_SYNC_UUID);
static BLECharacteristic s_char_info(CHAR_INFO_UUID);
static BLECharacteristic s_char_config(CHAR_CONFIG_UUID);
static BLEBas            s_blebas;

// ── C-style callback functions for Adafruit Bluefruit ──
static void connect_callback(uint16_t conn_handle) {
    ble().onConnect(conn_handle);
}

static void disconnect_callback(uint16_t conn_handle, uint8_t reason) {
    ble().onDisconnect(conn_handle, reason);
}

static void control_write_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len) {
    (void)conn_hdl;
    (void)chr;
    if (len == 0) return;

    uint8_t payload[32] = {};
    size_t payload_len = 0;
    const Cmd cmd = parseCommand(data, len, payload, payload_len);
    ble().handleCommand(cmd, payload, payload_len);
}

// ── VBAT Reading helpers ──
static float readVBAT_V() {
    analogReadResolution(12);
#if defined(AR_INTERNAL_3_0)
    analogReference(AR_INTERNAL_3_0);   // 3.0V reference
#endif
#ifdef PIN_VBAT_ENABLE
    pinMode(PIN_VBAT_ENABLE, OUTPUT);
    digitalWrite(PIN_VBAT_ENABLE, HIGH);
    delay(2);
#endif
#ifdef PIN_VBAT
    int raw = analogRead(PIN_VBAT);
#else
    int raw = analogRead(A7);
#endif
#ifdef PIN_VBAT_ENABLE
    digitalWrite(PIN_VBAT_ENABLE, LOW);
#endif
    float v_pin = raw * (3.0f / 4095.0f);
    float vbat  = v_pin * 2.0f;            // divider 2:1
    return vbat;
}

static float lipoPercentFromVoltage(float v) {
    const float vt[] = {3.30f, 3.50f, 3.70f, 3.85f, 4.00f, 4.10f, 4.20f};
    const float pt[] = {   0.f,  10.f,  30.f,  55.f,  80.f,  90.f, 100.f};
    const int   n = sizeof(vt)/sizeof(vt[0]);
    if (v <= vt[0]) return 0.f;
    if (v >= vt[n-1]) return 100.f;
    for (int i=0;i<n-1;i++) {
        if (v >= vt[i] && v <= vt[i+1]) {
            float t = (v - vt[i]) / (vt[i+1] - vt[i]);
            return pt[i] + t * (pt[i+1] - pt[i]);
        }
    }
    return 0.f;
}

// ── BleService methods ──

void BleService::begin(char wheel_id) {
    wheel_id_ = configStore().wheelChar();
    char legacy_name[24];
    snprintf(legacy_name, sizeof(legacy_name), "WheelAthlete-%c", wheel_id_);
    if (strlen(configStore().name()) == 0 || strcmp(configStore().name(), legacy_name) == 0) {
        char model_name[24];
        snprintf(model_name, sizeof(model_name), "WheelAthlete-XIAO-%c", wheel_id_);
        configStore().setName(model_name);
        configStore().save();
    }
    const char* device_name = configStore().name();

    char default_name[24];
    if (strlen(device_name) == 0) {
        snprintf(default_name, sizeof(default_name), "WheelAthlete-%c", wheel_id_);
        device_name = default_name;
    }

    // Configure max MTU, SoftDevice event length, HVN queue, and write queue.
    // The second argument is not a connection interval.
    Bluefruit.configPrphConn(247, 10, 10, 10);
    Bluefruit.begin();

#if defined(NRF52840_XXAA)
    Bluefruit.setTxPower(8); // +8 dBm on nRF52840
#else
    Bluefruit.setTxPower(4);
#endif

    Bluefruit.setName(device_name);

    Bluefruit.Periph.setConnectCallback(connect_callback);
    Bluefruit.Periph.setDisconnectCallback(disconnect_callback);

    s_service.begin();

    // IMU Data (Notify)
    s_char_imu.setProperties(CHR_PROPS_NOTIFY);
    s_char_imu.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
    s_char_imu.setMaxLen(MAX_BATCH_BUF);
    s_char_imu.begin();

    // Control (Write + Write Without Response)
    s_char_control.setProperties(CHR_PROPS_WRITE | CHR_PROPS_WRITE_WO_RESP);
    s_char_control.setPermission(SECMODE_NO_ACCESS, SECMODE_OPEN);
    s_char_control.setMaxLen(32);
    s_char_control.setWriteCallback(control_write_callback);
    s_char_control.begin();

    // Sync (Notify)
    s_char_sync.setProperties(CHR_PROPS_NOTIFY);
    s_char_sync.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
    s_char_sync.setMaxLen(1 + SYNC_RESPONSE_SIZE);
    s_char_sync.begin();

    // Info (Read)
    s_char_info.setProperties(CHR_PROPS_READ);
    s_char_info.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
    s_char_info.setMaxLen(INFO_SIZE);
    s_char_info.begin();

    // Config (Read)
    s_char_config.setProperties(CHR_PROPS_READ);
    s_char_config.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
    s_char_config.setMaxLen(CONFIG_SIZE);
    s_char_config.begin();

    updateInfoCharacteristic();
    updateConfigCharacteristic();

    s_blebas.begin();
    updateBatteryLevel();

    Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
    Bluefruit.Advertising.addTxPower();
    Bluefruit.Advertising.addService(s_service);
    Bluefruit.Advertising.addService(s_blebas);
    Bluefruit.ScanResponse.addName();

    Bluefruit.Advertising.restartOnDisconnect(true);
    Bluefruit.Advertising.setInterval(320, 320); // 200 ms
    Bluefruit.Advertising.start(0);

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
    info_buf[14] = 2;  // protocol 1.2 hardware model: Xiao BLE Sense
    info_buf[15] = 0x01;  // protocol 1.3 sample replay capability
    s_char_info.write(info_buf, INFO_SIZE);
}

void BleService::updateConfigCharacteristic() {
    uint8_t config_buf[CONFIG_SIZE];
    packConfig(configStore().name(),
               configStore().wheelId(),
               configStore().rateHz(),
               WheelAthlete_FW_MAJOR, WheelAthlete_FW_MINOR, WheelAthlete_FW_PATCH,
               configStore().beepEnabled(),
               config_buf);
    s_char_config.write(config_buf, CONFIG_SIZE);
}

void BleService::updateAdvertisedName() {
    Bluefruit.setName(configStore().name());
}

void BleService::updateBatteryLevel() {
    const uint32_t now_ms = millis();
    if (now_ms - last_battery_ms_ < 10000 && last_battery_ms_ != 0) {
        return;
    }

    // ADC averaging contains blocking delays. Never run it while the IMU is
    // acquiring; STOP resets the timer and publishes a fresh idle value.
    if (imu().running()) return;

    last_battery_ms_ = now_ms;

    float voltage_sum = 0.0f;
    for (uint8_t i = 0; i < 5; ++i) {
        voltage_sum += readVBAT_V();
        delay(2);
    }
    const float p = lipoPercentFromVoltage(voltage_sum / 5.0f);
    filtered_battery_ = filtered_battery_ < 0.0f
        ? p
        : (0.2f * p + 0.8f * filtered_battery_);

    uint8_t new_level = (uint8_t)roundf(filtered_battery_);
    if (new_level > 100) new_level = 100;

    const int delta = static_cast<int>(new_level) - static_cast<int>(battery_level_);
    if (battery_level_ == 0 || delta >= 2 || delta <= -2) {
        battery_level_ = new_level;
        s_blebas.write(battery_level_);
    }
}

void BleService::onConnect(uint16_t conn_handle) {
    conn_handle_ = conn_handle;
    connected_at_ms_ = millis();
    link_reported_ = false;
    state_ = BleState::Connected;
    last_battery_ms_ = 0;
    updateBatteryLevel();
    if (imu().running()) imu().stop();
    imu().resetQueueAndSeq();
    restoreLeds();
    BLEConnection* conn = Bluefruit.Connection(conn_handle_);
    const bool mtu_requested = conn && conn->requestMtuExchange(247);
    const bool interval_requested = conn && conn->requestConnectionParameter(
        PREFERRED_CONN_INTERVAL_UNITS, 0, SUPERVISION_TIMEOUT_UNITS);
    Serial.printf("[BLE] Central connected; MTU request=%s, 10 ms interval request=%s\n",
                  mtu_requested ? "ok" : "failed",
                  interval_requested ? "ok" : "failed");
}

void BleService::onDisconnect(uint16_t conn_handle, uint8_t reason) {
    (void)conn_handle;
    (void)reason;
    state_ = BleState::Advertising;
    conn_handle_ = 0xFFFF;
    link_reported_ = false;
    pending_start_ = false;
    stop_finalization_pending_ = false;
    stop_empty_since_ms_ = 0;
    consecutive_transport_failures_ = 0;
    retry_after_ms_ = 0;
    if (imu().running()) imu().stop();
    configStore().save();
    updateAdvertisedName();
    restoreLeds();
    Serial.println("[BLE] Disconnected — resuming advertising");
}

void BleService::handleCommand(Cmd cmd, const uint8_t* payload, size_t len) {
    switch (cmd) {
        case Cmd::Start: {
            if (len >= 4) {
                uint32_t target_us;
                std::memcpy(&target_us, payload, 4);
                handleStart(target_us);
            } else {
                handleStart(0);
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
        case Cmd::ReplayRange: {
            if (len != 6) { sendCmdNack(static_cast<uint8_t>(cmd)); break; }
            uint32_t start_seq;
            uint16_t count;
            std::memcpy(&start_seq, payload, 4);
            std::memcpy(&count, payload + 4, 2);
            handleReplayRange(start_seq, count);
            break;
        }
        case Cmd::SetBeepEnabled:
            if (len != 1 || payload[0] > 1) {
                sendCmdNack(static_cast<uint8_t>(cmd));
            } else {
                handleSetBeepEnabled(payload[0] == 1);
            }
            break;
        default:
            sendCmdNack(static_cast<uint8_t>(cmd));
            Serial.printf("[BLE] Unknown cmd: 0x%02X\n", static_cast<uint8_t>(cmd));
            break;
    }
}

void BleService::handleStart(uint32_t target_start_us) {
    replay_head_ = replay_count_ = 0;
    pending_count_ = 0;
    replay_pending_ = false;
    notified_samples_ = 0;
    transport_failures_ = 0;
    consecutive_transport_failures_ = 0;
    retry_after_ms_ = 0;
    last_drop_count_ = 0;
    last_health_ms_ = 0;
    stop_finalization_pending_ = false;
    stop_empty_since_ms_ = 0;
    imu().resetQueueAndSeq();
    target_start_us_ = target_start_us;
    last_blink_fired_ = -1;
    if (target_start_us == 0) {
        imu().start();
        state_ = BleState::Recording;
        sendStartFired();
        Serial.println("[BLE] START immediate");
    } else {
        pending_start_ = true;
        state_ = BleState::Countdown;
        Serial.printf("[BLE] START scheduled at %lu us\n", static_cast<unsigned long>(target_start_us));
    }
}

void BleService::handleStop() {
    pending_start_ = false;
    if (imu().running()) {
        imu().stop();
    }
    stop_device_us_ = micros();
    state_ = BleState::Connected;
    stop_finalization_pending_ = true;
    stop_empty_since_ms_ = 0;
    flushBatch();
    last_battery_ms_ = 0;
    updateBatteryLevel();
    Serial.println("[BLE] STOP - idle");
}

void BleService::handleReplayRange(uint32_t start_seq, uint16_t count) {
    if (count == 0 || count > 128 || replay_pending_) {
        sendCmdNack(static_cast<uint8_t>(Cmd::ReplayRange));
        return;
    }
    replay_start_seq_ = start_seq;
    replay_requested_ = count;
    replay_sent_ = 0;
    replay_turn_ = true;
    replay_pending_ = true;
}

void BleService::handleSetRate(uint16_t rate_hz) {
    if (imu().setRate(rate_hz)) {
        configStore().setRate(rate_hz);
        updateInfoCharacteristic();
        updateConfigCharacteristic();
        Serial.printf("[BLE] SET_RATE: %u Hz\n", rate_hz);
    } else {
        sendCmdNack(static_cast<uint8_t>(Cmd::SetRate));
    }
}

void BleService::handleSyncPing(uint32_t t_app_ms) {
    const uint32_t t_device_us = micros();
    ++sync_ping_count_;

    uint8_t buf[SYNC_RESPONSE_SIZE];
    packSyncResponse(t_app_ms, t_device_us, sync_ping_count_, buf);

    uint8_t event_buf[1 + SYNC_RESPONSE_SIZE];
    packSyncEvent(SyncEvent::SyncResponse, buf, SYNC_RESPONSE_SIZE, event_buf);
    s_char_sync.notify(event_buf, 1 + SYNC_RESPONSE_SIZE);
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
    // Beep maps to Red/Blue LED flash
    for (uint8_t i = 0; i < count; ++i) {
        active_blink_led_ = 2; // both
        blink_until_ms_ = millis() + 150;
        digitalWrite(LED_RED, LOW);
        digitalWrite(LED_BLUE, LOW);
        delay(period_ms);
    }
}

void BleService::handleSetBeepEnabled(bool enabled) {
    configStore().setBeepEnabled(enabled);
    configStore().save();
    updateConfigCharacteristic();
    Serial.printf("[BLE] SET_BEEP_ENABLED: %s\n", enabled ? "on" : "off");
}

void BleService::handleSetName(const uint8_t* name_data, size_t len) {
    if (!name_data || len == 0) {
        sendCmdNack(static_cast<uint8_t>(Cmd::SetName));
        return;
    }
    char name_buf[NAME_MAX_LEN + 1] = {};
    size_t copy_len = len < NAME_MAX_LEN ? len : NAME_MAX_LEN;
    std::memcpy(name_buf, name_data, copy_len);
    name_buf[NAME_MAX_LEN] = '\0';

    configStore().setName(name_buf);
    updateConfigCharacteristic();
    configStore().save();
    Serial.printf("[BLE] SET_NAME: '%s'\n", configStore().name());
}

void BleService::handleSetWheel(uint8_t wheel_id) {
    if (!isValidWheel(wheel_id)) {
        sendCmdNack(static_cast<uint8_t>(Cmd::SetWheel));
        return;
    }
    configStore().setWheel(wheel_id);
    wheel_id_ = static_cast<char>(wheel_id);

    if (std::strncmp(configStore().name(), "WheelAthlete-XIAO-", 18) == 0) {
        if (wheel_id == 0x52) {
            configStore().setName("WheelAthlete-XIAO-R");
        } else {
            configStore().setName("WheelAthlete-XIAO-L");
        }
    }

    updateInfoCharacteristic();
    updateConfigCharacteristic();
    configStore().save();
    Serial.printf("[BLE] SET_WHEEL: %c\n", wheel_id_);
}

void BleService::handleSetUtc(uint64_t utc_epoch_ms) {
    utc_epoch_ms_ = utc_epoch_ms;
    utc_set_ = true;
    uint8_t buf[9];
    packUtcSet(utc_epoch_ms, buf);
    s_char_sync.notify(buf, 9);
    Serial.printf("[BLE] SET_UTC: %llu ms\n", static_cast<unsigned long long>(utc_epoch_ms));
}

void BleService::handleResetSeq() {
    if (imu().running()) {
        imu().stop();
        imu().start();
    }
    Serial.println("[BLE] RESET_SEQ");
}

void BleService::sendStartFired() {
    const uint32_t now_us = micros();
    uint64_t utc_start_ms = 0;
    if (utc_set_ && pending_start_) {
        const int64_t delta_us = static_cast<int64_t>(target_start_us_) - static_cast<int64_t>(now_us);
        const int64_t delta_ms = delta_us / 1000;
        const int64_t utc_start_ms_signed = static_cast<int64_t>(utc_epoch_ms_) + delta_ms;
        utc_start_ms = static_cast<uint64_t>(utc_start_ms_signed);
    } else if (utc_set_) {
        utc_start_ms = utc_epoch_ms_;
    }
    uint8_t buf[13];
    packStartFired(now_us, utc_start_ms, buf);
    s_char_sync.notify(buf, 13);
}

void BleService::sendStopFired(uint32_t stop_device_us) {
    uint8_t buf[9];
    packStopFired(stop_device_us, imu().sampleCount(), buf);
    s_char_sync.notify(buf, 9);
}

void BleService::sendCountdownCue(uint8_t index, uint8_t total,
                                  uint16_t duration_ms) {
    uint8_t buf[5];
    packCountdownCue(index, total, duration_ms, buf);
    s_char_sync.notify(buf, sizeof(buf));
}

void BleService::sendDropCountEvent() {
    const uint32_t new_drops = imu().dropCount() - last_drop_count_;
    if (new_drops > 0) {
        uint8_t buf[5];
        packDropCountEvent(new_drops, buf);
        s_char_sync.notify(buf, 5);
        last_drop_count_ = imu().dropCount();
    }
}

void BleService::sendAcqHealth() {
    AcqState acq_state = AcqState::Ready;
    if (state_ == BleState::Countdown) acq_state = AcqState::Sync;
    if (state_ == BleState::Recording) acq_state = AcqState::Recording;
    if (transport_failures_ > 0) acq_state = AcqState::Retry;
    if (imu().dropCount() > 0) acq_state = AcqState::Error;
    uint8_t buf[ACQ_HEALTH_SIZE];
    const uint32_t produced_samples = imu().sampleCount() + imu().queueDropCount();
    packAcqHealth(acq_state, produced_samples, notified_samples_,
                  imu().queueDropCount(), transport_failures_, imu().queueDepth(),
                  imu().fifoOverflowCount(), imu().fifoDroppedSampleCount(),
                  buf);
    s_char_sync.notify(buf, sizeof(buf));
    last_health_ms_ = millis();
}

void BleService::sendCmdNack(uint8_t cmd) {
    uint8_t buf[2];
    packCmdNack(cmd, buf);
    s_char_sync.notify(buf, 2);
}

void BleService::restoreLeds() {
    if (blink_until_ms_ > 0 && millis() < blink_until_ms_) {
        return;
    }

    // Non-blocking acquisition health patterns. ERROR is a rapid red pulse;
    // RETRY alternates red/blue while the pending batch is retained.
    if (imu().dropCount() > 0) {
        const bool on = (millis() % 500) < 250;
        digitalWrite(LED_RED, on ? LOW : HIGH);
        digitalWrite(LED_BLUE, HIGH);
        return;
    }
    if (transport_failures_ > 0) {
        const bool red = (millis() / 125) % 2 == 0;
        digitalWrite(LED_RED, red ? LOW : HIGH);
        digitalWrite(LED_BLUE, red ? HIGH : LOW);
        return;
    }

    const bool is_right = (wheel_id_ == 0x52); // 0x52 = 'R' (Right wheel)

    if (state_ == BleState::Advertising) {
        bool flash_on = (millis() / 500) % 2 == 0;
        if (is_right) {
            digitalWrite(LED_RED, flash_on ? LOW : HIGH);
            digitalWrite(LED_BLUE, HIGH);
        } else {
            digitalWrite(LED_BLUE, flash_on ? LOW : HIGH);
            digitalWrite(LED_RED, HIGH);
        }
    }
    else if (state_ == BleState::Connected || state_ == BleState::Countdown) {
        if (is_right) {
            digitalWrite(LED_RED, LOW);
            digitalWrite(LED_BLUE, HIGH);
        } else {
            digitalWrite(LED_BLUE, LOW);
            digitalWrite(LED_RED, HIGH);
        }
    }
    else if (state_ == BleState::Recording) {
        if (is_right) {
            digitalWrite(LED_RED, LOW);
            bool blue_on = (millis() % 1000) < 100;
            digitalWrite(LED_BLUE, blue_on ? LOW : HIGH);
        } else {
            digitalWrite(LED_BLUE, LOW);
            bool red_on = (millis() % 1000) < 100;
            digitalWrite(LED_RED, red_on ? LOW : HIGH);
        }
    }
    else {
        digitalWrite(LED_BLUE, HIGH);
        digitalWrite(LED_RED, HIGH);
    }
}

void BleService::tick() {
    restoreLeds();

    if (connected() && !link_reported_ && millis() - connected_at_ms_ >= 1000) {
        BLEConnection* conn = Bluefruit.Connection(conn_handle_);
        if (conn) {
            mtu_ = conn->getMtu();
            const uint16_t interval_units = conn->getConnectionInterval();
            const uint32_t interval_hundredths_ms = interval_units * 125UL / 100;
            Serial.printf("[BLE] Link MTU=%u interval=%lu.%02lu ms supervision=%u ms\n",
                          mtu_, interval_hundredths_ms / 100,
                          interval_hundredths_ms % 100,
                          conn->getSupervisionTimeout() * 10);
        }
        link_reported_ = true;
    }

    if (pending_start_) {
        const uint32_t now = micros();

        // Check for blink
        const int8_t blink_idx = checkBlinkSchedule(target_start_us_, now, last_blink_fired_);
        if (blink_idx >= 0) {
            const BlinkEvent& bp = BLINK_SCHEDULE[blink_idx];
            active_blink_led_ = bp.led_type;
            blink_until_ms_ = millis() + bp.duration_ms;

            if (active_blink_led_ == 0 || active_blink_led_ == 2) {
                digitalWrite(LED_RED, LOW);
            }
            if (active_blink_led_ == 1 || active_blink_led_ == 2) {
                digitalWrite(LED_BLUE, LOW);
            }

            if (configStore().beepEnabled()) {
                sendCountdownCue(static_cast<uint8_t>(blink_idx),
                                 static_cast<uint8_t>(BLINK_SCHEDULE_LEN),
                                 bp.duration_ms);
            }
            last_blink_fired_ = blink_idx;
            Serial.printf("[BLE] Blink %d/%u (T%+ds)\n", blink_idx + 1,
                          static_cast<unsigned>(BLINK_SCHEDULE_LEN),
                          bp.offset_us / 1000000);
        }

        // Turn off blink when duration ends
        if (blink_until_ms_ > 0 && millis() >= blink_until_ms_) {
            digitalWrite(LED_RED, HIGH);
            digitalWrite(LED_BLUE, HIGH);
            blink_until_ms_ = 0;
        }

        // Check if it's time to start
        if (shouldStartNow(target_start_us_, now)) {
            digitalWrite(LED_RED, HIGH);
            digitalWrite(LED_BLUE, HIGH);
            blink_until_ms_ = 0;

            imu().start();
            pending_start_ = false;
            state_ = BleState::Recording;
            sendStartFired();
            Serial.println("[BLE] Scheduled START fired");
        }
    } else {
        if (blink_until_ms_ > 0 && millis() >= blink_until_ms_) {
            digitalWrite(LED_RED, HIGH);
            digitalWrite(LED_BLUE, HIGH);
            blink_until_ms_ = 0;
        }
    }

    if (imu().dropCount() > last_drop_count_) {
        sendDropCountEvent();
    }

    if (connected() && millis() - last_health_ms_ >= 1000) {
        sendAcqHealth();
    }

    updateBatteryLevel();
}

void BleService::bleTask() {
    if (!connected()) return;

    uint16_t conn_mtu = 23;
    BLEConnection* conn = Bluefruit.Connection(conn_handle_);
    if (conn) {
        conn_mtu = conn->getMtu();
    }
    mtu_ = conn_mtu;

    const uint8_t max_count = maxBatchCount(mtu_);
    if (max_count == 0) return;

    if (!imu().running() && stop_finalization_pending_) {
        finalizeStopIfDrained();
        return;
    }

    // During acquisition, alternate replay and live batches so gap recovery
    // never starves the current stream, even at the default 23-byte MTU.
    const bool service_replay = replay_pending_ &&
                                (!imu().running() || replay_turn_);
    if (replay_pending_ && imu().running()) {
        replay_turn_ = !replay_turn_;
    }
    if (service_replay) {
        ImuSample replay[MAX_BATCH_SAMPLES];
        uint8_t found = 0;
        while (found < max_count && replay_sent_ + found < replay_requested_) {
            const uint32_t wanted = replay_start_seq_ + replay_sent_ + found;
            bool matched = false;
            const size_t oldest = (replay_head_ + REPLAY_HISTORY_SIZE - replay_count_) % REPLAY_HISTORY_SIZE;
            for (size_t i = 0; i < replay_count_; ++i) {
                const ImuSample& candidate = replay_history_[(oldest + i) % REPLAY_HISTORY_SIZE];
                if (candidate.seq == wanted) { replay[found++] = candidate; matched = true; break; }
            }
            if (!matched) break;
        }
        if (found > 0) {
            const size_t len = packBatch(replay, found, batch_buf_);
            if (notifyImuBatch(batch_buf_, len)) {
                replay_sent_ += found;
                ++notify_count_;
            }
        }
        if (found == 0 || replay_sent_ == replay_requested_) {
            uint8_t result[10];
            const uint8_t status = replay_sent_ == replay_requested_ ? 0 : 1;
            packReplayResult(replay_start_seq_, replay_requested_, replay_sent_, status, result);
            s_char_sync.notify(result, sizeof(result));
            replay_pending_ = false;
        }
        return;
    }

    if (!imu().running()) {
        if (pending_count_ > 0) notifyPendingBatch();
        return;
    }
    const uint8_t target = targetBatchCount(mtu_, imu().rateHz());
    ImuSample sample;
    while (pending_count_ < target && pending_count_ < max_count && imu().popSample(sample)) {
        if (pending_count_ == 0) batch_started_ms_ = millis();
        pending_samples_[pending_count_++] = sample;
        replay_history_[replay_head_] = sample;
        replay_head_ = (replay_head_ + 1) % REPLAY_HISTORY_SIZE;
        if (replay_count_ < REPLAY_HISTORY_SIZE) ++replay_count_;
    }
    if (pending_count_ == 0) return;
    if (pending_count_ < target && millis() - batch_started_ms_ < BATCH_MAX_LATENCY_MS) return;
    notifyPendingBatch();
}

void BleService::finalizeStopIfDrained() {
    if (!stop_finalization_pending_) return;

    flushBatch();
    if (imu().queueDepth() != 0 || pending_count_ != 0) {
        stop_empty_since_ms_ = 0;
        return;
    }

    const uint32_t now_ms = millis();
    if (stop_empty_since_ms_ == 0) {
        stop_empty_since_ms_ = now_ms;
        return;
    }
    if (now_ms - stop_empty_since_ms_ < STOP_DRAIN_QUIET_MS) return;

    sendAcqHealth();
    sendStopFired(stop_device_us_);
    stop_finalization_pending_ = false;
    stop_empty_since_ms_ = 0;
}

bool BleService::notifyPendingBatch() {
    if (pending_count_ == 0) return true;
    const size_t len = packBatch(pending_samples_, pending_count_, batch_buf_);
    if (notifyImuBatch(batch_buf_, len)) {
        notified_samples_ += pending_count_;
        pending_count_ = 0;
        ++notify_count_;
        return true;
    }
    return false;
}

bool BleService::notifyImuBatch(const uint8_t* data, size_t len) {
    const uint32_t now_ms = millis();
    if (retry_after_ms_ != 0 &&
        !notificationRetryDue(now_ms, retry_after_ms_)) {
        return false;
    }
    if (s_char_imu.notify(data, len)) {
        if (consecutive_transport_failures_ > 0) {
            Serial.printf("[BLE] Notify recovered after %u failures\n",
                          consecutive_transport_failures_);
        }
        consecutive_transport_failures_ = 0;
        retry_after_ms_ = 0;
        return true;
    }
    ++transport_failures_;
    if (consecutive_transport_failures_ < UINT8_MAX) {
        ++consecutive_transport_failures_;
    }
    retry_after_ms_ = now_ms +
                      notificationRetryDelayMs(consecutive_transport_failures_);
    return false;
}

void BleService::flushBatch() {
    if (!connected()) return;
    const uint8_t max_count = maxBatchCount(mtu_);
    ImuSample sample;
    while (max_count > 0) {
        if (pending_count_ >= max_count && !notifyPendingBatch()) return;
        if (!imu().popSample(sample)) break;
        pending_samples_[pending_count_++] = sample;
        replay_history_[replay_head_] = sample;
        replay_head_ = (replay_head_ + 1) % REPLAY_HISTORY_SIZE;
        if (replay_count_ < REPLAY_HISTORY_SIZE) ++replay_count_;
        if (pending_count_ >= max_count && !notifyPendingBatch()) return;
    }
    notifyPendingBatch();
}

BleService& ble() {
    static BleService instance;
    return instance;
}

} // namespace WheelAthlete
