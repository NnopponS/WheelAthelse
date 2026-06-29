#pragma once
// ble_types.h — Pure logic for BLE packet packing, sync response, info layout,
// beep scheduling, and batch size calculation.
//
// This header is HARDWARE-FREE (no Arduino/NimBLE/ESP32) so it can be
// unit-tested on the host via Python mirror tests.
// The hardware-dependent BleService class in ble_service.h/.cpp uses these types.
//
// Protocol reference: docs/ble-protocol.md
// Architecture:       .project/architecture.md §1 + §4 (Time Sync)

#include <cstdint>
#include <cstddef>
#include <cstring>
#include "imu_types.h"

namespace WheelAthlete {

// ── BLE UUIDs (from docs/ble-protocol.md §1) ─────────────────────────────────
// Using 128-bit Bluetooth Base UUID: 0000xxxx-0000-1000-8000-00805f9b34fb

constexpr const char* SERVICE_UUID         = "0000a1b2-0000-1000-8000-00805f9b34fb";
constexpr const char* CHAR_IMU_DATA_UUID   = "0000a1b3-0000-1000-8000-00805f9b34fb";
constexpr const char* CHAR_CONTROL_UUID    = "0000a1b4-0000-1000-8000-00805f9b34fb";
constexpr const char* CHAR_SYNC_UUID       = "0000a1b5-0000-1000-8000-00805f9b34fb";
constexpr const char* CHAR_INFO_UUID       = "0000a1b6-0000-1000-8000-00805f9b34fb";

// ── Standard BLE Battery Service (§1.2 — added v1.1.0) ───────────────────────
constexpr const char* BATTERY_SERVICE_UUID     = "0000180f-0000-1000-8000-00805f9b34fb";
constexpr const char* BATTERY_LEVEL_CHAR_UUID  = "00002a19-0000-1000-8000-00805f9b34fb";

// ── Packet sizes (from protocol) ─────────────────────────────────────────────

constexpr size_t IMU_SAMPLE_SIZE    = 20;   // §2.1
constexpr size_t SYNC_RESPONSE_SIZE = 12;   // §4.1
constexpr size_t INFO_SIZE          = 16;   // §5
constexpr size_t BATTERY_LEVEL_SIZE = 1;    // §1.2 — uint8 0-100%
constexpr size_t SYNC_EVENT_HEADER  = 1;    // event_id byte

// ── Control commands (§3.1) ──────────────────────────────────────────────────

enum class Cmd : uint8_t {
    Start      = 0x01,
    Stop       = 0x02,
    SetRate    = 0x03,
    SyncPing   = 0x04,
    SetRange   = 0x05,
    Beep       = 0x06,
    ResetSeq   = 0xFF,
};

// ── Sync event IDs (§4.4) ────────────────────────────────────────────────────

enum class SyncEvent : uint8_t {
    SyncResponse = 0x00,
    DropCount    = 0x10,
    CmdNack      = 0x20,
    StartFired   = 0x30,
    StopFired    = 0x40,
};

// ── Pure functions (testable on host) ────────────────────────────────────────

// Pack a single ImuSample into a 20-byte buffer (little-endian).
// ImuSample fields are already in host order; this serializes them.
inline void packSample(const ImuSample& s, uint8_t* buf) {
    std::memcpy(buf + 0,  &s.seq,          4);
    std::memcpy(buf + 4,  &s.t_device_us,  4);
    std::memcpy(buf + 8,  &s.ax,           2);
    std::memcpy(buf + 10, &s.ay,           2);
    std::memcpy(buf + 12, &s.az,           2);
    std::memcpy(buf + 14, &s.gx,           2);
    std::memcpy(buf + 16, &s.gy,           2);
    std::memcpy(buf + 18, &s.gz,           2);
}

// Pack a batch of samples: [uint8 count][sample_0]...[sample_{count-1}]
// Returns total bytes written. buf must be large enough (1 + count*20).
inline size_t packBatch(const ImuSample* samples, uint8_t count, uint8_t* buf) {
    buf[0] = count;
    for (uint8_t i = 0; i < count; ++i) {
        packSample(samples[i], buf + 1 + i * IMU_SAMPLE_SIZE);
    }
    return 1 + static_cast<size_t>(count) * IMU_SAMPLE_SIZE;
}

// Max batch count given MTU size.
// BLE notify payload max = MTU - 3 (ATT header).
// Batch = 1 byte count + count * 20 bytes samples.
// → count = floor((MTU - 3 - 1) / 20)
inline uint8_t maxBatchCount(uint16_t mtu) {
    if (mtu <= 4) return 0;
    const size_t payload = static_cast<size_t>(mtu) - 3;
    if (payload <= 1) return 0;
    return static_cast<uint8_t>((payload - 1) / IMU_SAMPLE_SIZE);
}

// Pack a Sync Response packet (12 bytes, little-endian).
// §4.1: [uint32 t_app_ms][uint32 t_device_us][uint32 seq_ping]
inline void packSyncResponse(uint32_t t_app_ms,
                              uint32_t t_device_us,
                              uint32_t seq_ping,
                              uint8_t* buf) {
    std::memcpy(buf + 0, &t_app_ms,     4);
    std::memcpy(buf + 4, &t_device_us,  4);
    std::memcpy(buf + 8, &seq_ping,     4);
}

// Pack an event notification (Sync characteristic).
// Layout: [uint8 event_id][payload...]
inline void packSyncEvent(SyncEvent event_id, const uint8_t* payload,
                          size_t payload_len, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(event_id);
    if (payload && payload_len > 0) {
        std::memcpy(buf + 1, payload, payload_len);
    }
}

// Pack START_FIRED event: [0x30][uint32 t_device_us]
inline void packStartFired(uint32_t t_device_us, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::StartFired);
    std::memcpy(buf + 1, &t_device_us, 4);
}

