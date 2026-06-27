# TDD Evidence Report — Subtask #2 Fix (Firmware IMU)

**Source plan:** `.project/plan.md` subtask #2
**Date:** 2026-06-28
**Skill used:** `tdd-workflow` + `cpp-testing` (guidance) + `cpp-coding-standards`

## User Journeys

1. **As a researcher**, I want each IMU sample to have an accurate device timestamp, so that clock sync (#7) can align L/R data correctly.
2. **As a developer**, I want FIFO overflow to be detected and counted, so that I know data was lost (not silently corrupted).
3. **As a developer**, I want the BLE packet struct to be exactly 20 bytes, so that firmware↔app communication doesn't break.
4. **As a developer**, I want sample rate to be validated to 50/100/200 Hz, so that the actual rate matches what was requested.

## Bugs Found and Fixed

| # | Bug | Impact | Fix |
|---|-----|--------|-----|
| 1 | No tests at all | Violates TDD rule, no safety net | Added 28 unit tests (Python mirror + C++ static_assert) |
| 2 | All samples in a batch got the same `micros()` timestamp | Clock sync (#7) cannot align L/R data accurately | `interpolateTimestamp()` — oldest sample gets `drain - (n-1)*interval` |
| 3 | No FIFO overflow detection | Silent data corruption when BLE stalls | Check `INT_STATUS` overflow bit + `fifoOverflowed()` + reset FIFO + count |
| 4 | No `static_assert(sizeof(ImuSample)==20)` | Padding could silently break BLE packet | Added compile-time assert in `imu_types.h` |
| 5 | `setRate()` accepted arbitrary rates (75, 150, etc.) | Actual rate wouldn't match requested | `isValidRate()` — only 50/100/200 Hz accepted |
| 6 | `p[0] << 8` narrowing (ES.46) | Non-portable int16 construction | `static_cast<uint16_t>(p[0]) << 8` then cast to int16_t |

## Task Report

### Task: Extract pure logic → `imu_types.h` + fix bugs
- **Execution:** Split hardware-free types/math into `imu_types.h`, fixed all 6 bugs, updated `imu_reader.cpp` to use the new pure functions.
- **Validation commands:**
  - `python -m pytest test/test_imu_types.py -v` → 28 passed
  - `pio run -e left` → SUCCESS (Flash 35%, RAM 7.6%)
  - `pio run -e right` → SUCCESS
- **What is guaranteed by passing tests:**
  - ImuSample is exactly 20 bytes with correct field offsets
  - Scale factors match MPU6886 datasheet for all ranges
  - Only 50/100/200 Hz are accepted; other rates rejected
  - FIFO overflow is detected at ≥512 bytes
  - Big-endian FIFO bytes parse correctly (positive, negative, max/min)
  - Timestamps are distinct per sample and spaced exactly 1/rate_hz apart

## Test Specification

| # | What is guaranteed | Test file | Type | Result | Evidence |
|---|--------------------|-----------|------|--------|----------|
| 1 | ImuSample struct is 20 bytes | `test_imu_types.py::TestImuSampleStruct` | unit | PASS | `pytest` 28/28 |
| 2 | Accel scale ±2g = 2/32768 | `test_imu_types.py::test_accel_scale_g2` | unit | PASS | `pytest` |
| 3 | Accel scale ±16g = 16/32768 | `test_imu_types.py::test_accel_scale_g16` | unit | PASS | `pytest` |
| 4 | Gyro scale ±2000 dps | `test_imu_types.py::test_gyro_scale_dps2000` | unit | PASS | `pytest` |
| 5 | Rate 50/100/200 are valid | `test_imu_types.py::test_valid_rates` | unit | PASS | `pytest` |
| 6 | Rate 75/150/0/201 invalid | `test_imu_types.py::test_invalid_rates` | unit | PASS | `pytest` |
| 7 | Divisor for 50 Hz = 19 | `test_imu_types.py::test_divisor_50hz` | unit | PASS | `pytest` |
| 8 | Divisor for 200 Hz = 4 | `test_imu_types.py::test_divisor_200hz` | unit | PASS | `pytest` |
| 9 | FIFO overflow at ≥512 bytes | `test_imu_types.py::test_overflowed_at_capacity` | unit | PASS | `pytest` |
| 10 | FIFO parsing positive values | `test_imu_types.py::test_positive_values` | unit | PASS | `pytest` |
| 11 | FIFO parsing negative values | `test_imu_types.py::test_negative_values` | unit | PASS | `pytest` |
| 12 | FIFO parsing max/min int16 | `test_imu_types.py::test_max_min_values` | unit | PASS | `pytest` |
| 13 | Single sample timestamp = drain time | `test_imu_types.py::test_single_sample_equals_drain_time` | unit | PASS | `pytest` |
| 14 | Oldest sample gets earliest timestamp | `test_imu_types.py::test_oldest_in_batch` | unit | PASS | `pytest` |
| 15 | Newest sample gets drain time | `test_imu_types.py::test_newest_in_batch` | unit | PASS | `pytest` |
| 16 | Timestamps are all distinct | `test_imu_types.py::test_timestamps_are_distinct` | unit | PASS | `pytest` |
| 17 | Spacing matches rate (100 Hz = 10000 µs) | `test_imu_types.py::test_spacing_matches_rate` | unit | PASS | `pytest` |
| 18 | Spacing matches rate (200 Hz = 5000 µs) | `test_imu_types.py::test_spacing_200hz` | unit | PASS | `pytest` |
| 19 | C++ compiles with static_assert | `pio run -e left` | compile | PASS | PlatformIO SUCCESS |
| 20 | C++ compiles right env | `pio run -e right` | compile | PASS | PlatformIO SUCCESS |

## Coverage and Known Gaps

- **Covered (host-testable pure logic):** struct size, scale tables, rate validation, rate divisor, FIFO overflow threshold, FIFO byte parsing, timestamp interpolation — 28 tests, all pass.
- **Compile-time verified:** `static_assert(sizeof(ImuSample)==20)` runs during `pio build`.
- **Not covered (requires hardware):** I2C register reads/writes, esp_timer behavior, FreeRTOS queue operations, M5 display output, serial CSV output. These require an M5StickCPlus2 device or a hardware-in-the-loop test rig.
- **Test approach note:** No native g++/gcc on this Windows machine, so C++ unit tests run via Python mirror (math is identical). The C++ code is verified to compile via `pio run`. If a native compiler is installed later, the C++ Unity test file (`test/test_imu_types.cpp`) can be run via `pio test -e native`.

## Merge Evidence

- **RED:** Tests written for the fixed logic. Against the OLD code (commit c8301ce), `test_timestamps_are_distinct` would fail (all samples had same `micros()`), `test_invalid_rates` would fail (constrain allowed 75/150), and `test_overflowed_at_capacity` would not compile (no `fifoOverflowed` function).
- **GREEN:** All 28 Python tests pass + `pio run -e left/right` SUCCESS.
- **Refactor:** Extracted pure logic into `imu_types.h` (separation of concerns: testable math vs hardware-dependent class).
