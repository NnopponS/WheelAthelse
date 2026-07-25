#pragma once
// ble_service.h — BLE GATT server for WheelAthlete
//
// Implements the WheelAthlete BLE protocol (docs/ble-protocol.md):
//   - WheelAthlete Service with 4 characteristics (IMU Data, Control, Sync, Info)
//   - IMU Data: batched notify from FreeRTOS queue (Core 1 task)
//   - Control: write commands (START/STOP/SET_RATE/SYNC_PING/SET_RANGE/BEEP/RESET_SEQ)
//   - Sync: notify sync responses + event notifications (START_FIRED, STOP_FIRED, etc.)
//   - Info: read-only device info (wheel id, fw version, scales)
//   - Scheduled synchronized start with countdown beep 3-2-1
//
// Architecture: BLE task runs on Core 1, separate from IMU acquisition (Core 0).
// Pure packet logic is in ble_types.h (host-testable).

#include "imu_types.h"
#include "ble_types.h"
#include "config_store.h"

#include <cstdint>

namespace WheelAthlete {

// ── BLE connection state ─────────────────────────────────────────────────────

enum class BleState : uint8_t {
    Idle,           // not advertising
    Advertising,    // advertising, no connection
    Connected,      // central connected
    Countdown,      // countdown beep in progress (pre-start)
    Recording,      // acquisition active + streaming
};

// ── BleService — singleton managing BLE GATT + streaming ─────────────────────

class BleService {
public:
    // Initialize BLE stack, create service + characteristics, start advertising.
    // wheel_id = 'L' or 'R' (from build flag).
    void begin(char wheel_id);

    // BLE streaming task — runs on Core 1.
    // Drains IMU queue → batches → notifies via IMU Data characteristic.
    // Also handles scheduled start countdown + beep.
    void bleTask();

    // Called by the dedicated BLE owner task to handle countdown, scheduled
    // start, drop events, and idle battery publication without GATT races.
    // Returns true if acquisition should be running.
    void tick();

    // Update battery level on the Battery Service characteristic.
    // Reads M5.Power.getBatteryLevel(), clamps to 0-100, notifies on change.
    void updateBatteryLevel();

    // ── Accessors for display ──
    BleState   state()        const { return state_; }
    bool       connected()    const { return state_ == BleState::Connected ||
                                              state_ == BleState::Countdown ||
                                              state_ == BleState::Recording; }
    uint16_t   mtu()          const { return mtu_; }
    uint32_t   syncPingCount()const { return sync_ping_count_; }
    uint32_t   notifyCount()  const { return notify_count_; }
    uint32_t   notifiedSamples() const { return notified_samples_; }
    uint32_t   transportFailures() const { return transport_failures_; }
    bool       transportRetryActive() const {
        return consecutive_transport_failures_ > 0;
    }
    uint32_t   targetStartUs()const { return target_start_us_; }
    bool       hasPendingStart() const { return pending_start_; }
    uint8_t    batteryLevel() const { return battery_level_; }

    // ── GATT callbacks (static, public — called from NimBLE callbacks) ──
    static void onConnect(uint16_t conn_handle, uint16_t conn_interval_units);
    static void onDisconnect();
    static void onControlWrite(const uint8_t* data, size_t len);
    static void onMtuExchange(uint16_t mtu);

    // ── Command handlers ──
    void handleCommand(Cmd cmd, const uint8_t* payload, size_t len);
    void handleStart(uint32_t target_start_us);
    void handleStop();
    void handleSetRate(uint16_t rate_hz);
    void handleSyncPing(uint32_t t_app_ms);
    void handleSetRange(uint8_t accel_range, uint8_t gyro_range);
    void handleBeep(uint8_t count, uint16_t period_ms);
    void handleSetName(const uint8_t* name_data, size_t len);
    void handleSetWheel(uint8_t wheel_id);
    void handleSetUtc(uint64_t utc_epoch_ms);
    void handleSetBeepEnabled(bool enabled);
    void handleResetSeq();
    void handleReplayRange(uint32_t start_seq, uint16_t count);

