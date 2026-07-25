#pragma once
// ble_types.h — Pure logic for BLE packet packing, sync response, info layout,
// blink scheduling, and batch size calculation.
//
// This header is HARDWARE-FREE so it can be easily shared.
//
// Protocol reference: docs/ble-protocol.md

#include <cstdint>
#include <cstddef>
#include <cstring>
#include "imu_types.h"

namespace WheelAthlete {

// ── BLE UUIDs (from docs/ble-protocol.md §1) ──
constexpr const char* SERVICE_UUID         = "0000a1b2-0000-1000-8000-00805f9b34fb";
constexpr const char* CHAR_IMU_DATA_UUID   = "0000a1b3-0000-1000-8000-00805f9b34fb";
constexpr const char* CHAR_CONTROL_UUID    = "0000a1b4-0000-1000-8000-00805f9b34fb";
constexpr const char* CHAR_SYNC_UUID       = "0000a1b5-0000-1000-8000-00805f9b34fb";
constexpr const char* CHAR_INFO_UUID       = "0000a1b6-0000-1000-8000-00805f9b34fb";
constexpr const char* CHAR_CONFIG_UUID     = "0000a1b7-0000-1000-8000-00805f9b34fb";

// ── Standard BLE Battery Service ──
constexpr const char* BATTERY_SERVICE_UUID     = "0000180f-0000-1000-8000-00805f9b34fb";
constexpr const char* BATTERY_LEVEL_CHAR_UUID  = "00002a19-0000-1000-8000-00805f9b34fb";

// ── Packet sizes ──
constexpr size_t IMU_SAMPLE_SIZE    = 20;   // §2.1
constexpr size_t SYNC_RESPONSE_SIZE = 12;   // §4.1
constexpr size_t INFO_SIZE          = 16;   // §5
constexpr size_t BATTERY_LEVEL_SIZE = 1;    // §1.2 — uint8 0-100%
constexpr size_t SYNC_EVENT_HEADER  = 1;    // event_id byte
constexpr size_t ACQ_HEALTH_SIZE    = 28;   // legacy 20B + FIFO faults + FIFO drops
static_assert(ACQ_HEALTH_SIZE == 28, "ACQ_HEALTH wire size changed");
constexpr uint8_t TARGET_NOTIFICATIONS_PER_SECOND = 10;

// ── Control commands (§3.1) ──
enum class Cmd : uint8_t {
    Start      = 0x01,
    Stop       = 0x02,
    SetRate    = 0x03,
    SyncPing   = 0x04,
    SetRange   = 0x05,
    Beep       = 0x06,
    SetName    = 0x07,   // board name
    SetWheel   = 0x08,   // 0x4C='L' / 0x52='R'
    SetUtc     = 0x09,   // uint64 LE epoch ms
    ReplayRange= 0x0A,
    SetBeepEnabled = 0x0B,
    ResetSeq   = 0xFF,
};

// ── Sync event IDs (§4.4) ──
enum class SyncEvent : uint8_t {
    AcqHealth    = 0x60,
    ReplayResult = 0x61,
    SyncResponse = 0x00,
    DropCount    = 0x10,
    CmdNack      = 0x20,
    StartFired   = 0x30,
    CountdownCue= 0x31,
    StopFired    = 0x40,
    UtcSet       = 0x50,   // echo UTC epoch back
};

enum class AcqState : uint8_t {
    Ready = 0,
    Sync = 1,
    Recording = 2,
    Retry = 3,
    Error = 4,
};

// Pack a single ImuSample into a 20-byte buffer (little-endian).
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

// Pack a batch of samples.
inline size_t packBatch(const ImuSample* samples, uint8_t count, uint8_t* buf) {
    buf[0] = count;
    for (uint8_t i = 0; i < count; ++i) {
        packSample(samples[i], buf + 1 + i * IMU_SAMPLE_SIZE);
    }
    return 1 + static_cast<size_t>(count) * IMU_SAMPLE_SIZE;
}

// Max batch count given MTU size.
inline uint8_t maxBatchCount(uint16_t mtu) {
    if (mtu <= 4) return 0;
    const size_t payload = static_cast<size_t>(mtu) - 3;
    if (payload <= 1) return 0;
    return static_cast<uint8_t>((payload - 1) / IMU_SAMPLE_SIZE);
}

// Target batch count based on sample rate, bounded by MTU capacity.
inline uint8_t targetBatchCount(uint16_t mtu, uint16_t rate_hz) {
    const uint16_t rate = isValidRate(rate_hz) ? rate_hz : 100;
    const uint16_t requested =
        (rate + TARGET_NOTIFICATIONS_PER_SECOND - 1) /
        TARGET_NOTIFICATIONS_PER_SECOND;
    const uint8_t target = static_cast<uint8_t>(requested);
    const uint8_t max_count = maxBatchCount(mtu);
    return target < max_count ? target : max_count;
}

inline uint32_t notificationRetryDelayMs(uint8_t consecutive_failures) {
    if (consecutive_failures == 0) return 0;
    if (consecutive_failures >= 5) return 100;
    return 10u << (consecutive_failures - 1);
}

inline bool notificationRetryDue(uint32_t now_ms, uint32_t retry_after_ms) {
    return static_cast<int32_t>(now_ms - retry_after_ms) >= 0;
}

// Pack a Sync Response packet.
inline void packSyncResponse(uint32_t t_app_ms,
                              uint32_t t_device_us,
                              uint32_t seq_ping,
                              uint8_t* buf) {
    std::memcpy(buf + 0, &t_app_ms,     4);
    std::memcpy(buf + 4, &t_device_us,  4);
    std::memcpy(buf + 8, &seq_ping,     4);
}

// Pack an event notification.
inline void packSyncEvent(SyncEvent event_id, const uint8_t* payload,
                          size_t payload_len, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(event_id);
    if (payload && payload_len > 0) {
        std::memcpy(buf + 1, payload, payload_len);
    }
}

// Compute the UTC start ms for a scheduled start.
inline uint64_t computeStartFiredUtcMs(uint64_t utc_epoch_ms,
                                       uint32_t target_start_us,
                                       uint32_t now_us,
                                       bool utc_set,
                                       bool pending_start) {
    if (!utc_set) return 0;
    if (pending_start) {
        const int64_t delta_us = static_cast<int64_t>(target_start_us) -
                                 static_cast<int64_t>(now_us);
        const int64_t delta_ms = delta_us / 1000;
        const int64_t utc_start_ms_signed =
            static_cast<int64_t>(utc_epoch_ms) + delta_ms;
        return static_cast<uint64_t>(utc_start_ms_signed);
    }
    return utc_epoch_ms;
}

// Pack START_FIRED event.
inline void packStartFired(uint32_t t_device_us, uint64_t utc_start_ms, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::StartFired);
    std::memcpy(buf + 1, &t_device_us, 4);
    std::memcpy(buf + 5, &utc_start_ms, 8);
}


