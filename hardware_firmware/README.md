# WheelAthlete Hardware & Firmware

This directory contains the maintained embedded firmware targets for WheelAthlete dual-wheel IMU sensors.

| Directory | Official firmware name | Target |
|---|---|---|
| `m5stickc_plus2/` | **WheelAthlete M5StickC Plus2 Firmware** | M5StickC Plus2 / ESP32 |
| `xiao_nrf52840_sense/` | **WheelAthlete XIAO nRF52840 Sense Firmware** | Seeed Studio XIAO nRF52840 Sense |

Both targets implement the same left/right WheelAthlete BLE protocol defined in [`docs/ble-protocol.md`](../docs/ble-protocol.md).

See the repository-level [`README.md`](../README.md) or [`README.th.md`](../README.th.md) for build, flash, synchronization, and version information.