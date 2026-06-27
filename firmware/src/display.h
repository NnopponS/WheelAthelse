#pragma once
// display.h — M5StickCPlus2 status display for WheelSense
//
// Shows: wheel id (L/R), sample rate, sample count, battery %,
//        FIFO depth, drop count, running state.
// Refreshed periodically from the main loop (Core 1).

#include <cstdint>

namespace wheelsense {

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

private:
    bool     initialized_ = false;
    uint32_t last_draw_   = 0;   // ms of last full redraw
};

StatusDisplay& display();

} // namespace wheelsense
