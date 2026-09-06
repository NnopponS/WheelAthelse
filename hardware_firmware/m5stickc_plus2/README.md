# WheelAthlete M5StickC Plus2 Firmware

Firmware for the **M5StickC Plus2 / ESP32** WheelAthlete sensor node.

This target implements the same WheelAthlete BLE wire and acquisition-lifecycle contract used by the XIAO nRF52840 Sense firmware. It is intended to work with both maintained operator applications without client-specific firmware branches:

- `applications/wheelathlete_mobile/` — WheelAthlete Mobile Application
- `applications/wheelathlete_windows/` — WheelAthlete Windows Research Application

The Windows Python application does not require M5-specific changes. The M5 identifies itself through Info `hardware_model = 1`; XIAO uses model `2`.

## Hardware

- M5StickC Plus2 / ESP32
- MPU6886 IMU
- M5 display, buttons, battery/power subsystem, and speaker

## Runtime architecture

- MPU6886 acquisition uses the hardware FIFO and a dedicated FreeRTOS producer task.
- BLE ownership runs separately from IMU acquisition.
- IMU data is batched according to negotiated MTU and streamed through the standard WheelAthlete IMU characteristic.
- The PC/mobile central owns START/STOP/rate lifecycle while BLE is connected. Local buttons cannot bypass the connected central's acquisition lifecycle.

## PC/XIAO protocol parity

The M5 firmware implements the same client-visible contract as the current XIAO firmware:

- WheelAthlete service and IMU / Control / Sync / Info / Config characteristics
- standard Battery Service
- 50 / 100 / 200 Hz configuration
- Info and Config payloads compatible with the Python acquisition service
- write-with-response compatible Control characteristic
- clock `SYNC_PING` / `SYNC_RESPONSE`
- common-device-time scheduled START
- `START_FIRED` and `STOP_FIRED`
- countdown cue event
- 28-byte `ACQ_HEALTH`
- sequence/drop accounting
- bounded replay with `REPLAY_RANGE` / `REPLAY_RESULT`
- configurable accelerometer/gyroscope ranges
- board name, wheel identity, UTC, beep, and countdown-sound configuration

A new BLE connection forces acquisition to idle and clears stale queue/sequence state. Accepting a START command also begins a fresh sequence epoch before waiting for a scheduled T0. This matches the lifecycle behavior expected by the existing Python Windows acquisition stack.

M5 retains hardware-specific FIFO fault/drop telemetry because the MPU6886 implementation has a real hardware FIFO. XIAO reports the same wire fields with zero FIFO values.

## Build

From this directory:

```bash
pio run -e left
pio run -e right
```

Flash the required wheel identity explicitly:

```bash
pio run -e left -t upload
pio run -e right -t upload
```

Do not flash both physical boards with the same wheel environment.

## Tests

Host-side firmware contract tests:

```bash
python -m pytest test -q
pio test -e native
```

The `test_pc_python_parity.py` contract protects the client-visible M5 behavior required by the existing Python Windows application while treating the current XIAO firmware as the reference behavior.

## BLE protocol

The canonical wire specification is:

`../../docs/ble-protocol.md`

Coordinated firmware version: `1.8.0`.
