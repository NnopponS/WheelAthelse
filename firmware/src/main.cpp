// main.cpp — WheelSense firmware entry point (subtask #2)
//
// Wires ImuReader (MPU6886 FIFO + esp_timer on Core 0) →
//   StatusDisplay (M5 LCD on Core 1) + Serial CSV debug output.
//
// BLE GATT will be added in subtask #3 (reads from the same sample queue).

#include <M5Unified.h>

#include "imu_reader.h"
#include "display.h"

using namespace wheelsense;

// ── Build-time wheel identity (from platformio.ini build_flags) ──
// WHEEL_ID is passed as ASCII hex (0x4C='L', 0x52='R') to avoid shell quoting issues
#ifndef WHEEL_ID
#define WHEEL_ID 0x4C    // default 'L'
#endif

static constexpr char WHEEL = static_cast<char>(WHEEL_ID);

// ── Serial CSV header (matches docs/ble-protocol.md §6) ──
static const char CSV_HEADER[] =
    "seq,wheel,timestamp_app_ms,timestamp_device_us,ax,ay,az,gx,gy,gz,marker\n";

void setup() {
    M5.begin();

    // Serial debug
    Serial.begin(115200);
    delay(200);
    Serial.println("\n=== WheelSense Firmware (subtask #2) ===");
    Serial.printf("Wheel: %c\n", WHEEL);

    // Initialize display
    display().begin();

    // Initialize IMU reader (default 100 Hz, ±4g, ±2000 dps)
    if (!imu().begin()) {
        Serial.println("[FATAL] IMU init failed — check wiring");
        M5.Display.fillScreen(RED);
        M5.Display.setTextColor(WHITE);
        M5.Display.setCursor(10, 50);
        M5.Display.print("IMU FAIL");
        while (true) delay(1000);
    }

    // Print CSV header for serial debug
    Serial.print(CSV_HEADER);

    // Start acquisition
    imu().start();
    Serial.println("[MAIN] Acquisition started");
}

void loop() {
    M5.update();

    // Drain sample queue → serial CSV + display stats
    ImuSample s;
    while (imu().popSample(s)) {
        // Serial CSV (raw LSB values; physical conversion done in app per BLE protocol)
        // marker=0 (no Mark Event in subtask #2; will be added in #8)
        Serial.printf("%lu,%c,%lu,%lu,%d,%d,%d,%d,%d,%d,0\n",
                      static_cast<unsigned long>(s.seq),
                      WHEEL,
                      static_cast<unsigned long>(millis()),   // timestamp_app_ms (proxy)
                      static_cast<unsigned long>(s.t_device_us),
                      s.ax, s.ay, s.az,
                      s.gx, s.gy, s.gz);
    }

    // Refresh display (~5 fps, throttled inside refresh())
    display().refresh(WHEEL,
                      imu().rateHz(),
                      imu().sampleCount(),
                      imu().dropCount(),
                      imu().fifoDepth(),
                      static_cast<uint8_t>(M5.Power.getBatteryLevel()),
                      imu().running());

    // Button A (M5 btn) = toggle start/stop
    if (M5.BtnA.wasPressed()) {
        if (imu().running()) {
            imu().stop();
            Serial.println("[MAIN] Acquisition stopped");
        } else {
            imu().start();
            Serial.println("[MAIN] Acquisition started");
        }
    }

    // Button B = cycle sample rate (50 → 100 → 200 → 50)
    if (M5.BtnB.wasPressed()) {
        uint16_t new_rate = 50;
        switch (imu().rateHz()) {
            case 50:  new_rate = 100; break;
            case 100: new_rate = 200; break;
            case 200: new_rate = 50;  break;
            default:  new_rate = 100; break;
        }
        imu().setRate(new_rate);
        Serial.printf("[MAIN] Sample rate → %u Hz\n", new_rate);
    }

    delay(2);   // small yield to keep loop responsive
}
