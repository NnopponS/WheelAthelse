# WheelAthlete firmware

WheelAthlete v1.8.2 maintains two sensor firmware targets that share the BLE 1.8.0 protocol contract.

| Directory | Hardware | Supported roles |
|---|---|---|
| [`m5stickc_plus2/`](m5stickc_plus2/) | M5StickC Plus2 / ESP32 | L, R, optional C |
| [`xiao_nrf52840_sense/`](xiao_nrf52840_sense/) | Seeed XIAO nRF52840 Sense / LSM6DS3 | L, R, optional C |

Role identity is `L=0x4C`, `R=0x52`, `C=0x43`. The optional chair-center C mounting contract is **+Z down toward the floor**. XIAO C uses green identity/heartbeat; M5 C retains its yellow display identity.

Build output under `.pio/` is generated and must not be committed. A successful compile is a software/build result only; flashing, RF behavior, physical orientation and synchronized L/R/C integrity require separate hardware acceptance.

Canonical wire semantics: [`../docs/ble-protocol.md`](../docs/ble-protocol.md).
