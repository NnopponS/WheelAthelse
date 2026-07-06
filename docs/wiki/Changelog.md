# Changelog

All notable changes to WheelAthlete are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/).

## [v0.1.0] — 2026-07-06 (pre-release)

First usable release. Data collection MVP — captures synchronized IMU
data from two wheelchair wheels, with clock sync, session preview,
quality badges, and CSV/Excel export. **No ML model training or inference
yet.**

### Firmware (0.2.0)
#### Added
- MPU6886 IMU acquisition via hardware data-ready interrupt + FIFO
- Configurable sampling rate: 50 / 100 / 200 Hz
- BLE GATT server (NimBLE) with 5 characteristics:
  - IMU Data (Notify), Control (Write), Sync (Notify+Indicate),
    Info (Read), Config (Read)
- Standard Battery Service (0x180F) with Battery Level (Notify)
- Batched IMU notify (up to 12 samples per packet at MTU 247)
- Control commands: START, STOP, SET_RATE, SYNC_PING, SET_RANGE, BEEP,
  SET_NAME, SET_WHEEL, SET_UTC, RESET_SEQ
- Scheduled synchronized start with countdown beep 3-2-1
- On-device display: connection, recording, battery, sample count
- Board identity (L/R) configurable at build time or runtime
- Persistent config store (name, wheel side, ranges) in NVS
- `CMD_NACK` response for unknown commands
- `UTC_SET` event for `SET_UTC` command
- `DROP_COUNT` event for queue overflow reporting

#### Fixed
- All samples in a batch got the same `micros()` → interpolated per-sample
- FIFO overflow not detected → now checks `INT_STATUS` + byte count ≥ 512
- Rate validation accepted arbitrary rates → only 50/100/200 Hz
- ES.46 narrowing in FIFO byte parsing

### App (1.0.0+1)
#### Added
- BLE scan + connect to two M5StickCPlus2 modules simultaneously
- Automatic L/R side assignment from board Info characteristic
- Clock sync engine (NTP/PTP-lite over BLE): offset + drift correction
  → common UTC timeline in milliseconds
- Realtime IMU display (6 metrics per wheel + sample/drop counts)
- Recording with synchronized start, countdown, and beep
- Session storage organized by topic → trial → session
- Protocol templates with target trial count (experiment tracker dashboard)
- Session tags + search/filter on Browse
- Session preview page: scrub slider, accel/gyro charts, summary stats
- Quality badges (good / fair / poor / unknown) from drift residual RMS
- Export to CSV (separate L/R tables) and Excel (.xlsx)
- Share exported files via OS share sheet
- Light + dark theme, designed for outdoor sunlight readability
- Custom design system (palette, typography, WheelAthleteColors
  ThemeExtension, reusable components)
- Delete at topic / trial / session levels with confirmation dialogs
- Quick re-record from stopped view
- Sample chunk reader for lazy loading in preview
- Session stats computation (mean/peak accel + gyro magnitude)
- UTC millisecond alignment for cross-wheel + cross-camera sync
- Board settings page (rename board, change wheel side)

#### Changed
- CSV format: separate L/R tables (was single combined table)
- Mark Event removed from recording UI (beep + camera audio replaces it)
  - `marker` column preserved in CSV for backward compatibility (always 0)
- Experiments tab merged into Browse (Phase 4)

#### Fixed
- Two-board signal drops from unthrottled IMU/recording state emissions
  → throttled emissions + `.select` to eliminate rebuilds
- Board settings save reliability improvements
- `UnmountedRefException` on async state set after dispose → `ref.mounted`
  guards
- `pumpAndSettle` timeout from infinite spinner animation
- `flutter_blue_plus` 2.x API drift (Guid, License, states)
- `servicesStream` deprecated in fbp 2.x → `servicesList + lastValueStream`

### Documentation
#### Added
- BLE protocol spec (`docs/ble-protocol.md`) v1.1.0
- Field data collection protocol (`docs/data-collection-protocol.md`)
- Bilingual README (English + Thai)
- Wiki pages in `docs/wiki/` (Home, Architecture, BLE-Protocol,
  Data-Format, Time-Sync, Build-Guide, Field-Protocol, Testing, Roadmap,
  Changelog)
- Architecture docs for Phase 1, 3, 4 in `.project/`
- TDD evidence reports in `docs/testing/`

### Testing
- Firmware: 62+ host-side tests (Unity + Python)
- App: 200+ unit + widget tests
- Strict analysis config (`strict-casts`, `strict-inference`,
  `unawaited_futures: error`, etc.)
- `flutter analyze` clean

### Known limitations
- No ML model training or inference
- No real-time biomechanical feedback
- No cloud sync or server backend
- No automated video↔IMU alignment (manual via beep + mark events)
- No OTA firmware updates (flash via USB only)
- No multi-athlete/session comparison dashboard
- No CI/CD pipeline (tests run locally)

### Version tracks
- App: `1.0.0+1`
- Firmware: `0.2.0`
- BLE Protocol: `1.1.0`