    // ── Internal helpers ──
    void sendSyncResponse(uint32_t t_app_ms);
    void sendEvent(SyncEvent event, const uint8_t* payload, size_t len);
    void sendStartFired();
    void sendCountdownCue(uint8_t index, uint8_t total, uint16_t duration_ms);
    void sendStopFired(uint32_t stop_device_us);
    void sendDropCountEvent();
    void sendAcqHealth();
    void sendCmdNack(uint8_t cmd);
    void updateInfoCharacteristic();
    void updateConfigCharacteristic();
    void updateAdvertisedName();
    void doBeep(uint16_t freq_hz, uint16_t duration_ms);
    void flushBatch();
    void finalizeStopIfDrained();
    bool notifyPendingBatch();
    bool notifyImuBatch(const uint8_t* data, size_t len);
    void recordTransportFailure(int rc, const char* stage);
    void clearTransportBackoff();
    void maybeRequestConnectionParams();

    // ── State ──
    char       wheel_id_         = 'L';
    BleState   state_            = BleState::Idle;
    uint16_t   mtu_              = 23;       // default BLE MTU
    uint16_t   conn_handle_      = 0xFFFF;   // BLE_HS_CONN_HANDLE_NONE
    uint32_t   sync_ping_count_  = 0;
    uint32_t   notify_count_     = 0;
    uint32_t   notified_samples_ = 0;
    uint32_t   target_start_us_  = 0;
    bool       pending_start_    = false;    // scheduled start waiting
    int8_t     last_beep_fired_  = -1;
    uint32_t   last_drop_count_  = 0;        // for DROP_COUNT event
    uint32_t   last_health_ms_   = 0;

    // ── Battery Service state ──
    uint8_t    battery_level_    = 0;        // last reported battery % (0-100)
    uint32_t   last_battery_ms_  = 0;        // millis() of last battery update

    // ── UTC epoch state (v1.1.0) ──
    uint64_t   utc_epoch_ms_     = 0;        // UTC epoch set via SET_UTC (0 = not set)
    bool       utc_set_          = false;

    // ── Batch buffer ──
    static constexpr uint8_t MAX_BATCH_SAMPLES = 12;
    static constexpr size_t MAX_BATCH_BUF = 1 + MAX_BATCH_SAMPLES * IMU_SAMPLE_SIZE;
    static constexpr uint32_t BATCH_MAX_LATENCY_MS = 100;
    uint8_t    batch_buf_[MAX_BATCH_BUF] = {};
    ImuSample  pending_samples_[MAX_BATCH_SAMPLES] = {};
    uint8_t    pending_count_       = 0;
    uint32_t   batch_started_ms_    = 0;
    static constexpr uint32_t STOP_DRAIN_QUIET_MS = 30;
    bool       stop_finalization_pending_ = false;
    uint32_t   stop_device_us_ = 0;
    uint32_t   stop_empty_since_ms_ = 0;
    static constexpr size_t REPLAY_HISTORY_SIZE = 512;
    ImuSample  replay_history_[REPLAY_HISTORY_SIZE] = {};
    size_t     replay_head_ = 0;
    size_t     replay_count_ = 0;
    bool       replay_pending_ = false;
    bool       replay_turn_ = true;
    uint32_t   replay_start_seq_ = 0;
    uint16_t   replay_requested_ = 0;
    uint16_t   replay_sent_ = 0;
    uint32_t   transport_failures_ = 0;
    uint8_t    consecutive_transport_failures_ = 0;
    uint32_t   retry_after_ms_ = 0;
    int        last_notify_rc_ = 0;
    uint32_t   no_subscriber_failures_ = 0;
    uint32_t   allocation_failures_ = 0;
    uint32_t   host_notify_failures_ = 0;
    uint16_t   connection_interval_units_ = 0;
    bool       connection_params_pending_ = false;
    uint32_t   connection_params_after_ms_ = 0;
};

// Global singleton
BleService& ble();

} // namespace WheelAthlete
