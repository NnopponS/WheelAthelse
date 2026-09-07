# WheelAthlete

**Dual-wheel IMU acquisition and analysis platform for wheelchair sports research.**

WheelAthlete synchronizes left- and right-wheel inertial sensors, records research-grade motion data, and provides dedicated mobile and Windows applications for field collection, monitoring, quality control, export, and optional trajectory analysis.

> **Current release line:** `v1.8.0`
> **Mobile application:** `1.8.0+10`
> **Firmware:** `1.8.0`
> **BLE protocol:** `1.8.0`
> **Windows package:** `1.8.0`
> **Language:** English | [ไทย](README.th.md)

## Product architecture

WheelAthlete is organized into two top-level product domains:

1. **Applications** — operator-facing software.
2. **Hardware & Firmware** — embedded sensor firmware.

There are two maintained operator applications. Use only one operator application with a given left/right sensor pair at a time.

| Component | Official name | Platform / hardware | Technology | Primary role |
|---|---|---|---|---|
| Mobile | **WheelAthlete Mobile Application** | iOS, Android | Flutter / Dart | Portable BLE acquisition, live monitoring, session management, export |
| Windows | **WheelAthlete Windows Research Application** | Windows 10/11 | Python / PySide6 | Reliability-first acquisition, QC, recovery, research workflow, optional model analysis |
| Firmware | **WheelAthlete M5StickC Plus2 Firmware** | M5StickC Plus2 / ESP32 | PlatformIO | Dual-wheel IMU sensing and BLE transport |
| Firmware | **WheelAthlete XIAO nRF52840 Sense Firmware** | Seeed Studio XIAO nRF52840 Sense | PlatformIO | Dual-wheel IMU sensing and BLE transport |

The retired Flutter Windows target, Flutter Web scaffold, and legacy Tkinter desktop interface are not part of the maintained product surface.

## Repository layout

```text
WheelAthelse/
├── applications/
│   ├── wheelathlete_mobile/              # Flutter — iOS / Android
│   │   ├── android/
│   │   ├── ios/
│   │   ├── lib/
│   │   ├── test/
│   │   └── pubspec.yaml
│   │
│   └── wheelathlete_windows/             # Python / PySide6 — Windows
│       ├── tools/
│       │   ├── pc_acquisition/           # Authoritative BLE acquisition daemon
│       │   └── pc_gui/                   # Operator UI + optional MODEL adapter
│       ├── packaging/
│       │   └── windows/                  # PyInstaller + Inno Setup
│       ├── run_wheelathlete_windows.bat
│       ├── build/                        # Generated, ignored
│       └── release/                      # Generated, ignored
│
├── hardware_firmware/
│   ├── m5stickc_plus2/                   # M5StickC Plus2 / ESP32 firmware
│   └── xiao_nrf52840_sense/              # XIAO nRF52840 Sense firmware
│
├── assets/                               # Product icons and shared assets
├── docs/                                 # BLE specification, testing, protocols, wiki
├── .project/                             # Canonical engineering/project state
├── VERSION                               # Coordinated semantic release version
├── README.md
└── README.th.md
```

Generated build output, PlatformIO `.pio/`, Flutter generated files, Python caches, and collected research sessions are intentionally excluded from Git.

## System overview

```text
 Left wheel IMU                         Right wheel IMU
       |                                      |
       +--------------- BLE ------------------+
                          |
              +-----------+-----------+
              |                       |
              v                       v
 WheelAthlete Mobile       WheelAthlete Windows
 Application               Research Application
 Flutter / Dart             PySide6 GUI
 direct BLE ownership           |
                                v
                       localhost IPC
                                |
                                v
                       Acquisition daemon
                       Bleak / WinRT BLE
                                |
                                v
                       append-only .waj journal
                       QC / recovery / CSV export
                                |
                                v
                       optional offline MODEL
```

Both firmware targets implement the same BLE contract. The canonical protocol specification is [`docs/ble-protocol.md`](docs/ble-protocol.md).

## Applications

### WheelAthlete Mobile Application

Location: [`applications/wheelathlete_mobile/`](applications/wheelathlete_mobile/)

Primary capabilities:

