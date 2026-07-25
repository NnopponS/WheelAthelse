#pragma once

#include <cstdint>

namespace WheelAthlete {

class StatusDisplay {
public:
    void begin(char wheel_id);

    void refresh(char wheel_id,
                 uint16_t rate_hz,
                 uint32_t sample_count,
                 uint32_t drop_count,
                 uint16_t queue_depth,
                 uint8_t battery_pct,
                 bool connected,
                 bool syncing,
                 bool running,
                 bool transport_retry_active,
                 uint32_t transport_failures);

    void showCountdown(int8_t num);
    void clearCountdown();

private:
    bool initialized_ = false;
    uint32_t last_draw_ = 0;
    bool countdown_active_ = false;
    int8_t countdown_num_ = 0;
    int8_t last_countdown_num_ = -99;
    char last_status_[8] = {};
    char last_rate_[8] = {};
    char last_elapsed_[8] = {};
    char last_count_[12] = {};
    char last_battery_[8] = {};
    char last_queue_[8] = {};
    char last_drops_[12] = {};
    char last_transport_[12] = {};
    uint16_t last_status_color_ = 0;
    uint16_t last_queue_color_ = 0;
    uint16_t last_drops_color_ = 0;
    uint16_t last_transport_color_ = 0;
};

StatusDisplay& display();

} // namespace WheelAthlete
