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
    // Recording: ~1 fps (1000 ms) — display updates are irrelevant during
    // active recording; the priority is draining the IMU queue. Every
    // display refresh takes several ms of SPI time which delays bleTask().
    const uint32_t now = millis();
    const uint32_t interval = running ? 1000 : 200;
    if (now - last_draw_ < interval) return;
    last_draw_ = now;

    auto& d = M5.Display;

    // ── Draw background + header bar only once (not every frame) ──
    // Text below uses setTextColor(fg, BLACK) which self-clears each char,
    // so we don't need fillScreen every frame.
    if (!layout_drawn_) {
        d.fillScreen(BLACK);
        d.fillRect(0, 0, d.width(), 20, (wheel_id == 'L') ? 0x001F : 0xF800);
        d.setTextColor(WHITE);
        d.setCursor(6, 4);
        d.printf("WheelAthlete  %c", wheel_id);
        layout_drawn_ = true;
    }

    // ── Countdown overlay takes priority over normal status ──
    if (countdown_active_) {
        // Clear the status area (below header) for the big number
        d.fillRect(0, 20, d.width(), d.height() - 20, BLACK);
        d.setTextSize(6);
        d.setTextColor(WHITE, BLACK);
        if (countdown_num_ > 0) {
            // Single digit: center it
            d.setCursor(d.width() / 2 - 18, d.height() / 2 - 24);
            d.printf("%d", countdown_num_);
        } else {
            // "GO" at T-0
            d.setCursor(d.width() / 2 - 36, d.height() / 2 - 24);
            d.print("GO");
        }
        d.setTextSize(1);   // restore default
        return;
    }

    // ── Status lines (text self-clears via setTextColor(fg, BLACK)) ──
    d.setTextColor(WHITE, BLACK);
    d.setCursor(6, 28);
    d.printf("Rate:  %u Hz", rate_hz);

    d.setCursor(6, 44);
    d.printf("Count: %lu", static_cast<unsigned long>(sample_count));

    d.setCursor(6, 60);
    d.setTextColor(GREEN, BLACK);
    d.printf("Batt:  %u%%", battery_pct);

    d.setTextColor(WHITE, BLACK);
    d.setCursor(6, 76);
    d.printf("FIFO:  %u", fifo_depth);

    d.setCursor(6, 92);
    d.setTextColor(drop_count > 0 ? RED : WHITE, BLACK);
    d.printf("Drop:  %lu", static_cast<unsigned long>(drop_count));

    // ── Running indicator ──
    d.setCursor(6, 108);
    if (running) {
        d.setTextColor(GREEN, BLACK);
        d.print("● REC");
    } else {
        d.setTextColor(DARKGREY, BLACK);
        d.print("○ IDLE");
    }
}

void StatusDisplay::showCountdown(int8_t num) {
    countdown_num_ = num;
    countdown_active_ = true;
    last_draw_ = 0;   // force immediate draw on next refresh()
}

void StatusDisplay::clearCountdown() {
    if (!countdown_active_) return;
    countdown_active_ = false;
    layout_drawn_ = false;   // force full redraw to clear big number
    last_draw_ = 0;          // force immediate redraw
}

StatusDisplay& display() {
    static StatusDisplay instance;
    return instance;
}

} // namespace WheelAthlete
