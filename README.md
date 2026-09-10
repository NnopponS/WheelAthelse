# WheelAthlete

**Reliability-first IMU acquisition and motion-analysis platform for wheelchair sports research.**

WheelAthlete synchronizes inertial sensors mounted on the left and right wheelchair wheels, records research-grade motion data, and provides a dedicated Windows workflow for acquisition, quality control, export, diagnostics, and optional offline trajectory analysis. An optional chair-center IMU (`C`) is supported for acquisition and research instrumentation.

> **Current release:** `v1.8.2` — Windows-first
> **Windows application:** `1.8.2`
> **Firmware:** `1.8.2`
> **BLE protocol:** `1.8.0`
> **Mobile source:** `1.8.2+12`, maintenance-only; no new mobile publication or binary in this release
> **Language:** English | [ไทย](README.th.md)

## Release status

WheelAthlete 1.8.2 consolidates the Windows application, M5/XIAO firmware, three-sensor acquisition support, release hardening, installer lifecycle, Results workflow, and portable model-bundle support into one maintained source line.

The public repository is intentionally organized around two branches:

- `main` — integrated source of truth;
- `release/main-v1.8.2` — exact tested 1.8.2 release line.

Historical version tags are retained for traceability. Obsolete development/release branches do not need to remain visible after their work is fully integrated.

### Source-only Windows release while signing is unavailable

The current v1.8.2 GitHub Release is source-only. Public Windows installer, portable archive, and `latest.json` are withheld until the fail-closed signing pipeline can verify a trusted RSA Code Signing identity, Code Signing EKU, exact publisher subject, timestamped executable components, generated uninstaller, and installer.

An unsigned local package is suitable for development/testing only. SHA-256 protects artifact integrity but does not establish Windows publisher trust or bypass SmartScreen/Application Control policy.

## What is included in 1.8.2

### WheelAthlete Windows Research Application

Location: [`applications/wheelathlete_windows/`](applications/wheelathlete_windows/)

The Windows application uses a two-process architecture:

- **Acquisition daemon** — owns BLE, packet parsing, clock synchronization, sequence/loss accounting, append-only `.waj` recording, QC, recovery, and synchronized lifecycle control.
- **PySide6 GUI** — owns Dashboard, Acquisition, Results, Diagnostics, export, and optional offline MODEL review.

The GUI is not the authoritative raw-data path. A slow chart, model task, or GUI restart must not silently become the BLE recording bottleneck.

Key 1.8.2 behavior:

- Day -> Experiment -> Trial Results hierarchy with persistent session-ID selection;
- day/all/clear batch selection and deduplicated export;
- high-resolution Windows host timing based on QueryPerformanceCounter;
- exact sensor fault reporting for sequence, queue, FIFO, malformed packet, fatal, and active retry states;
- safe daemon shutdown and active-journal finalization before upgrade/uninstall;
- recordings and custom/seeded models preserved across installer lifecycle operations;
- verified in-app update flow when a trusted signed release and `latest.json` exist;
- portable, contained `wheelathlete-model.json` model bundles with compatibility validation.

Run from source:

```bat
cd applications\wheelathlete_windows
run_wheelathlete_windows.bat
```

Demo mode:

```bat
run_wheelathlete_windows.bat --demo
```

Default Windows data locations:

```text
~/Documents/WheelAthlete/PC Sessions
~/Documents/WheelAthlete/Model
~/Documents/WheelAthlete/Logs
```

Detailed Windows documentation: [`applications/wheelathlete_windows/README.md`](applications/wheelathlete_windows/README.md)

### Sensor firmware

WheelAthlete maintains two firmware targets:

| Target | Hardware | Roles | Version |
|---|---|---|---:|
| M5StickC Plus2 | ESP32 / M5StickC Plus2 | L / R / optional C | `1.8.2` |
| XIAO nRF52840 Sense | nRF52840 / LSM6DS3 | L / R / optional C | `1.8.2` |

Locations:

- [`hardware_firmware/m5stickc_plus2/`](hardware_firmware/m5stickc_plus2/)
- [`hardware_firmware/xiao_nrf52840_sense/`](hardware_firmware/xiao_nrf52840_sense/)

Supported role bytes are `L=0x4C`, `R=0x52`, and optional chair-center `C=0x43`.

The center mounting contract is **+Z pointing down toward the floor**. Center X/Y remain physical board axes until forward/lateral orientation is measured. XIAO C uses a **green** identity/heartbeat; M5 C retains its yellow display identity. Existing production trajectory models remain L/R-only.

Canonical BLE specification: [`docs/ble-protocol.md`](docs/ble-protocol.md)

### Offline MODEL analysis

The installed Windows default remains the frozen **Classical v1** L/R planar model. Experimental residual, Slalom, or hybrid paths are explicit research choices and do not silently replace the production default.

New portable models use the versioned bundle contract:

