# WheelAthlete

**IMU-based wheelchair motion data collection system** — captures raw accelerometer + gyroscope data from both wheelchair wheels and synchronizes it with a video gold standard, replacing multi-camera 3D motion capture.

> **Status:** `v0.1.0` — Data Collection MVP (pre-release)
> **Languages:** [English](README.md) · [ภาษาไทย](README.th.md)

---

## Table of Contents

- [Overview](#overview)
- [What's Working in v0.1.0](#whats-working-in-v010)
- [What's NOT in v0.1.0](#whats-not-in-v010)
- [Architecture](#architecture)
- [Hardware Requirements](#hardware-requirements)
- [Repository Layout](#repository-layout)
- [Build & Flash — Firmware](#build--flash--firmware)
- [Build & Run — Mobile App](#build--run--mobile-app)
- [Data Format](#data-format)
- [Time Synchronization](#time-synchronization)
- [BLE Protocol](#ble-protocol)
- [Field Data Collection Protocol](#field-data-collection-protocol)
- [Testing](#testing)
- [Roadmap](#roadmap)
- [License](#license)

---

## Overview

WheelAthlete turns two cheap M5StickCPlus2 modules into a research-grade IMU
acquisition rig for wheelchair sports biomechanics. Each module mounts on one
wheel and streams synchronized 6-axis IMU data over BLE to a Flutter app. The
app records sessions, computes quality metrics, and exports CSV/Excel for
later model training.

The system replaces expensive 3D motion capture setups with a portable,
battery-powered kit that fits in a small bag. A single phone acts as the
common time reference for both wheels, eliminating the need for NTP or RTC
hardware.

```
  [Left wheel]                [Right wheel]
 M5StickCPlus2 (L)           M5StickCPlus2 (R)
  MPU6886 IMU                 MPU6886 IMU
   │ accel xyz, gyro xyz       │ accel xyz, gyro xyz
   │ @ 50/100/200 Hz           │ @ 50/100/200 Hz
   └────── BLE GATT ────┐  ┌── BLE GATT ──────┘
                        ▼  ▼
                ┌──────────────────────┐
                │   Flutter App         │
                │  (iOS + Android)      │
                │  - BLE manager (x2)   │
                │  - Clock sync engine  │
                │  - Recorder + preview │
                │  - CSV/Excel export   │
                └───────────┬───────────┘
                            │
                            ▼
                      session_*.csv
                            │
              (future phase) ─► Python: train model
                            ▲
              Camera (gold standard) recorded separately
              → aligned later via beep 3-2-1 + mark events
```

---

## What's Working in v0.1.0

This is the first usable release. It is a **data collection MVP** — the app
captures, syncs, previews, and exports. It does **not** train or run any
machine-learning model yet.

### Firmware (M5StickCPlus2)
- MPU6886 IMU acquisition via hardware data-ready interrupt + FIFO
- Configurable sampling rate: 50 / 100 / 200 Hz
- BLE GATT server (NimBLE) with 5 characteristics + standard Battery Service
- Batched IMU notify (up to 12 samples per packet at MTU 247)
- Control commands: START, STOP, SET_RATE, SYNC_PING, SET_RANGE, BEEP,
  SET_NAME, SET_WHEEL, SET_UTC, RESET_SEQ
- Scheduled synchronized start with countdown beep 3-2-1
- On-device display: connection state, recording, battery, sample count
- Board identity (L/R) configurable at build time or at runtime via BLE
- Persistent config store (name, wheel side, ranges) in NVS
- Firmware version 0.2.0

### Mobile App (Flutter, iOS + Android)
- BLE scan + connect to two M5StickCPlus2 modules simultaneously
- Automatic L/R side assignment from board Info characteristic
- Clock sync engine (NTP/PTP-lite over BLE): offset estimation + drift
  correction → common timeline in UTC milliseconds
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
- App version 1.0.0+1

### Documentation
- BLE protocol spec (`docs/ble-protocol.md`) — single source of truth
- Field data collection protocol (`docs/data-collection-protocol.md`)
- Architecture docs in `.project/` (Phase 1, 3, 4)

---

## What's NOT in v0.1.0

- No machine-learning model training or inference
- No real-time biomechanical feedback to the athlete
- No cloud sync or server backend (all data stays on-device)
- No automated video↔IMU alignment (manual via beep + mark events)
- No multi-athlete/session comparison dashboard
- Firmware has no OTA update (flash via USB only)

These are planned for later phases — see [Roadmap](#roadmap).

---

## Architecture

The system has three layers:

### 1. Firmware (ESP32, Core 0 + Core 1)
- **Core 0:** IMU acquisition — data-ready ISR drains MPU6886 FIFO into a
  FreeRTOS queue. Sampling interval is hardware-timed, immune to BLE jitter.
- **Core 1:** BLE task batches queue contents and notifies the app. If BLE
  stalls, the queue fills and `drop_count` is reported via Sync events.
- Pure logic (packet layout, scale tables, rate math) lives in
  `imu_types.h` / `ble_types.h` and is host-testable without hardware.

### 2. Mobile App (Flutter + Riverpod)
- **BLE layer** (`lib/ble/`): abstract `BleRepository` + `FlutterBluePlusBleRepository`
  adapter. Fake implementation for unit tests.
- **State layer** (`lib/state/`): Riverpod 3.x Notifiers for connection, IMU
  stream, clock sync, recording, preview, browse, protocol templates.
- **Records layer** (`lib/records/`): session model, storage repository,
  protocol templates, session stats, quality badges.
- **Export layer** (`lib/export/`): CSV + Excel exporters, resampler, share.
- **UI layer** (`lib/ui/`): Connect, Live, Record, Browse, Session Preview,
  Experiment Tracker, Board Settings, Tag Editor.
- **Theme** (`lib/theme/`): custom design system — palette, typography
  (Inter + JetBrains Mono for tabular metrics), WheelAthleteColors
  ThemeExtension (L=blue, R=orange), light + dark high-contrast.

### 3. Data
- Sessions stored on-device under `WheelAthleteData/<topic>/trial_<NN>/`.
- Each session = one CSV + one `session_<id>_meta.json`.
- Protocol templates stored in `protocols.json` alongside the data root.

Full architecture docs:
- `.project/architecture.md` — Phase 1 (data collection core)
- `.project/architecture-phase3.md` — Phase 3 (browse + protocol templates)
- `.project/architecture-phase4.md` — Phase 4 (session preview + quality)

---

## Hardware Requirements

| Item | Qty | Notes |
|------|-----|-------|
| M5StickCPlus2 | 2 | Left + Right wheel |
| USB-C cable | 2 | For charging + flashing |
| Power bank | 1 | For sessions longer than ~30 min (M5 battery ~80 mAh) |
| iOS or Android phone | 1 | Runs the WheelAthlete app |
| Video camera (gold standard) | 1 | 60+ fps recommended, with microphone |
| Tripod | 1 | Optional but recommended |
| 3M VHB double-sided tape or strap | — | To mount M5 on wheel hub/spoke |
| L/R labels | 2 | Stick on each M5 for clarity |

---

## Repository Layout

```
WheelAthlete/
├── firmware/                 # PlatformIO project (M5StickCPlus2, ESP32)
│   ├── platformio.ini        # envs: left, right, native (host tests)
│   ├── src/
│   │   ├── main.cpp          # Entry point + task scheduling
│   │   ├── imu_types.h       # Pure logic: sample struct, scales, rate math
│   │   ├── imu_reader.{h,cpp}# MPU6886 FIFO + data-ready acquisition
│   │   ├── ble_types.h       # Pure logic: packet layout, command parsing
│   │   ├── ble_service.{h,cpp}# NimBLE GATT server
│   │   ├── config_store.{h,cpp}# NVS persistent config
│   │   ├── display.{h,cpp}   # M5 LCD status rendering
│   ├── test/                 # Unity host tests (env: native)
│   └── README.md
├── app/                      # Flutter project (iOS + Android)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── ble/              # BLE repository, packet parser, device info
│   │   ├── state/            # Riverpod providers + clock sync engine
│   │   ├── records/          # Session model, storage, stats, quality, protocols
│   │   ├── export/           # CSV + Excel exporters, resampler, share
│   │   ├── ui/               # Connect, Live, Record, Browse, Preview, etc.
│   │   ├── widgets/          # Reusable components (chart, cards, badges)
│   │   └── theme/            # Design system (palette, typography, themes)
│   ├── test/                 # Unit + widget tests
│   ├── pubspec.yaml
│   └── README.md
├── docs/
│   ├── ble-protocol.md              # BLE contract (firmware ↔ app)
│   ├── data-collection-protocol.md # Field procedure
│   └── testing/                     # TDD evidence reports
├── tools/                    # Helper scripts
├── .project/                 # Cross-session plans, architecture, progress
├── README.md                 # This file (English)
├── README.th.md              # Thai version
└── .gitignore
```

---

## Build & Flash — Firmware

Requires [PlatformIO](https://platformio.org/) (VS Code extension or CLI).

```bash
cd firmware

# Build for each wheel
pio run -e left          # build left wheel firmware
pio run -e right         # build right wheel firmware

# Flash to M5StickCPlus2 (connect via USB-C first)
pio run -e left -t upload     # flash left M5
pio run -e right -t upload    # flash right M5

# Monitor serial debug output
pio device monitor

# Run host-side pure-logic tests (no hardware needed)
pio run -e native            # build native test env
pio test -e native           # run Unity tests
```

Build flags set `WHEEL_ID` per env:
- `env:left`  → `WHEEL_ID=0x4C` ('L')
- `env:right` → `WHEEL_ID=0x52` ('R')

Wheel side can also be changed at runtime via the `SET_WHEEL` BLE command
(persisted to NVS by `config_store`).

Firmware version is defined in `platformio.ini`:
`WheelAthlete_FW_MAJOR=0`, `WheelAthlete_FW_MINOR=2`, `WheelAthlete_FW_PATCH=0`.

---

## Build & Run — Mobile App

Requires [Flutter](https://flutter.dev/) 3.x with a connected device or emulator.

```bash
cd app

flutter pub get
flutter run -d <device-id>          # run on phone/emulator
flutter test                        # run all unit + widget tests
flutter analyze                     # static analysis (strict config)

# Build release artifacts
flutter build apk --release         # Android APK
flutter build appbundle --release   # Android App Bundle
flutter build ios --release         # iOS (requires macOS + Xcode)
```

Key dependencies (see `pubspec.yaml` for full list):
- `flutter_blue_plus ^2.3.9` — BLE
- `flutter_riverpod ^3.3.2` — state management
- `fl_chart ^1.2.0` — charts
- `csv ^8.0.0`, `excel ^4.0.6` — export
- `share_plus ^13.2.0`, `path_provider ^2.1.6` — file sharing
- `file_picker 12.0.0-beta.7` — directory picker (pinned for share_plus compat)

App version: `1.0.0+1` (defined in `pubspec.yaml`).

---

## Data Format

Each session produces two files under
`WheelAthleteData/<topic>/trial_<NN>/`:

### `session_<id>.csv`
CSV with separate Left and Right tables. Columns:

| Column | Type | Meaning |
|--------|------|---------|
| `seq` | uint32 | Sample sequence from firmware (detects packet loss) |
| `wheel` | char | `L` or `R` |
| `timestamp_app_ms` | uint64 | Phone epoch ms when sample received (has BLE jitter) |
| `timestamp_device_us` | uint32 | `micros()` on M5 when sampled |
| `timestamp_synced_ms` | uint64 | **UTC epoch ms after offset/drift correction** — primary key for cross-wheel + camera alignment |
| `ax, ay, az` | float | Acceleration in g (raw × accel_scale) |
| `gx, gy, gz` | float | Gyro in dps (raw × gyro_scale) |
| `marker` | 0/1 | 1 = Mark Event pressed (legacy; always 0 in v0.1.0) |

### `session_<id>_meta.json`
Session metadata: athlete, datetime, sample rate, sync quality
(offset + drift residual RMS per wheel), drop count, notes, camera video
filename, tags, `protocolTemplateId`.

### `protocols.json`
Protocol templates with `id`, `name`, `description`, `topicName`,
`targetTrialCount`, `sampleRateHz`, `createdAt`.

---

## Time Synchronization

Two M5StickCPlus2 modules have independent `micros()` clocks that drift.
BLE notify latency varies per connection. Using raw phone timestamps is not
accurate enough for cross-wheel alignment.

**Solution:** the phone is the common reference (it talks to both wheels
already). The app runs an NTP/PTP-lite estimation over BLE:

1. **Offset estimation** — app sends `SYNC_PING` with `t_app_ms`; firmware
   echoes `t_device_us`. App measures round-trip and keeps the lowest-RTT
   sample to estimate clock offset.
2. **Drift correction** — multiple `(t_device_us, t_app_ms)` pairs are fit
   linearly; slope = drift rate. Every sample is mapped to
   `timestamp_synced_ms` on the common UTC timeline.
3. **Scheduled synchronized start** — app computes `T_start = now + 5s`,
   converts to each wheel's local `micros()`, and sends `START` with
   `target_start_us`. Both wheels begin acquisition at the same instant on
   the phone timeline (jitter = offset error only, typically < 1 sample).
4. **Beep 3-2-1 audio marker** — during countdown, both M5 speakers beep at
   T-3s, T-2s, T-1s, T-0. The beeps are recorded by the camera and align
   video↔IMU without needing to tap the wheel.

Sync quality is reported as **drift residual RMS in ms**:
- `< 2 ms` → good (green)
- `2–5 ms` → fair (amber)
- `> 5 ms` → poor (red)
- `null`  → unknown (grey)

---

## BLE Protocol

Full contract: [`docs/ble-protocol.md`](docs/ble-protocol.md) (version 1.1.0).

Summary:

| Characteristic | UUID suffix | Properties | Direction | Purpose |
|---|---|---|---|---|
| IMU Data | `a1b3` | Notify | FW → App | Batched IMU samples (20 B each) |
| Control | `a1b4` | Write | App → FW | Commands (START, STOP, SET_RATE, ...) |
| Sync | `a1b5` | Notify + Indicate | FW → App | Sync responses + events |
| Info | `a1b6` | Read | FW → App | Wheel ID, firmware version, ranges, scales |
| Config | `a1b7` | Read | FW → App | Board name, wheel ID, persisted settings |
| Battery Level | `2a19` | Read + Notify | FW → App | Standard Battery Service (0x180F) |

Service UUID: `0000a1b2-0000-1000-8000-00805f9b34fb`

The protocol doc is the single source of truth — firmware and app must both
implement it exactly. Changes require updating the doc first.

---

## Field Data Collection Protocol

Step-by-step field procedure: [`docs/data-collection-protocol.md`](docs/data-collection-protocol.md).

Quick summary:
1. Charge both M5 modules and flash latest firmware.
2. Mount M5 on each wheel hub (Z axis perpendicular to wheel plane).
3. Open the app → Connect tab → scan + connect both wheels.
4. Wait for clock sync to settle (residual < 2 ms).
5. Pick a protocol template (or custom topic) on the Record tab.
6. Start the camera **before** pressing Start in the app.
7. Press Start → 5-second countdown + beep 3-2-1 → recording begins.
8. During recording, watch realtime metrics. (Mark Event is removed in
   v0.1.0 — beep + camera audio is the sync source.)
9. Press Stop → session saved → preview page shows stats + charts.
10. Export CSV/Excel from Browse or the preview page. Share via OS sheet.

---

## Testing

### Firmware
- Host-side Unity tests (`pio test -e native`) cover pure logic in
  `imu_types.h` and `ble_types.h`: struct sizes, scale tables, rate math,
  FIFO byte parsing, timestamp interpolation, packet layout, command parsing.
- Python unit tests (`firmware/test/test_imu_types.py`,
  `test_ble_types.py`) mirror the C++ tests for fast iteration.

### App
- Unit tests for BLE parsing, clock sync, recording, storage, stats, quality
  badges, protocol templates, export.
- Widget tests for every reusable component and page.
- `flutter analyze` runs under strict config (strict-casts, strict-inference,
  raw-types, unawaited_futures = error).
- Coverage reports in `docs/testing/`.

---

## Roadmap

### Done in v0.1.0
- Phase 1: Data collection + calibration (firmware + app + CSV export)
- Phase 3: Browse, protocol templates, experiment tracker, session tags
- Phase 4: Session preview page, quality badges, Excel export, UTC alignment

### Planned (not in this release)
- **Phase 5:** Python pipeline — load CSV, feature extraction, train
  classification/regression model for biomechanical metrics.
- **Phase 6:** Real-time feedback to athlete during training.
- **Phase 7:** Cloud sync + multi-athlete dashboard.
- **Phase 8:** Automated video↔IMU alignment (beep detection + visual marker).
- **OTA firmware updates** over BLE.
- **Multi-wheel support** (4 wheels for court sports).

---

## License

Proprietary — all rights reserved. See repository settings on GitHub.
This is a research project; contact the maintainer before reuse.

---

**Release:** `v0.1.0` (pre-release) · **Firmware:** `0.2.0` · **App:** `1.0.0+1`
