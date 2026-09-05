# WheelAthlete

**Dual-wheel IMU data collection for wheelchair sports research.** WheelAthlete captures synchronized accelerometer and gyroscope data from left/right wheel sensors and provides two operator applications: a Flutter mobile app and a reliability-focused Python Windows app.

> **Current release line:** `v1.8.0`
> **Mobile:** `1.8.0+9` · **Firmware:** `1.8.0` · **BLE protocol:** `1.8.0` · **Windows package:** `1.8.0`
> **Languages:** [English](README.md) · [ภาษาไทย](README.th.md)

## Current products

WheelAthlete intentionally has **two user-facing applications only**:

| Product | Platform | Runtime | BLE ownership | Primary storage |
|---|---|---|---|---|
| Mobile App | iOS + Android | Flutter / Dart | App owns BLE directly | Mobile session CSV + metadata |
| Windows App | Windows 10/11 | Python / PySide6 | Acquisition daemon owns BLE | Append-only `.waj` journal + derived CSV |

The retired Flutter Windows application, Flutter Web scaffold, and legacy Tkinter/Matplotlib desktop GUI are not part of the current source tree.

## System overview

Both clients use the same firmware BLE contract. Use one operator client at a time with a given sensor pair.

```text
     Left wheel sensor                    Right wheel sensor
  M5StickCPlus2 / XIAO                 M5StickCPlus2 / XIAO
           │                                   │
           └────────────── BLE GATT ───────────┘
                            │
               ┌────────────┴────────────┐
               │                         │
               ▼                         ▼
      Flutter Mobile App        Python Windows App
        iOS / Android              PySide6 GUI
        direct BLE I/O                  │
               │                  localhost IPC
               │                        │
               │                 Acquisition daemon
               │                 Bleak / WinRT BLE
               ▼                        ▼
      CSV + metadata           authoritative .waj journal
      preview + export         QC + recovery + CSV export
```

### Firmware

Two maintained targets implement the same protocol:

- `M5plus2_firmware/` — M5StickCPlus2 / ESP32
- `Xiao_firmware/` — Seeed XIAO nRF52840 Sense

Core capabilities include left/right identity, 50/100/200 Hz sampling, synchronized lifecycle commands, sensor-range configuration, battery information, replay/recovery support, sequence accounting, and acquisition-health telemetry.

### Flutter mobile app

Location: `app/`

Key capabilities:

- connect left/right BLE boards simultaneously;
- realtime Accel XYZ + Gyro XYZ display;
- clock synchronization and synchronized recording start;
- topic/trial/session organization;
- protocol templates, experiment tracking, tags, search/filter;
- session preview, QC/quality indicators, and statistics;
- CSV/Excel/ZIP export and OS sharing;
- mobile-only runtime target: Android + iOS.

### Python Windows app

Locations: `tools/pc_gui/` + `tools/pc_acquisition/`

The PySide6 UI is deliberately separated from the authoritative raw-data path. The acquisition daemon owns BLE, strict packet parsing, sequence/loss accounting, synchronization, `.waj` journal writes, final QC, and crash recovery. The GUI receives bounded preview/status traffic over localhost IPC.

This means a slow chart or restarted GUI cannot silently become the raw BLE storage bottleneck.

Windows UI includes Dashboard, Live, Record, Experiments, Sessions, and Diagnostics. See [`tools/pc_gui/README.md`](tools/pc_gui/README.md) for the detailed workflow.

## Repository layout

```text
WheelAthelse/
├── app/                         # Flutter mobile app — iOS + Android
├── M5plus2_firmware/            # M5StickCPlus2 firmware
├── Xiao_firmware/               # XIAO nRF52840 Sense firmware
├── tools/
│   ├── pc_acquisition/          # Windows authoritative BLE/recording daemon
│   ├── pc_gui/                  # PySide6 Windows operator UI
│   ├── check_session.py         # Session validation helper
│   └── process_dataset.py       # Dataset processing helper
├── packaging/
│   └── windows/                 # PyInstaller + Inno Setup build sources
├── docs/
│   ├── ble-protocol.md          # Canonical BLE contract
│   ├── data-collection-protocol.md
│   ├── testing/                 # Verification evidence
│   └── wiki/                    # Longer-form project documentation
├── assets/                      # Product icons/logo
├── .project/                    # Canonical current project state only
├── run_python_pc_app.bat        # Windows source launcher
├── VERSION                      # Coordinated semantic product version
├── README.md
└── README.th.md
```

