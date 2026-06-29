// config_store.cpp — NVS-backed board configuration store
//
// Uses ESP32 Preferences library (NVS namespace "wacfg") to persist
// board name, wheel side, and sample rate across reboots.
// Pure logic is in config_store.h (host-testable).

#include "config_store.h"

#include <Arduino.h>
#include <Preferences.h>

namespace WheelAthlete {

static Preferences s_prefs;

void ConfigStore::begin() {
    s_prefs.begin(NVS_NAMESPACE, true);   // read-only first
    config_.wheel_id = s_prefs.getUChar("wheel", 0x4C);   // default 'L'
    config_.rate_hz  = s_prefs.getUShort("rate", 100);     // default 100 Hz

    // Read name (stored as raw bytes, null-padded)
    size_t name_len = s_prefs.getBytesLength("name");
    if (name_len > 0) {
        uint8_t name_buf[NAME_MAX_LEN] = {};
        size_t read = s_prefs.getBytes("name", name_buf, sizeof(name_buf));
        (void)read;
        std::memset(config_.name, 0, sizeof(config_.name));
        for (size_t i = 0; i < NAME_MAX_LEN && i < sizeof(name_buf); ++i) {
            config_.name[i] = static_cast<char>(name_buf[i]);
        }
        config_.name[NAME_MAX_LEN] = '\0';
    } else {
        // Default name based on wheel
        config_.setName("WheelAthlete-L");
    }
    s_prefs.end();

    // Validate loaded values
    if (!isValidWheel(config_.wheel_id)) {
        config_.wheel_id = 0x4C;
    }
    if (!isValidRate(config_.rate_hz)) {
        config_.rate_hz = 100;
    }

    loaded_ = true;
    Serial.printf("[CFG] Loaded: name='%s' wheel=%c rate=%u Hz\n",
                  config_.name, config_.wheelChar(), config_.rate_hz);
}

void ConfigStore::save() {
    s_prefs.begin(NVS_NAMESPACE, false);  // read-write
    s_prefs.putUChar("wheel", config_.wheel_id);
    s_prefs.putUShort("rate", config_.rate_hz);

    // Store name as raw bytes (null-padded)
    uint8_t name_buf[NAME_MAX_LEN] = {};
    for (size_t i = 0; i < NAME_MAX_LEN && config_.name[i] != '\0'; ++i) {
        name_buf[i] = static_cast<uint8_t>(config_.name[i]);
    }
    s_prefs.putBytes("name", name_buf, sizeof(name_buf));
    s_prefs.end();
    Serial.printf("[CFG] Saved: name='%s' wheel=%c rate=%u Hz\n",
                  config_.name, config_.wheelChar(), config_.rate_hz);
}

void ConfigStore::setName(const char* name) {
    config_.setName(name);
}

void ConfigStore::setWheel(uint8_t wheel_id) {
    if (isValidWheel(wheel_id)) {
        config_.wheel_id = wheel_id;
    }
}

void ConfigStore::setRate(uint16_t rate_hz) {
    if (isValidRate(rate_hz)) {
        config_.rate_hz = rate_hz;
    }
}

ConfigStore& configStore() {
    static ConfigStore instance;
    return instance;
}

} // namespace WheelAthlete
