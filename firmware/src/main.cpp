// main.cpp — WheelAthlete firmware entry point (subtask #2 + #3)
//
// Core 0: IMU acquisition (esp_timer → FIFO → queue)  [imu_reader.cpp]
// Core 1: Arduino loop — BLE streaming + display + buttons  [this file]
//
// BLE GATT (subtask #3):
//   - BleService handles IMU Data notify, Control commands, Sync, Info
//   - Scheduled start with countdown beep 3-2-1
//   - BLE task drains queue → batches → notifies

#include <M5Unified.h>

#include "imu_reader.h"
#include "display.h"
#include "ble_service.h"

using namespace WheelAthlete;

// ── Build-time wheel identity (from platformio.ini build_flags) ──
// WHEEL_ID is passed as ASCII hex (0x4C='L', 0x52='R') to avoid shell quoting issues
#ifndef WHEEL_ID
#define WHEEL_ID 0x4C    // default 'L'
#endif

static constexpr char WHEEL = static_cast<char>(WHEEL_ID);

// ── Serial CSV header (matches docs/ble-protocol.md §6) ──
static const char CSV_HEADER[] =
    "seq,wheel,timestamp_app_ms,timestamp_device_us,ax,ay,az,gx,gy,gz,marker\n";

// ── BLE task (runs on Core 1 via Arduino loop, not a separate FreeRTOS task) ──
// We call ble().bleTask() from loop() since Arduino loop is already on Core 1.
// This keeps BLE streaming separate from IMU acquisition (Core 0 esp_timer).

void setup() {
    M5.begin();

    // Serial debug
    Serial.begin(115200);
    delay(200);
    Serial.println("\n=== WheelAthlete Firmware (subtask #2+#3) ===");
    Serial.printf("Wheel: %c\n", WHEEL);

    // Initialize display
    display().begin();

    // Power up the MPU6886 via M5Unified (AXP192 power management on
    // M5StickCPlus2 must be enabled before any I2C traffic to the IMU).
    // M5.Imu.init() sends the standard init sequence; our ImuReader then
    // uses M5.Imu.update() + getImuData() to read float values and converts
    // them to raw int16 for the BLE packet.
    if (!M5.Imu.init()) {
        Serial.println("[FATAL] M5.Imu.init() failed — MPU6886 not detected");
        M5.Display.fillScreen(RED);
        M5.Display.setTextColor(WHITE);
        M5.Display.setCursor(10, 50);
        M5.Display.print("IMU FAIL");
        while (true) delay(1000);
    }
    Serial.println("[MAIN] M5.Imu.init() OK — MPU6886 powered up");

    // Initialize IMU reader (default 100 Hz, ±4g, ±2000 dps)
    if (!imu().begin()) {
        Serial.println("[FATAL] IMU init failed — check wiring");
        M5.Display.fillScreen(RED);
        M5.Display.setTextColor(WHITE);
        M5.Display.setCursor(10, 50);
        M5.Display.print("IMU FAIL");
        while (true) delay(1000);
    }

    // Initialize BLE GATT server
    ble().begin(WHEEL);

    // Print CSV header for serial debug
    Serial.print(CSV_HEADER);

    Serial.println("[MAIN] Setup complete — waiting for BLE START command");
}

void loop() {
    M5.update();

    // ── BLE tick: countdown beeps + scheduled start + drop count events ──
    ble().tick();

    // ── BLE streaming: drain queue → batch → notify ──
    ble().bleTask();

    // ── Serial CSV debug (drain any remaining samples if BLE not connected) ──
    if (!ble().connected()) {
        ImuSample s;
        while (imu().popSample(s)) {
            Serial.printf("%lu,%c,%lu,%lu,%d,%d,%d,%d,%d,%d,0\n",
                          static_cast<unsigned long>(s.seq),
                          WHEEL,
                          static_cast<unsigned long>(millis()),
                          static_cast<unsigned long>(s.t_device_us),
                          s.ax, s.ay, s.az,
                          s.gx, s.gy, s.gz);
        }
    }

    // ── Refresh display ──
    display().refresh(WHEEL,
                      imu().rateHz(),
                      imu().sampleCount(),
                      imu().dropCount(),
                      imu().fifoDepth(),
                      static_cast<uint8_t>(M5.Power.getBatteryLevel()),
                      imu().running());

    // ── Button A (M5 btn) = toggle start/stop (local, without BLE) ──
    if (M5.BtnA.wasPressed()) {
        if (imu().running()) {
            imu().stop();
            Serial.println("[MAIN] Acquisition stopped (BtnA)");
        } else {
            imu().start();
            Serial.println("[MAIN] Acquisition started (BtnA)");
        }
    }

    // ── Button B = cycle sample rate (50 → 100 → 200 → 50) ──
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
