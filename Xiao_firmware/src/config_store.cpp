// config_store.cpp — LittleFS-backed board configuration store
//
// Uses Adafruit LittleFS library (InternalFS) to persist
// board name, wheel side, and sample rate across reboots.

#include "config_store.h"

#include <Arduino.h>
#include <Adafruit_LittleFS.h>
#include <InternalFileSystem.h>

using namespace Adafruit_LittleFS_Namespace;

namespace WheelAthlete {

void ConfigStore::begin(char default_wheel) {
    uint8_t default_wheel_id = static_cast<uint8_t>(default_wheel);
    if (!isValidWheel(default_wheel_id)) {
        default_wheel_id = 0x4C; // default 'L'
    }

    InternalFS.begin();
    Adafruit_LittleFS_Namespace::File file(InternalFS);

    bool read_ok = false;
    if (file.open("/wacfg.bin", FILE_O_READ)) {
        if (file.read(&config_, sizeof(config_)) == sizeof(config_)) {
            read_ok = true;
        }
        file.close();
    }

    if (!read_ok) {
        // Use defaults
        config_.wheel_id = default_wheel_id;
        config_.rate_hz  = 100;
        if (config_.wheel_id == 0x52) {
            config_.setName("WheelAthlete-R");
        } else {
            config_.setName("WheelAthlete-L");
        }
    }

    // Stored separately so the legacy raw BoardConfig file remains readable.
    Adafruit_LittleFS_Namespace::File beep_file(InternalFS);
    if (beep_file.open("/wabeep.bin", FILE_O_READ)) {
        uint8_t value = 1;
        if (beep_file.read(&value, 1) == 1 && value <= 1) {
            beep_enabled_ = value == 1;
        }
        beep_file.close();
    }

    // Validate loaded values
    if (!isValidWheel(config_.wheel_id)) {
        config_.wheel_id = default_wheel_id;
    }
    if (!isValidRate(config_.rate_hz)) {
        config_.rate_hz = 100;
    }

    loaded_ = true;
    Serial.printf("[CFG] Loaded: name='%s' wheel=%c rate=%u Hz sound=%s\n",
                  config_.name, config_.wheelChar(), config_.rate_hz,
                  beep_enabled_ ? "on" : "off");
}

void ConfigStore::save() {
    InternalFS.begin();
    // Remove old file to avoid issues
    InternalFS.remove("/wacfg.bin");

    Adafruit_LittleFS_Namespace::File file(InternalFS);
    if (file.open("/wacfg.bin", FILE_O_WRITE)) {
        file.write(reinterpret_cast<const uint8_t*>(&config_), sizeof(config_));
        file.close();
        Serial.printf("[CFG] Saved: name='%s' wheel=%c rate=%u Hz sound=%s\n",
                      config_.name, config_.wheelChar(), config_.rate_hz,
                      beep_enabled_ ? "on" : "off");
    } else {
        Serial.println("[CFG] Error saving config file");
    }


    InternalFS.remove("/wabeep.bin");
    Adafruit_LittleFS_Namespace::File beep_file(InternalFS);
    if (beep_file.open("/wabeep.bin", FILE_O_WRITE)) {
        const uint8_t value = beep_enabled_ ? 1 : 0;
        beep_file.write(&value, 1);
        beep_file.close();
    } else {
        Serial.println("[CFG] Error saving sound preference");
    }
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

void ConfigStore::setBeepEnabled(bool enabled) {
    beep_enabled_ = enabled;
}

ConfigStore& configStore() {
    static ConfigStore instance;
    return instance;
}

} // namespace WheelAthlete
