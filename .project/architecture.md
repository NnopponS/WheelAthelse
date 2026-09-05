# WheelAthlete — Current Architecture

Updated: 2026-09-05

## Product topology

WheelAthlete supports two independent operator clients that speak the same WheelAthlete BLE contract. Use **one client at a time** with a given pair of wheel sensors.

```text
                     Wheel sensors
          ┌────────────────────────────────┐
          │ Left / Right WheelAthlete node │
          │ M5StickCPlus2 or XIAO BLE Sense│
          └───────────────┬────────────────┘
                          │ BLE GATT
              ┌───────────┴───────────┐
              │                       │
              ▼                       ▼
     Flutter Mobile App       Python Windows App
       iOS + Android              PySide6 GUI
       direct BLE I/O                  │
              │                  localhost IPC
              │                       │
              │                Acquisition daemon
              │                Bleak / WinRT BLE
              │                       │
              ▼                       ▼
     CSV/meta sessions        append-only .waj journal
     + preview/export         + QC/recovery + CSV export
```

## 1. Firmware

Two maintained firmware targets implement the same protocol:

- `M5plus2_firmware/` — M5StickCPlus2 / ESP32
- `Xiao_firmware/` — Seeed XIAO nRF52840 Sense

Both support left/right identities, 50/100/200 Hz sampling, BLE control, synchronized start, range configuration, battery information, sequence/loss telemetry, and acquisition-health reporting.

The canonical protocol is `docs/ble-protocol.md`.

## 2. Flutter mobile application

Location: `app/`

Supported product platforms:

- Android
- iOS

The mobile app owns BLE directly through `flutter_blue_plus`. Its responsibilities include dual-wheel connection, clock synchronization, realtime preview, recording, session organization, QC presentation, and CSV/Excel/ZIP export.

The mobile product intentionally contains no Windows or Web runtime target.

## 3. Python Windows application

Locations:

- `tools/pc_gui/` — PySide6 operator UI
- `tools/pc_acquisition/` — authoritative acquisition daemon
- `run_python_pc_app.bat` — source launcher
- `packaging/windows/` — EXE/installer build files

Reliability boundary:

```text
BLE notification
  -> acquisition daemon
  -> strict parsing / sequence accounting
  -> synchronization
  -> append-only .waj journal
  -> final QC / recovery
  -> localhost NDJSON status/events/~10 Hz preview
  -> PySide6 GUI
```

Raw 50/100/200 Hz samples do not use the GUI as their authoritative storage path. Closing or slowing the UI therefore cannot silently turn UI rendering backpressure into raw-data loss. During an active recording, a GUI close does not terminate the acquisition daemon.

Default Windows data locations:

- Sessions: `~/Documents/WheelAthlete/PC Sessions`
- GUI log: `~/Documents/WheelAthlete/Logs/python-pc-app.log`
- Experiment presets: `~/Documents/WheelAthlete/experiments.json`

## 4. Packaging

Windows packaging lives only under `packaging/windows/`:

- `build_installer.bat` — builds GUI + bundled daemon + portable ZIP + installer
- `installer.iss` — Inno Setup definition
- `README.md` — packaging prerequisites and outputs

Generated artifacts are written to root `release/` and are not tracked by Git.

## 5. Versioning

The current coordinated release is `v1.8.0`:

- Flutter mobile: `1.8.0+9`
- firmware: `1.8.0`
- BLE contract: `1.8.0`
- Python Windows packaging: `1.8.0`

The app build number is independent of semantic product version and increments from `+8` to `+9` for this release.

## 6. Retired implementations

Removed from the current source tree:

- legacy Tkinter/Matplotlib desktop GUI
- Flutter Windows desktop UI/backend/tests
- Flutter Windows runner target
- Flutter Web scaffold

Their implementation history remains available through Git commits and is summarized in `.project/history.md`.