- connect left and right BLE sensor boards;
- display real-time accelerometer and gyroscope data;
- synchronize device clocks and recording start;
- organize data by topic, trial, and session;
- use protocol templates and experiment tracking;
- add tags, search, filter, and preview sessions;
- show QC/quality indicators and statistics;
- export CSV, Excel, ZIP, and share through the operating system;
- run on Android and iOS only.

Quick start:

```bash
cd applications/wheelathlete_mobile
flutter pub get
flutter run -d <device-id>
```

Verification:

```bash
cd applications/wheelathlete_mobile
flutter test
flutter analyze
```

Release builds:

```bash
# Android
flutter build apk --release
flutter build appbundle --release

# iOS — requires macOS + Xcode
flutter build ios --release
```

### WheelAthlete Windows Research Application

Location: [`applications/wheelathlete_windows/`](applications/wheelathlete_windows/)

The Windows application uses a reliability-first two-process design:

- the **acquisition daemon** owns BLE, packet parsing, synchronization, sequence/loss accounting, append-only journal writes, QC, and recovery;
- the **PySide6 GUI** handles operator controls, status, preview, results, diagnostics, export, and optional model analysis.

The GUI is intentionally not the authoritative raw-data path. A slow chart, model inference task, or GUI restart therefore cannot silently become the BLE storage bottleneck.

Current operator sections:

- **Dashboard** — board connection and system overview;
- **Acquisition** — synchronized preview and recording controls;
- **Results** — finalized sessions, QC, metadata editing, export, and delete;
- **MODEL** — optional offline trajectory reconstruction;
- **Diagnostics** — acquisition and integrity information.

Run from source:

```bat
cd applications\wheelathlete_windows
run_wheelathlete_windows.bat
```

Demo mode:

```bat
cd applications\wheelathlete_windows
run_wheelathlete_windows.bat --demo
```

Default Windows data locations:

- Sessions: `~/Documents/WheelAthlete/PC Sessions`
- GUI log: `~/Documents/WheelAthlete/Logs/wheelathlete-windows.log`
- Experiment presets: `~/Documents/WheelAthlete/experiments.json`

Detailed Windows documentation: [`applications/wheelathlete_windows/tools/pc_gui/README.md`](applications/wheelathlete_windows/tools/pc_gui/README.md)

### Optional MODEL dependencies

PyTorch/model dependencies are separate from the core acquisition runtime.

```bat
python -m pip install -r applications\wheelathlete_windows\tools\pc_gui\requirements-model.txt
```

The MODEL workflow is optional and offline. Recording, Results, export, and diagnostics remain available without PyTorch or a compatible model checkout.

## Hardware & firmware

Both maintained firmware targets support the shared left/right WheelAthlete BLE contract, including configured wheel identity, sampling rates, synchronized lifecycle control, battery state, sequence accounting, replay/recovery support, and acquisition-health telemetry.

### WheelAthlete M5StickC Plus2 Firmware

Location: [`hardware_firmware/m5stickc_plus2/`](hardware_firmware/m5stickc_plus2/)

```bash
cd hardware_firmware/m5stickc_plus2

pio run -e left
pio run -e right

pio run -e left -t upload
pio run -e right -t upload
```

### WheelAthlete XIAO nRF52840 Sense Firmware

Location: [`hardware_firmware/xiao_nrf52840_sense/`](hardware_firmware/xiao_nrf52840_sense/)

```bash
cd hardware_firmware/xiao_nrf52840_sense

pio run -e left
pio run -e right

pio run -e left -t upload
pio run -e right -t upload
```

## Windows packaging

Prerequisites:

- Python 3.10+
- PyInstaller
- Inno Setup 6

Build the portable package and installer:

```bat
cd applications\wheelathlete_windows
packaging\windows\build_installer.bat
```

Generated output:

```text
applications/wheelathlete_windows/release/
├── WheelAthlete-1.8.0-portable.zip
└── WheelAthleteSetup-1.8.0.exe
```

The installer and portable package bundle `WheelAthleteDaemon.exe`. Packaging details are documented in [`applications/wheelathlete_windows/packaging/windows/README.md`](applications/wheelathlete_windows/packaging/windows/README.md).

## Automatic application updates

The Flutter Mobile and Python Windows applications use one stable GitHub Releases manifest:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

Every downloadable artifact is pinned by exact byte size and SHA-256 in `latest.json`.

