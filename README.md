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
                                      │
                                      ▼
                           optional offline MODEL page
                         PyTorch trajectory reconstruction
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

The Python Research Edition uses a reliability-first two-process architecture. The PySide6 GUI never owns the authoritative BLE/raw-data path. A separate acquisition daemon owns BLE, strict packet parsing, sequence/loss accounting, synchronization, append-only `.waj` journal writes, final QC, and crash recovery. The GUI receives bounded preview/status traffic over localhost IPC.

This means a slow chart, PyTorch inference, or restarted GUI cannot silently become the raw BLE storage bottleneck.

The current Windows UI has five operator sections:

- **Dashboard** — board connection and system overview;
- **Acquisition** — synchronized live preview and recording controls;
- **Results** — recordings grouped by topic, QC, telemetry preview, batch CSV export/delete, and direct metadata editing;
- **MODEL** — optional offline 2D trajectory reconstruction from finalized recordings;
- **Diagnostics** — acquisition/data-integrity information.

#### Results and session organization

Finalized Windows recordings keep an immutable internal session UUID, but the files users see are stored with human-readable names:

```text
~/Documents/WheelAthlete/PC Sessions/
└── 10x5/
    ├── 10x5_Trial16_Nipoon.waj
    └── 10x5_Trial16_Nipoon.summary.json
```

Results supports both **Group by Topic** and **All Trials Table** views. Topic, trial, and athlete names can be edited directly from the table. Changes require confirmation before the file/folder is renamed, while the internal UUID and raw journal identity remain unchanged. Group names can also be renamed, which moves all finalized sessions in that topic to the new topic folder.

Checkboxes are reserved for batch actions such as Export/Delete; table editing does not use row selection, so preview controls stay visible while metadata is being edited.

#### Experimental MODEL page

The MODEL page is intentionally offline and does not touch the acquisition critical path:

```text
Record
  ↓
Finalized Results session
  ↓
Select checkpoint
  ↓
Prepare synchronized dual-wheel IMU window
  ↓
PyTorch / BiWheel3D inference
  ↓
2D XY trajectory
```

Current model integration supports:

- selecting a compatible discovered checkpoint or browsing to a `.pt` / `.pth` checkpoint with Windows File Explorer;
- loading finalized sessions from Results;
- dual-wheel preprocessing into the BiWheel3D input contract;
- SI-unit conversion and 100 Hz preparation for the current adapter;
- offline PyTorch inference in a background worker so the GUI stays responsive;
- a 2D XY trajectory plot with equal X/Y physical scale (`1 m` on X equals `1 m` on Y);
- path length, endpoint distance, and model-point summaries;
- explicit compatibility/errors instead of silently forcing an incompatible checkpoint.

The current BiWheel3D TCN + BiLSTM model is a buffered/offline research model, not a zero-latency causal estimator. The MODEL feature should therefore be treated as experimental analysis, not as part of authoritative acquisition.

See [`tools/pc_gui/README.md`](tools/pc_gui/README.md) for the detailed Windows workflow.

## Repository layout

```text
WheelAthelse/
├── app/                         # Flutter mobile app — iOS + Android
├── M5plus2_firmware/            # M5StickCPlus2 firmware
├── Xiao_firmware/               # XIAO nRF52840 Sense firmware
├── tools/
│   ├── pc_acquisition/          # Windows authoritative BLE/recording daemon
│   ├── pc_gui/                  # PySide6 Windows operator UI + MODEL adapter
│   │   ├── model_inference.py   # Experimental offline model integration
│   │   └── requirements-model.txt
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

The launcher checks the normal Python UI dependencies and starts `tools.pc_gui`. In normal mode the GUI starts or reuses the local acquisition daemon automatically.

Demo UI without physical boards:

```bat
run_python_pc_app.bat --demo
```

Demo mode is visibly labeled and does not create synthetic research evidence.

Default Windows data locations:

- Sessions: `~/Documents/WheelAthlete/PC Sessions`
- GUI log: `~/Documents/WheelAthlete/Logs/python-pc-app.log`
- Experiment presets: `~/Documents/WheelAthlete/experiments.json`

### Optional MODEL dependencies

PyTorch is kept separate from the normal acquisition requirements so the reliable data-collection app does not need to install the large ML runtime unless MODEL analysis is required.

```bat
python -m pip install -r tools\pc_gui\requirements-model.txt
```

The MODEL page also expects the compatible model project/checkpoint files referenced by the selected checkpoint. Model inference is optional; recording, Results, export, and diagnostics remain usable without it.

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

Finalized sessions are relocated into human-readable topic folders using `Topic_TrialN_Athlete` filenames while preserving the UUID embedded in the authoritative journal. User-facing metadata can be corrected later from Results without rewriting the raw journal identity.

Do not treat preview/UI values or MODEL output as the authoritative research record.

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

MODEL-specific tests cover preprocessing contracts, checkpoint selection, Results → MODEL navigation, equal-axis trajectory rendering, and custom checkpoint browsing.

Firmware has host-side contract/unit tests under each firmware target. Detailed verification evidence is kept under `docs/testing/`.

Automated tests/simulation do **not** prove real RF throughput, real physical left/right start skew, real-world model accuracy, or hardware behavior at distance. Those claims require the prepared physical two-XIAO acceptance procedure and model validation data.

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
