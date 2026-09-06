#include "display.h"

#include <M5Unified.h>
#include <cstdio>
#include <cstring>

namespace WheelAthlete {
namespace {

void drawChanged(char* previous,
                 size_t capacity,
                 const char* next,
                 int32_t x,
                 int32_t y,
                 float text_size,
                 uint16_t color,
                 uint16_t* previous_color = nullptr) {
    const bool color_changed = previous_color && *previous_color != color;
    if (!color_changed && std::strcmp(previous, next) == 0) return;

    auto& d = M5.Display;
    d.setTextSize(text_size);
    d.setCursor(x, y);
    d.setTextColor(BLACK);
    d.print(previous);  // erase only pixels belonging to the previous glyphs

    std::snprintf(previous, capacity, "%s", next);
    d.setCursor(x, y);
    d.setTextColor(color);
    d.print(previous);
    if (previous_color) *previous_color = color;
}

} // namespace

void StatusDisplay::begin(char wheel_id) {
    auto& d = M5.Display;
    d.setRotation(3);
    d.setTextWrap(false);
    d.fillScreen(BLACK);
    d.fillRect(0, 0, 10, d.height(), wheel_id == 'L' ? BLUE : RED);

    // Static dashboard is painted exactly once, before Arduino loop().
    d.setTextColor(wheel_id == 'L' ? CYAN : ORANGE);
    d.setTextSize(6);
    d.setCursor(22, 12);
    d.printf("%c", wheel_id);

    d.setTextColor(WHITE);
    d.setTextSize(1);
    d.setCursor(22, 96);  d.print("N:");
    d.setCursor(125, 96); d.print("BAT:");
    d.setCursor(22, 114); d.print("Q:");
    d.setCursor(75, 114); d.print("D:");
    d.setCursor(145, 114); d.print("T:");
    initialized_ = true;
}

void StatusDisplay::refresh(char wheel_id,
                            uint16_t rate_hz,
                            uint32_t sample_count,
                            uint32_t drop_count,
                            uint16_t queue_depth,
                            uint8_t battery_pct,
                            bool connected,
                            bool syncing,
                            bool running,
                            bool transport_retry_active,
                            uint32_t transport_failures) {
    if (!initialized_) return;
    (void)wheel_id;  // identity is static and was painted once by begin().
    const uint32_t now = millis();
    if (!countdown_active_ && now - last_draw_ < (running ? 1000U : 250U)) return;
    last_draw_ = now;

    char status_text[8] = {};
    uint16_t status_color = GREEN;
    if (countdown_active_) {
        if (countdown_num_ > 0) {
            std::snprintf(status_text, sizeof(status_text), "%d", countdown_num_);
            status_color = YELLOW;
        } else {
            std::snprintf(status_text, sizeof(status_text), "GO");
            status_color = GREEN;
        }
        last_countdown_num_ = countdown_num_;
    } else {
        const char* status = "READY";
        if (!connected) { status = "READY"; status_color = DARKGREY; }
        if (syncing) { status = "SYNC"; status_color = YELLOW; }
        if (running) { status = "REC"; status_color = RED; }
        if (transport_retry_active) { status = "RETRY"; status_color = ORANGE; }
        if (drop_count > 0) { status = "ERROR"; status_color = RED; }
        std::snprintf(status_text, sizeof(status_text), "%s", status);
    }

    const uint32_t elapsed_s = rate_hz > 0 ? sample_count / rate_hz : 0;
    char rate_text[8];
    char elapsed_text[8];
    char count_text[12];
    char battery_text[8];
    char queue_text[8];
    char drops_text[12];
    char transport_text[12];
    std::snprintf(rate_text, sizeof(rate_text), "%3u Hz", rate_hz);
    std::snprintf(elapsed_text, sizeof(elapsed_text), "%02lu:%02lu",
                  static_cast<unsigned long>(elapsed_s / 60),
                  static_cast<unsigned long>(elapsed_s % 60));
    std::snprintf(count_text, sizeof(count_text), "%lu",
                  static_cast<unsigned long>(sample_count));
    std::snprintf(battery_text, sizeof(battery_text), "%u%%", battery_pct);
    std::snprintf(queue_text, sizeof(queue_text), "%u", queue_depth);
    std::snprintf(drops_text, sizeof(drops_text), "%lu",
                  static_cast<unsigned long>(drop_count));
    std::snprintf(transport_text, sizeof(transport_text), "%lu",
                  static_cast<unsigned long>(transport_failures));

    const uint16_t health_color = (drop_count || transport_failures) ? RED : WHITE;
    auto& d = M5.Display;
    d.startWrite();
    drawChanged(last_status_, sizeof(last_status_), status_text,
                82, 22, 3, status_color, &last_status_color_);
    drawChanged(last_rate_, sizeof(last_rate_), rate_text, 22, 78, 1, WHITE);
    drawChanged(last_elapsed_, sizeof(last_elapsed_), elapsed_text, 108, 78, 1, WHITE);
    drawChanged(last_count_, sizeof(last_count_), count_text, 36, 96, 1, WHITE);
    drawChanged(last_battery_, sizeof(last_battery_), battery_text, 158, 96, 1, WHITE);
    drawChanged(last_queue_, sizeof(last_queue_), queue_text,
                35, 114, 1, health_color, &last_queue_color_);
    drawChanged(last_drops_, sizeof(last_drops_), drops_text,
                88, 114, 1, health_color, &last_drops_color_);
    drawChanged(last_transport_, sizeof(last_transport_), transport_text,
                158, 114, 1, health_color, &last_transport_color_);
    d.endWrite();
}

void StatusDisplay::showCountdown(int8_t num) {
    countdown_num_ = num;
    countdown_active_ = true;
}

void StatusDisplay::clearCountdown() {
    countdown_active_ = false;
    last_countdown_num_ = -99;
    last_draw_ = 0;
}

StatusDisplay& display() {
    static StatusDisplay instance;
    return instance;
}

} // namespace WheelAthlete
