#pragma once
// display.h — M5StickCPlus2 status display for WheelAthlete
//
// Shows: wheel id (L/R), sample rate, sample count, battery %,
//        FIFO depth, drop count, running state.
// Refreshed periodically from the main loop (Core 1).

#include <cstdint>

namespace WheelAthlete {

class StatusDisplay {
public:
    void begin();

    // Refresh the display with current values.
    // Called from loop() at a modest rate (e.g. every 200 ms).
    void refresh(char wheel_id,
                 uint16_t rate_hz,
                 uint32_t sample_count,
                 uint32_t drop_count,
                 uint16_t fifo_depth,
                 uint8_t  battery_pct,
                 bool     running);

    // Show countdown number on screen (3, 2, 1, GO).
    // num: 3 → "3", 2 → "2", 1 → "1", 0 → "GO"
    // Triggers an immediate draw (bypasses throttle).
    void showCountdown(int8_t num);

    // Clear countdown overlay and return to normal status display.
    void clearCountdown();

private:
    bool     initialized_      = false;
    uint32_t last_draw_        = 0;   // ms of last full redraw
    bool     layout_drawn_     = false;  // fillScreen + header drawn once
    bool     countdown_active_ = false;
    int8_t   countdown_num_    = 0;      // 3, 2, 1, 0(GO)
};

StatusDisplay& display();

} // namespace WheelAthlete
