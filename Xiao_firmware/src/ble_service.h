#pragma once
// ble_service.h — BLE GATT server for WheelAthlete using Adafruit Bluefruit nRF52

#include "imu_types.h"
#include "ble_types.h"
#include "config_store.h"

#include <cstdint>

namespace WheelAthlete {

enum class BleState : uint8_t {
    Idle,           // not advertising
    Advertising,    // advertising, no connection
    Connected,      // central connected
    Countdown,      // countdown blink in progress (pre-start)
    Recording,      // acquisition active + streaming
};

class BleService {
public:
    void begin(char wheel_id);

    // Drains IMU queue → batches → notifies via IMU Data characteristic.
    void bleTask();

    // Handles countdown blinks + scheduled start.
    void tick();

    // Update battery level (0-100%)
    void updateBatteryLevel();

    // Accessors
    BleState   state()        const { return state_; }
    bool       connected()    const { return state_ == BleState::Connected ||
                                              state_ == BleState::Countdown ||
                                              state_ == BleState::Recording; }
    uint16_t   mtu()          const { return mtu_; }
    uint32_t   syncPingCount()const { return sync_ping_count_; }
    uint32_t   notifyCount()  const { return notify_count_; }
    uint32_t   notifiedSamples() const { return notified_samples_; }
    uint32_t   transportFailures() const { return transport_failures_; }
    uint32_t   targetStartUs()const { return target_start_us_; }
    bool       hasPendingStart() const { return pending_start_; }
    uint8_t    batteryLevel() const { return battery_level_; }

    // Command handlers
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

    // Internal helpers
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
    void flushBatch();
    void finalizeStopIfDrained();
    bool notifyPendingBatch();
    bool notifyImuBatch(const uint8_t* data, size_t len);

    // LED UI helpers
    void restoreLeds();

    // Callbacks
    void onConnect(uint16_t conn_handle);
    void onDisconnect(uint16_t conn_handle, uint8_t reason);
    void onMtuExchange(uint16_t conn_handle, uint16_t mtu);

    // State
    char       wheel_id_         = 'L';
    BleState   state_            = BleState::Idle;
    uint16_t   mtu_              = 23;       // default BLE MTU
    uint32_t   sync_ping_count_  = 0;
    uint32_t   notify_count_     = 0;
    uint32_t   notified_samples_ = 0;
    uint32_t   target_start_us_  = 0;
    bool       pending_start_    = false;    // scheduled start waiting
    int8_t     last_blink_fired_ = -1;
    uint32_t   last_drop_count_  = 0;        // for DROP_COUNT event
    uint32_t   last_health_ms_   = 0;

    // Battery state
    uint8_t    battery_level_    = 0;        // last reported battery % (0-100)
    uint32_t   last_battery_ms_  = 0;        // millis() of last battery update
    float      filtered_battery_ = -1.0f;

    // UTC epoch state
    uint64_t   utc_epoch_ms_     = 0;        // UTC epoch set via SET_UTC (0 = not set)
    bool       utc_set_          = false;

    // LED countdown state
    uint32_t   blink_until_ms_   = 0;
    uint8_t    active_blink_led_ = 0;        // 0 = Red, 1 = Blue, 2 = Both

    // Batch buffer
    static constexpr uint8_t MAX_BATCH_SAMPLES = 12;
    static constexpr size_t MAX_BATCH_BUF = 1 + MAX_BATCH_SAMPLES * IMU_SAMPLE_SIZE;
    static constexpr uint32_t BATCH_MAX_LATENCY_MS = 100;
    uint8_t    batch_buf_[MAX_BATCH_BUF] = {};
    ImuSample  pending_samples_[MAX_BATCH_SAMPLES] = {};
    uint8_t    pending_count_ = 0;
    uint32_t   batch_started_ms_ = 0;
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
};

// Global singleton
BleService& ble();

} // namespace WheelAthlete