// Pack STOP_FIRED event: [0x40][uint32 t_device_us][uint32 last_seq]
inline void packStopFired(uint32_t t_device_us, uint32_t last_seq, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::StopFired);
    std::memcpy(buf + 1, &t_device_us, 4);
    std::memcpy(buf + 5, &last_seq, 4);
}

// Pack DROP_COUNT event: [0x10][uint32 count]
inline void packDropCountEvent(uint32_t count, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::DropCount);
    std::memcpy(buf + 1, &count, 4);
}

// Pack CMD_NACK event: [0x20][uint8 cmd]
inline void packCmdNack(uint8_t cmd, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::CmdNack);
    buf[1] = cmd;
}

// Pack Info characteristic (16 bytes, §5).
// [uint8 wheel_id][uint8 fw_major][uint8 fw_minor][uint8 fw_patch]
// [uint8 accel_range][uint8 gyro_range][float32 accel_scale][float32 gyro_scale][uint16 reserved]
inline void packInfo(uint8_t wheel_id,
                     uint8_t fw_major, uint8_t fw_minor, uint8_t fw_patch,
                     uint8_t accel_range, uint8_t gyro_range,
                     float accel_scale, float gyro_scale,
                     uint8_t* buf) {
    buf[0] = wheel_id;
    buf[1] = fw_major;
    buf[2] = fw_minor;
    buf[3] = fw_patch;
    buf[4] = accel_range;
    buf[5] = gyro_range;
    std::memcpy(buf + 6, &accel_scale, 4);
    std::memcpy(buf + 10, &gyro_scale, 4);
    buf[14] = 0;  // reserved
    buf[15] = 0;
}

// ── Beep scheduling (§3.3) ───────────────────────────────────────────────────
// Beep at T-3s, T-2s, T-1s, T-0 relative to target_start_us.
// Each beep has a time offset (negative = before start) and a tone.

struct BeepEvent {
    int32_t  offset_us;    // relative to target_start_us (negative = before)
    uint16_t freq_hz;      // beep frequency
    uint16_t duration_ms;  // beep duration
};

// Standard countdown beep schedule: 3 short beeps + 1 long beep at start
constexpr BeepEvent BEEP_SCHEDULE[] = {
    { -3000000, 880, 150 },   // T-3s: 880 Hz, 150 ms
    { -2000000, 880, 150 },   // T-2s: 880 Hz, 150 ms
    { -1000000, 880, 150 },   // T-1s: 880 Hz, 150 ms
    {         0, 1320, 500 }, // T-0:  1320 Hz, 500 ms (higher tone, longer)
};
constexpr size_t BEEP_SCHEDULE_LEN = 4;

// Check if a beep should fire at the current time.
// Returns the beep index (0..3) if a beep should fire now, or -1 if none.
// `last_beep_fired` is the index of the last beep that was triggered (-1 = none yet).
inline int8_t checkBeepSchedule(uint32_t target_start_us,
                                uint32_t current_us,
                                int8_t last_beep_fired) {
    // Handle micros() wrap: if target is in the future, current < target.
    // We check if current >= target + offset for each beep.
    for (size_t i = static_cast<size_t>(last_beep_fired) + 1; i < BEEP_SCHEDULE_LEN; ++i) {
        // target_start_us + offset_us (offset is negative for T-3..T-1, 0 for T-0)
        // Use signed arithmetic carefully with uint32 wrap.
        const int64_t beep_time = static_cast<int64_t>(target_start_us) +
                                  static_cast<int64_t>(BEEP_SCHEDULE[i].offset_us);
        const int64_t current_signed = static_cast<int64_t>(current_us);

        // If beep_time has passed (current >= beep_time)
        if (current_signed >= beep_time) {
            return static_cast<int8_t>(i);
        }
    }
    return -1;
}

// Check if it's time to start acquisition (micros >= target_start_us).
// Handles the case where target_start_us = 0 (start immediately).
inline bool shouldStartNow(uint32_t target_start_us, uint32_t current_us) {
    if (target_start_us == 0) return true;
    return current_us >= target_start_us;
}

// Clamp a raw battery reading to the valid BLE Battery Level range [0, 100].
// M5.Power.getBatteryLevel() may return -1 (unknown) or values > 100.
// Returns 0 for negative/unknown, caps at 100.
inline uint8_t clampBatteryLevel(int32_t raw) {
    if (raw < 0) return 0;
    if (raw > 100) return 100;
    return static_cast<uint8_t>(raw);
}

// Parse a Control command from the write buffer.
// Returns the command byte. Payload is copied to payload_buf (if not null).
// payload_len is set to the number of payload bytes.
inline Cmd parseCommand(const uint8_t* data, size_t len,
                        uint8_t* payload_buf, size_t& payload_len) {
    payload_len = 0;
    if (len == 0) return static_cast<Cmd>(0x00);  // invalid
    const uint8_t cmd = data[0];
    if (len > 1 && payload_buf) {
        payload_len = len - 1;
        std::memcpy(payload_buf, data + 1, payload_len);
    } else if (len > 1) {
        payload_len = len - 1;
    }
    return static_cast<Cmd>(cmd);
}

} // namespace WheelAthlete
