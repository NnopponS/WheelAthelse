// main.cpp — Seeed Xiao BLE Sense firmware entry point
//
// Runs BLE stack, config store, and IMU acquisition task.
// Uses Red and Blue LEDs for connection, countdown, and recording status.

#include <Arduino.h>
#include "imu_reader.h"
#include "ble_service.h"
#include "config_store.h"

using namespace WheelAthlete;

// ── Build-time wheel identity (from platformio.ini build_flags) ──
#ifndef WHEEL_ID
#define WHEEL_ID 0x4C    // default 'L' (ASCII 76)
#endif

static constexpr char WHEEL = static_cast<char>(WHEEL_ID);

void setup() {
    Serial.begin(115200);
    delay(500);

    // Initialize LED pins (active LOW on Xiao BLE Sense)
    pinMode(LED_RED, OUTPUT);
    pinMode(LED_BLUE, OUTPUT);
    pinMode(LED_GREEN, OUTPUT);
    digitalWrite(LED_RED, HIGH);   // OFF
    digitalWrite(LED_BLUE, HIGH);  // OFF
    digitalWrite(LED_GREEN, HIGH); // OFF

    Serial.println("\n=== WheelAthlete Firmware (Xiao BLE Sense) ===");
    Serial.printf("Wheel: %c\n", WHEEL);

    // Initialize configuration store (NVS equivalent using LittleFS on nRF52)
    configStore().begin(WHEEL);

    // Initialize IMU reader (LSM6DS3)
    if (!imu().begin(configStore().rateHz())) {
        Serial.println("[FATAL] IMU init failed — LSM6DS3 not detected");
        // Fast Red flash to indicate hardware failure
        while (true) {
            digitalWrite(LED_RED, LOW);
            delay(100);
            digitalWrite(LED_RED, HIGH);
            delay(100);
        }
    }

    // Apply persisted sample rate
    if (imu().rateHz() != configStore().rateHz()) {
        imu().setRate(configStore().rateHz());
    }

    // Initialize BLE GATT server
    ble().begin(WHEEL);

    Serial.println("[MAIN] Setup complete — waiting for BLE START command");
}

void loop() {
    // BLE tick: countdown blinks + scheduled start + battery updates
    ble().tick();

    // BLE streaming: drain queue → batch → notify
    ble().bleTask();

    // Serial CSV debug: drain remaining samples if BLE is not connected
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

    delay(2);   // Small yield
}
