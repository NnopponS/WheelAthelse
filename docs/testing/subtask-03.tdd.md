# TDD Evidence Report — Subtask #3 (Firmware BLE GATT + Time-Sync)

**Source plan:** `.project/plan.md` subtask #3, `.project/prompts/subtask-03.md`
**Date:** 2026-06-28
**Skills used:** `cpp-coding-standards` + `cpp-testing` + `tdd-workflow` + `gateguard` + `intent-driven-development` + `latency-critical-systems`

## User Journeys

1. **As a researcher**, I want 2 M5 devices to stream IMU data via BLE to my phone, so that I can collect synchronized data from both wheels.
2. **As a developer**, I want sync_ping to respond with minimal latency, so that clock offset estimation is accurate.
3. **As a researcher**, I want scheduled synchronized start with countdown beeps, so that both wheels start at the same instant and the beep is recorded in video for alignment.
4. **As a developer**, I want the BLE packet format to match the protocol exactly, so that the Flutter app can parse it without errors.

## Acceptance Criteria (from intent-driven-development)

| AC | Description | Status |
|----|-------------|--------|
| AC-1 | GATT Service + 4 Characteristics (IMU/Control/Sync/Info) with correct UUIDs | ✅ |
| AC-2 | IMU Data batch notify: [count][sample_0]... little-endian, max batch from MTU | ✅ |
| AC-3 | Control commands: START/STOP/SET_RATE/SYNC_PING/SET_RANGE/BEEP/RESET_SEQ | ✅ |
| AC-4 | Sync Response: 12 bytes [t_app_ms][t_device_us][seq_ping], captured in callback | ✅ |
| AC-5 | Info: 16 bytes [wheel_id][fw][ranges][scales][reserved] | ✅ |
| AC-6 | Scheduled start: wait until micros >= target, beep 3-2-1, send START_FIRED | ✅ |
| AC-7 | Event notifications: SYNC_RESPONSE/DROP_COUNT/CMD_NACK/START_FIRED/STOP_FIRED | ✅ |
| AC-8 | All multi-byte fields little-endian (ESP32 native) | ✅ |

## Task Report

### Task: Implement BLE GATT server with IMU streaming + time-sync
- **Execution:** Created `ble_types.h` (pure logic) + `ble_service.h/.cpp` (NimBLE hardware layer). Updated `main.cpp` to wire BLE. Added NimBLE-Arduino dependency.
- **Validation commands:**
  - `python -m pytest test/ -v` → 62 passed (28 imu + 34 ble)
  - `pio run -e left` → SUCCESS
  - `pio run -e right` → SUCCESS
- **What is guaranteed by passing tests:**
  - BLE packet packing matches protocol (sample, batch, sync, events, info)
  - Batch size calculation correct for any MTU
  - Beep schedule fires 4 beeps in order (T-3, T-2, T-1, T-0)
  - Scheduled start waits correctly, fires at target time
  - All fields little-endian, correct sizes

## Test Specification

| # | What is guaranteed | Test file | Type | Result |
|---|--------------------|-----------|------|--------|
| 1 | IMU sample = 20 bytes LE | test_ble_types.py::TestPackSample | unit | PASS |
| 2 | Batch = [count][samples] | test_ble_types.py::TestPackBatch | unit | PASS |
| 3 | Max batch = floor((MTU-4)/20) | test_ble_types.py::TestMaxBatchCount | unit | PASS |
| 4 | Sync response = 12 bytes | test_ble_types.py::TestSyncResponse | unit | PASS |
| 5 | START_FIRED event = [0x30][uint32] | test_ble_types.py::TestSyncEvents | unit | PASS |
| 6 | STOP_FIRED event = [0x40][uint32][uint32] | test_ble_types.py::TestSyncEvents | unit | PASS |
| 7 | Info = 16 bytes with all fields | test_ble_types.py::TestInfoCharacteristic | unit | PASS |
| 8 | Beep fires at T-3,T-2,T-1,T-0 in order | test_ble_types.py::TestBeepSchedule | unit | PASS |
| 9 | Scheduled start waits for target | test_ble_types.py::TestScheduledStart | unit | PASS |
| 10 | C++ compiles left/right | pio run -e left/right | compile | PASS |

## Coverage and Known Gaps

- **Covered (host-testable pure logic):** 62 tests covering packet packing, batch sizing, sync response, events, info, beep schedule, scheduled start
- **Compile-time verified:** static_assert(sizeof(ImuSample)==20)
- **Not covered (requires hardware):** NimBLE GATT interaction, actual BLE notify delivery, I2C + FIFO hardware, M5.Speaker buzzer, FreeRTOS queue timing. These require an M5StickCPlus2 device.
- **Latency-critical note:** sync_ping response captures `micros()` directly in the NimBLE write callback — this is the shortest possible path. No queue or task dispatch in between.

## Merge Evidence

- **RED:** Tests written for ble_types.h pure logic before implementing ble_service.cpp
- **GREEN:** 62/62 tests pass + pio run left/right SUCCESS
- **Refactor:** Pure logic separated into ble_types.h (testable) from ble_service.cpp (hardware-dependent)
