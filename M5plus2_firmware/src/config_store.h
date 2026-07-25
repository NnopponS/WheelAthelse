#pragma once
// config_store.h — Board configuration pure logic + NVS-backed store
//
// Pure logic (host-testable): config packing/parsing, name sanitization,
// wheel/rate validation. Hardware NVS access is in config_store.cpp.
//
// Config characteristic layout (v1.6.0, 31 bytes):
//   [name 24B null-padded ASCII][wheel_id 1B][rate_hz 2B LE]
//   [fw_major 1B][fw_minor 1B][fw_patch 1B][beep_enabled 1B]
//
// Protocol reference: docs/ble-protocol.md §1.1 (Config char) + §3.1 (SET_NAME/SET_WHEEL)

#include <cstdint>
#include <cstddef>
#include <cstring>
#include "imu_types.h"   // isValidRate (50/100/200)

namespace WheelAthlete {

// ── Constants ────────────────────────────────────────────────────────────────

constexpr size_t  NAME_MAX_LEN  = 24;
constexpr size_t  CONFIG_SIZE   = 31;
constexpr const char* NVS_NAMESPACE = "wacfg";

// Config characteristic UUID (v1.1.0)
constexpr const char* CHAR_CONFIG_UUID = "0000a1b7-0000-1000-8000-00805f9b34fb";

// ── Pure functions (host-testable) ───────────────────────────────────────────

// Check if wheel_id is valid (0x4C='L' or 0x52='R').
inline bool isValidWheel(uint8_t wheel_id) {
    return wheel_id == 0x4C || wheel_id == 0x52;
}

// isValidRate is defined in imu_types.h (50/100/200 Hz)

// Sanitize a board name into a 16-byte null-padded ASCII buffer.
// Truncates to 16 bytes. `out` must be at least NAME_MAX_LEN bytes.
inline void sanitizeName(const char* name, uint8_t* out) {
    std::memset(out, 0, NAME_MAX_LEN);
    if (!name) return;
    for (size_t i = 0; i < NAME_MAX_LEN && name[i] != '\0'; ++i) {
        out[i] = static_cast<uint8_t>(name[i]);
    }
}

// Pack Config characteristic (22 bytes, little-endian).
// [name 16B][wheel_id 1B][rate_hz 2B LE][fw_major 1B][fw_minor 1B][fw_patch 1B]
inline void packConfig(const char* name,
                       uint8_t wheel_id,
                       uint16_t rate_hz,
                       uint8_t fw_major, uint8_t fw_minor, uint8_t fw_patch,
                       bool beep_enabled,
                       uint8_t* buf) {
    sanitizeName(name, buf);                          // bytes 0-15
    buf[24] = wheel_id;
    std::memcpy(buf + 25, &rate_hz, 2);
    buf[27] = fw_major;
    buf[28] = fw_minor;
    buf[29] = fw_patch;
    buf[30] = beep_enabled ? 1 : 0;
}

// ── BoardConfig — runtime config struct ──────────────────────────────────────

struct BoardConfig {
    char     name[NAME_MAX_LEN + 1] = {};   // null-terminated for convenience
    uint8_t  wheel_id    = 0x4C;            // 'L' default
    uint16_t rate_hz     = 100;             // default 100 Hz
    bool     beep_enabled = true;            // countdown audio default on

    void setName(const char* n) {
        std::memset(name, 0, sizeof(name));
        if (!n) return;
        for (size_t i = 0; i < NAME_MAX_LEN && n[i] != '\0'; ++i) {
            name[i] = n[i];
        }
        name[NAME_MAX_LEN] = '\0';
    }

    char wheelChar() const { return static_cast<char>(wheel_id); }
};

// ── ConfigStore — NVS-backed persistent config (hardware in .cpp) ────────────

class ConfigStore {
public:
    // Load config from NVS (or use defaults if not set). Call before ble().begin().
    void begin(char default_wheel);

    // Save config to NVS (rate cached in RAM, persist on stop/disconnect).
    void save();

    // Get current config (RAM-cached).
    const BoardConfig& config() const { return config_; }

    // Setters — update RAM cache. Call save() to persist.
    void setName(const char* name);
    void setWheel(uint8_t wheel_id);
    void setRate(uint16_t rate_hz);
    void setBeepEnabled(bool enabled);

    // Accessors
    const char* name() const { return config_.name; }
    uint8_t wheelId() const { return config_.wheel_id; }
    char wheelChar() const { return config_.wheelChar(); }
    uint16_t rateHz() const { return config_.rate_hz; }
    bool beepEnabled() const { return config_.beep_enabled; }

private:
    BoardConfig config_{};
    bool        loaded_ = false;
};

// Global singleton
ConfigStore& configStore();

} // namespace WheelAthlete
