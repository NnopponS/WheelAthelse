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

    // Throttle redraw to ~5 fps to avoid starving the loop
    const uint32_t now = millis();
    if (now - last_draw_ < 200) return;
    last_draw_ = now;

    auto& d = M5.Display;

    // ── Header bar ──
    d.fillScreen(BLACK);
    d.fillRect(0, 0, d.width(), 20, (wheel_id == 'L') ? 0x001F : 0xF800);  // blue=L, red=R
    d.setTextColor(WHITE);
    d.setCursor(6, 4);
    d.printf("WheelAthlete  %c", wheel_id);

    // ── Status lines ──
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

StatusDisplay& display() {
    static StatusDisplay instance;
    return instance;
}

} // namespace WheelAthlete