`build/`, `release/`, Flutter generated files, PlatformIO `.pio/`, and collected session data are intentionally untracked.

## Quick start — Windows Python app

From the repository root:

```bat
run_python_pc_app.bat
```

The launcher checks the Python UI dependencies and starts `tools.pc_gui`. In normal mode the GUI starts or reuses the local acquisition daemon automatically.

Demo UI without physical boards:

```bat
run_python_pc_app.bat --demo
```

Demo mode is visibly labeled and does not create synthetic research evidence.

Default Windows data locations:

- Sessions: `~/Documents/WheelAthlete/PC Sessions`
- GUI log: `~/Documents/WheelAthlete/Logs/python-pc-app.log`
- Experiment presets: `~/Documents/WheelAthlete/experiments.json`

## Build Windows portable EXE + installer

Prerequisites: Python, PyInstaller, and Inno Setup 6.

```bat
packaging\windows\build_installer.bat
```

Outputs are generated under ignored `release/`:

```text
release/WheelAthlete-1.8.0-portable.zip
release/WheelAthleteSetup-1.8.0.exe
```

The distribution bundles `WheelAthleteDaemon.exe`; users do not need to start a separate daemon manually. Packaging source and details live in [`packaging/windows/README.md`](packaging/windows/README.md).

## Build & run — Flutter mobile app

Requires Flutter 3.x and a physical BLE-capable device.

```bash
cd app
flutter pub get
flutter run -d <device-id>
flutter test
flutter analyze

# Android release
flutter build apk --release
flutter build appbundle --release

# iOS release (macOS + Xcode required)
flutter build ios --release
```

Mobile version is `1.8.0+9` in `app/pubspec.yaml`.

## Build & flash firmware

### M5StickCPlus2

```bash
cd M5plus2_firmware
pio run -e left
pio run -e right
pio run -e left -t upload
pio run -e right -t upload
```

### XIAO nRF52840 Sense

```bash
cd Xiao_firmware
pio run -e left
pio run -e right
pio run -e left -t upload
pio run -e right -t upload
```

Both firmware targets use version `1.8.0` and the same left/right BLE contract.

## BLE protocol and synchronization

The canonical contract is [`docs/ble-protocol.md`](docs/ble-protocol.md), version `1.8.0`.

Important characteristics include IMU Data, Control, Sync, Info, Config, and the standard Battery Level characteristic. Recording reliability uses explicit lifecycle acknowledgements, sequence accounting, acquisition-health telemetry, and low-RTT clock synchronization/drift mapping.

The mobile and Windows implementations share the protocol semantics but maintain platform-appropriate storage and runtime architecture.

## Data

### Mobile

Mobile sessions are stored in the app documents area under a topic/trial/session hierarchy and exported as versioned CSV/metadata/Excel/ZIP artifacts.

### Windows

The Windows acquisition daemon writes an append-only `.waj` journal as the authoritative record. CSV is derived from the journal. Incomplete `.open` journals are recoverable.

Do not treat preview/UI values as the authoritative research record.

## Verification

Core verification includes:

```bash
# Mobile
cd app
flutter test
flutter analyze

# Windows Python stack (from repo root)
python -m pytest tools/pc_acquisition/tests tools/pc_gui/tests -q
python -m compileall -q tools/pc_acquisition tools/pc_gui
```

Firmware has host-side contract/unit tests under each firmware target. Detailed verification evidence is kept under `docs/testing/`.

Automated tests/simulation do **not** prove real RF throughput, real physical left/right start skew, or hardware behavior at distance. Those claims require the prepared physical two-XIAO acceptance procedure.

## Versioning

Current coordinated release:

| Component | Version |
|---|---:|
| Product | `1.8.0` |
| Flutter mobile | `1.8.0+9` |
| M5StickCPlus2 firmware | `1.8.0` |
| XIAO firmware | `1.8.0` |
| BLE protocol | `1.8.0` |
| Python Windows installer | `1.8.0` |

`VERSION` is the product/Windows packaging version. Automated consistency tests guard the duplicated platform-specific version declarations.

## Project state

Current architecture/decisions/progress are intentionally consolidated under [`.project/`](.project/). Old phase prompts and duplicate trackers were removed because Git history already preserves them.

Development for the Windows product is currently on `codex/pc-version`. Do not merge/push it into `main` unless explicitly requested.

## License

Proprietary — all rights reserved. This is a research project; contact the maintainer before reuse.