inline void packCountdownCue(uint8_t index, uint8_t total,
                             uint16_t duration_ms, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::CountdownCue);
    buf[1] = index;
    buf[2] = total;
    std::memcpy(buf + 3, &duration_ms, 2);
}

// Pack UTC_SET event.
inline void packUtcSet(uint64_t utc_epoch_ms, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::UtcSet);
    std::memcpy(buf + 1, &utc_epoch_ms, 8);
}

// Pack STOP_FIRED event.
inline void packStopFired(uint32_t t_device_us, uint32_t last_seq, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::StopFired);
    std::memcpy(buf + 1, &t_device_us, 4);
    std::memcpy(buf + 5, &last_seq, 4);
}

// Pack DROP_COUNT event.
inline void packDropCountEvent(uint32_t count, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::DropCount);
    std::memcpy(buf + 1, &count, 4);
}

// Pack CMD_NACK event.
inline void packCmdNack(uint8_t cmd, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::CmdNack);
    buf[1] = cmd;
}

// Pack Info characteristic.
inline void packInfo(uint8_t wheel_id,
                     uint8_t fw_major, uint8_t fw_minor, uint8_t fw_patch,
                     uint8_t accel_range, uint8_t gyro_range,
                     float accel_scale, float gyro_scale,
                     uint8_t* buf);