- **Android:** the release app checks automatically after startup and every six hours, downloads only the repository's HTTPS release APK, verifies size + SHA-256, then opens Android's system package installer. The user still approves installation. Direct APK updating requires a persistent release signing key; GitHub release builds intentionally fail if the Android signing secrets are missing.
- **iOS:** update discovery uses the same manifest, while installation is handed to App Store/TestFlight. iOS does not permit an app to replace itself with an arbitrary downloaded binary.
- **Windows:** the installed PyInstaller build checks automatically after startup and every six hours, downloads and verifies the Inno Setup installer, then can silently update the existing AppId and relaunch WheelAthlete.
- **Acquisition safety:** neither app will install an update while Live preview, countdown, or recording is active.

Release automation lives in `.github/workflows/release.yml`. A `v<version>` tag builds/tests both applications, produces the APK and Windows installer, generates `latest.json`, and publishes all three to one GitHub Release. See [`release/README.md`](release/README.md).

> Bootstrap note: an already-installed build that predates this updater cannot self-update. Install the first updater-enabled release once manually; subsequent releases can use the in-app updater.

## Data integrity

### Mobile

The mobile application stores sessions using topic/trial/session organization and exports versioned CSV/metadata artifacts.

### Windows

The Windows acquisition daemon writes an append-only `.waj` journal as the authoritative record. CSV and summaries are derived from that journal. Incomplete `.open` journals can be recovered.

Finalized sessions use human-readable topic/trial/athlete file names while preserving the immutable internal session UUID.

**Preview values, charts, and MODEL output are not the authoritative research record.**

## BLE protocol and synchronization

Canonical specification: [`docs/ble-protocol.md`](docs/ble-protocol.md)

Current protocol version: `1.8.0`

Important reliability mechanisms include:

- explicit recording lifecycle acknowledgements;
- left/right synchronized start;
- clock synchronization and drift mapping;
- sequence accounting;
- acquisition-health telemetry;
- replay/recovery support;
- strict packet parsing and QC.

## Verification

Mobile application:

```bash
cd applications/wheelathlete_mobile
flutter test
flutter analyze
```

Windows application:

```bat
cd applications\wheelathlete_windows
python -m pytest tools\pc_acquisition\tests tools\pc_gui\tests -q
python -m compileall -q tools\pc_acquisition tools\pc_gui
```

Firmware:

```bash
cd hardware_firmware/m5stickc_plus2
pio run -e left
pio run -e right

cd ../xiao_nrf52840_sense
pio run -e left
pio run -e right
```

Automated tests do not replace physical two-board acceptance testing under realistic RF conditions.

## Version matrix

| Component | Version |
|---|---:|
| Product release | `1.8.0` |
| WheelAthlete Mobile Application | `1.8.0+10` |
| WheelAthlete Windows Research Application | `1.8.0` |
| M5StickC Plus2 firmware | `1.8.0` |
| XIAO nRF52840 Sense firmware | `1.8.0` |
| BLE protocol | `1.8.0` |

The root [`VERSION`](VERSION) file is the coordinated product version used by Windows packaging and release validation.

## Engineering documentation

- [`docs/`](docs/) — protocol, field workflow, test plans, and wiki documentation
- [`.project/`](.project/) — current architecture, progress, engineering decisions, and project state

## License

Proprietary. Use, redistribution, and modification require permission from the project maintainers.

## Automatic software updates

WheelAthlete Mobile and WheelAthlete Windows use one verified stable manifest published with GitHub Releases:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

- **Android:** checks automatically in release builds, downloads the APK, verifies exact size + SHA-256, and opens Android's system installer. Android still requires user approval and every public APK must use the same permanent signing key with an increasing `versionCode`.
- **iOS:** checks the same manifest, then opens the configured App Store/TestFlight page; iOS installation remains store-managed.
- **Windows:** an installed PyInstaller/Inno build checks shortly after launch and every six hours, downloads and verifies the installer, refuses to interrupt active acquisition, closes safely, installs silently, and relaunches WheelAthlete. Source and portable builds never replace themselves.

Release artifacts and `latest.json` are generated by `.github/workflows/release.yml`. The first updater-enabled production build must be installed manually once on devices running an older build that did not contain the updater. Full release/signing instructions are in `release/README.md`.