[`docs/model_analysis/MODEL_BUNDLES.md`](docs/model_analysis/MODEL_BUNDLES.md)

The authoritative research recording remains the `.waj` journal. MODEL output, preview charts, and derived exports are not a replacement for raw-record integrity or physical reference validation.

### Mobile status

The existing Flutter Android/iOS source remains in the repository as maintenance material. **No new mobile source changes, APK/AAB/IPA, mobile download, or mobile update offer are part of this v1.8.2 consolidation.**

Mobile is therefore not a current publication gate for this release. Future mobile publication should be handled as a separately reviewed release scope.

## Repository layout

```text
WheelAthelse/
├── applications/
│   ├── wheelathlete_windows/          # active Windows v1.8.2 application
│   └── wheelathlete_mobile/           # retained mobile maintenance source
├── hardware_firmware/
│   ├── m5stickc_plus2/
│   └── xiao_nrf52840_sense/
├── assets/                            # shared product assets
├── docs/                              # BLE/model contracts, testing, wiki
├── release/                           # release notes + manifest tooling
├── scripts/                           # verification/hygiene tooling
├── .project/                          # current engineering state
├── VERSION                            # coordinated product version
├── README.md
└── README.th.md
```

Generated build directories, firmware `.pio/`, Python caches, Flutter generated output, collected sessions, local engineering evidence, and the separate local `BiWheel3D/` research repository are excluded from the root source publication.

## Data integrity

The Windows daemon writes an append-only `.waj` journal as the authoritative recording. Derived CSV/summary output can be regenerated from the journal, and incomplete `.open` journals use the recovery path.

L/R-only recordings retain backward-compatible journal behavior. Sessions that contain optional C use an explicit C side code; C is never silently decoded as R or inserted into the legacy L/R model tensor.

## Automatic Windows updates

Installed Windows clients use the stable manifest location:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

When a trusted signed release exists, WheelAthlete validates semantic version, repository-owned HTTPS URL, exact byte size, and SHA-256 before launching the installer. Update installation is blocked while Live preview, countdown, or recording is active.

The current source-only v1.8.2 release intentionally publishes no `latest.json`, so installed clients receive no update offer yet.

The release workflow is **manually dispatched** from [`.github/workflows/release.yml`](.github/workflows/release.yml). It tests the Windows application, requires the trusted signing configuration, builds/verifies the Windows package, generates `latest.json`, and publishes only after all release gates pass.

See [`release/README.md`](release/README.md) for the complete trust and publication contract.

## Build the Windows package

Prerequisites:

- Python 3.10+
- PyInstaller
- Inno Setup 6

```bat
cd applications\wheelathlete_windows
packaging\windows\build_installer.bat
```

Generated local output is written under `applications/wheelathlete_windows/release/` and is ignored by Git.

## Verification

Project publication hygiene:

```bash
python scripts/verify_project.py
```

Windows application:

```bat
cd applications\wheelathlete_windows
python -m pytest tools\pc_gui\tests tools\pc_acquisition\tests -q
python -m compileall -q tools\pc_gui tools\pc_acquisition
```

Firmware host tests/builds are run from each firmware target using its existing test and PlatformIO configuration.

Automated tests and successful builds do **not** prove real RF throughput, physical orientation, synchronized three-board timing, or trajectory accuracy. Those require physical/reference acceptance.

## Current acceptance boundary

Software/source acceptance for 1.8.2 is separate from two external gates:

- **Trusted Windows signing** — required before public Windows binaries/update manifest are published.
- **Final L/R/C physical acceptance** — deferred until the sensor hardware is available again.

The specific XIAO C 1.8.2 board has strong partial runtime evidence, but the final Windows C record/QC/reopen/export sequence and simultaneous L/R/C bench run remain outstanding and are not represented as complete physical acceptance.

## Engineering documentation

- [`.project/STATUS.md`](.project/STATUS.md) — current measured state and open gates
- [`.project/HANDOFF.md`](.project/HANDOFF.md) — exact continuation instructions
- [`.project/architecture.md`](.project/architecture.md) — runtime/data/model boundaries
- [`.project/decisions.md`](.project/decisions.md) — active durable decisions
- [`release/RELEASE_NOTES_1.8.2.md`](release/RELEASE_NOTES_1.8.2.md) — release summary

## Version matrix

| Component | Version / status |
|---|---|
| Product release | `1.8.2` |
| Windows Research Application | `1.8.2` |
| M5StickC Plus2 firmware | `1.8.2` |
| XIAO nRF52840 Sense firmware | `1.8.2` |
| BLE protocol | `1.8.0` |
| Flutter mobile source | `1.8.2+12` — maintenance-only, not part of current publication |

The root [`VERSION`](VERSION) file is the coordinated product version used by Windows packaging and release validation.

## License

Proprietary. Use, redistribution, and modification require permission from the project maintainers.