inline void packReplayResult(uint32_t start_seq, uint16_t requested,
                             uint16_t replayed, uint8_t status, uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::ReplayResult);
    std::memcpy(buf + 1, &start_seq, 4);
    std::memcpy(buf + 5, &requested, 2);
    std::memcpy(buf + 7, &replayed, 2);
    buf[9] = status;
}

inline void packAcqHealth(AcqState state, uint32_t produced_samples,
                          uint32_t notified_samples, uint32_t queue_drops,
                          uint32_t transport_failures, uint16_t queue_depth,
                          uint32_t fifo_faults,
                          uint32_t fifo_dropped_samples,
                          uint8_t* buf) {
    buf[0] = static_cast<uint8_t>(SyncEvent::AcqHealth);
    buf[1] = static_cast<uint8_t>(state);
    std::memcpy(buf + 2, &produced_samples, 4);
    std::memcpy(buf + 6, &notified_samples, 4);
    std::memcpy(buf + 10, &queue_drops, 4);
    std::memcpy(buf + 14, &transport_failures, 4);
    std::memcpy(buf + 18, &queue_depth, 2);
    std::memcpy(buf + 20, &fifo_faults, 4);
    std::memcpy(buf + 24, &fifo_dropped_samples, 4);
}

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

// ── Blink scheduling (for LED 5-4-3-2-1 countdown) ──
struct BlinkEvent {
    int32_t  offset_us;    // relative to target_start_us (negative = before)
    uint8_t  led_type;     // 0 = Red, 1 = Blue, 2 = Both
    uint16_t duration_ms;  // blink duration
};

// Match the M5 countdown: 3 short flashes and one long start flash.
constexpr BlinkEvent BLINK_SCHEDULE[] = {
    { -3000000, 0, 150 },   // T-3s: Red LED, 150 ms
    { -2000000, 0, 150 },   // T-2s: Red LED, 150 ms
    { -1000000, 0, 150 },   // T-1s: Red LED, 150 ms
    {         0, 2, 500 },   // T-0:  Both LEDs, 500 ms (higher tone, longer)
};
constexpr size_t BLINK_SCHEDULE_LEN = 4;

// Check if a blink should fire at the current time.
inline int8_t checkBlinkSchedule(uint32_t target_start_us,
                                 uint32_t current_us,
                                 int8_t last_blink_fired) {
    for (size_t i = static_cast<size_t>(last_blink_fired) + 1; i < BLINK_SCHEDULE_LEN; ++i) {
        const int64_t blink_time = static_cast<int64_t>(target_start_us) +
                                   static_cast<int64_t>(BLINK_SCHEDULE[i].offset_us);
        const int64_t current_signed = static_cast<int64_t>(current_us);

        if (blink_time < 0) {
            if (current_signed < 0 && current_signed >= blink_time) {
                return static_cast<int8_t>(i);
            }
            continue;
        }

        if (current_signed >= blink_time) {
            return static_cast<int8_t>(i);
        }
    }
    return -1;
}

// Check if it's time to start acquisition.
inline bool shouldStartNow(uint32_t target_start_us, uint32_t current_us) {
    if (target_start_us == 0) return true;
    return current_us >= target_start_us;
}

// Clamp a raw battery reading to [0, 100]
inline uint8_t clampBatteryLevel(int32_t raw) {
    if (raw < 0) return 0;
    if (raw > 100) return 100;
    return static_cast<uint8_t>(raw);
}

// Parse a Control command from the write buffer.
inline Cmd parseCommand(const uint8_t* data, size_t len,
                        uint8_t* payload_buf, size_t& payload_len) {
    payload_len = 0;
    if (len == 0) return static_cast<Cmd>(0x00);
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
