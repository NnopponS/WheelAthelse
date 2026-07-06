// display.cpp — M5StickCPlus2 status display for WheelAthlete

#include "display.h"

#include <M5Unified.h>

namespace WheelAthlete {

void StatusDisplay::begin() {
    M5.Display.setTextSize(1);
    M5.Display.setRotation(3);   // landscape for M5StickC Plus 2 (240×135)
    initialized_ = true;
}

void StatusDisplay::refresh(char wheel_id,
                            uint16_t rate_hz,
                            uint32_t sample_count,
                            uint32_t drop_count,
                            uint16_t fifo_depth,
                            uint8_t  battery_pct,
                            bool     running) {
    if (!initialized_) return;

    // Throttle redraw to avoid starving the BLE streaming loop.
    // Idle: ~5 fps (200 ms) — fast enough for status updates.
    // Recording: ~1 fps (1000 ms)
    const uint32_t now = millis();
    const uint32_t interval = running ? 1000 : 200;
    if (now - last_draw_ < interval && !countdown_active_) return;
    last_draw_ = now;

    auto& d = M5.Display;

    // If wheel ID changed, force layout redraw
    if (wheel_id != last_wheel_id_) {
        layout_drawn_ = false;
        last_wheel_id_ = wheel_id;
    }

    // ── Draw background + header bar + bottom divider only once (not every frame) ──
    if (!layout_drawn_) {
        d.fillScreen(BLACK);
        d.fillRect(0, 0, d.width(), 20, (wheel_id == 'L') ? 0x001F : 0xF800); // Blue for L, Red for R
        d.setTextColor(WHITE);
        d.setTextSize(1);
        d.setCursor(6, 4);
        d.printf("WheelAthlete  %c", wheel_id);

        // Bottom divider
        d.drawFastHLine(0, 105, d.width(), WHITE);
        
        layout_drawn_ = true;
        // Invalidate other caches to force them to draw on new layout
        has_last_running_ = false;
        last_rate_ = 0;
        last_batt_ = 0;
        last_drop_ = 999999;
    }

    // ── Countdown overlay takes priority over normal status ──
    if (countdown_active_) {
        if (countdown_num_ != last_countdown_num_) {
            // Clear the center status area for the big number
            d.fillRect(0, 20, d.width(), 85, BLACK);
            d.setTextSize(6);
            d.setTextColor(WHITE, BLACK);
            if (countdown_num_ > 0) {
                // Single digit: center it
                d.setCursor(d.width() / 2 - 18, 46);
                d.printf("%d", countdown_num_);
            } else {
                // "GO" at T-0
                d.setCursor(d.width() / 2 - 36, 46);
                d.print("GO");
            }
            d.setTextSize(1);   // restore default
            last_countdown_num_ = countdown_num_;
        }
        return;
    }

    // Reset countdown cache when inactive
    last_countdown_num_ = -99;

    // ── Large Status in Center (Y: 20 to 105) ──
    if (!has_last_running_ || running != last_running_) {
        // Clear the status area
        d.fillRect(0, 20, d.width(), 85, BLACK);
        d.setTextSize(4);
        if (running) {
            d.setTextColor(GREEN, BLACK);
            d.setCursor(84, 46);
            d.print("REC");
        } else {
            d.setTextColor(DARKGREY, BLACK);
            d.setCursor(72, 46);
            d.print("IDLE");
        }
        d.setTextSize(1); // restore
        last_running_ = running;
        has_last_running_ = true;
    }

    // ── Bottom stats (Rate, Batt, Drop) ──
    d.setTextSize(1);
    
    // Rate
    if (rate_hz != last_rate_) {
        d.setTextColor(WHITE, BLACK);
        d.setCursor(6, 115);
        d.printf("Rate: %3u Hz", rate_hz);
        last_rate_ = rate_hz;
    }

    // Battery
    if (battery_pct != last_batt_) {
        d.setTextColor(GREEN, BLACK);
        d.setCursor(95, 115);
        d.printf("Batt: %3u%%", battery_pct);
        last_batt_ = battery_pct;
    }

    // Drop
    if (drop_count != last_drop_) {
        d.setTextColor(drop_count > 0 ? RED : WHITE, BLACK);
        d.setCursor(175, 115);
        d.printf("Drop: %4lu", static_cast<unsigned long>(drop_count));
        last_drop_ = drop_count;
    }
}

void StatusDisplay::showCountdown(int8_t num) {
    countdown_num_ = num;
    countdown_active_ = true;
}

void StatusDisplay::clearCountdown() {
    if (!countdown_active_) return;
    countdown_active_ = false;
    layout_drawn_ = false;   // force full redraw to clear big number
}

StatusDisplay& display() {
    static StatusDisplay instance;
    return instance;
}

} // namespace WheelAthlete
