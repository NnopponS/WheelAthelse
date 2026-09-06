# WheelAthlete â€” Current Architecture

Updated: 2026-09-06

## Repository topology

WheelAthlete is organized into two explicit product domains: operator applications and embedded hardware firmware.

```text
WheelAthelse/
â”œâ”€â”€ applications/
â”‚   â”œâ”€â”€ wheelathlete_mobile/          # WheelAthlete Mobile Application
â”‚   â””â”€â”€ wheelathlete_windows/         # WheelAthlete Windows Research Application
â”œâ”€â”€ hardware_firmware/
â”‚   â”œâ”€â”€ m5stickc_plus2/               # WheelAthlete M5StickC Plus2 Firmware
â”‚   â””â”€â”€ xiao_nrf52840_sense/          # WheelAthlete XIAO nRF52840 Sense Firmware
â”œâ”€â”€ assets/
â”œâ”€â”€ docs/
â”œâ”€â”€ .project/
â”œâ”€â”€ VERSION
â”œâ”€â”€ README.md
â””â”€â”€ README.th.md
```

Generated build output, caches, PlatformIO `.pio/`, and collected research data are excluded from Git.

## Product topology

Both operator applications use the same WheelAthlete BLE contract. Only one operator application should own a given left/right sensor pair at a time.

```text
Left wheel sensor â”€â”
                   â”œâ”€â”€ BLE GATT â”€â”€ WheelAthlete Mobile Application
Right wheel sensor â”˜                  Flutter / iOS / Android

Left wheel sensor â”€â”
                   â”œâ”€â”€ BLE GATT â”€â”€ Acquisition daemon â”€â”€ localhost IPC â”€â”€ PySide6 GUI
Right wheel sensor â”˜                  WheelAthlete Windows Research Application
```

## WheelAthlete Mobile Application

Location: `applications/wheelathlete_mobile/`

Supported product platforms:

- Android
- iOS

The mobile application owns BLE directly through `flutter_blue_plus`. It handles dual-wheel connection, synchronization, realtime preview, recording, session organization, QC presentation, and CSV/Excel/ZIP export.

Flutter Windows and Web targets are retired and are not part of the maintained mobile source tree.

## WheelAthlete Windows Research Application

Location: `applications/wheelathlete_windows/`

Main components:

- `tools/pc_acquisition/` â€” authoritative BLE acquisition daemon
- `tools/pc_gui/` â€” PySide6 operator interface and optional offline MODEL adapter
- `run_wheelathlete_windows.bat` â€” source launcher
- `packaging/windows/` â€” PyInstaller and Inno Setup packaging

Reliability boundary:

```text
BLE notification
  -> acquisition daemon
  -> strict parsing and sequence accounting
  -> synchronization
  -> append-only .waj journal
  -> final QC / recovery
  -> bounded localhost preview/status IPC
  -> PySide6 GUI
```

The GUI is not the authoritative raw-data path. UI rendering, optional model inference, or GUI restart must not become the BLE storage bottleneck.

Default Windows data locations:

- Sessions: `~/Documents/WheelAthlete/PC Sessions`
- GUI log: `~/Documents/WheelAthlete/Logs/wheelathlete-windows.log`
- Experiment presets: `~/Documents/WheelAthlete/experiments.json`

## Hardware & firmware

Maintained targets:

- `hardware_firmware/m5stickc_plus2/` â€” M5StickC Plus2 / ESP32
- `hardware_firmware/xiao_nrf52840_sense/` â€” Seeed Studio XIAO nRF52840 Sense

Both implement the same left/right BLE protocol and support configured wheel identity, 50/100/200 Hz sampling, synchronized lifecycle control, sensor ranges, battery reporting, sequence/loss accounting, replay/recovery, and acquisition-health telemetry.

Canonical protocol: `docs/ble-protocol.md`.

## Optional trajectory MODEL

The Windows MODEL workflow is offline/optional and does not participate in authoritative acquisition. Compatible local BiWheel3D checkpoints may be discovered from the repository root when available. The existing TCN + BiLSTM model is buffered/offline research analysis rather than a zero-latency causal estimator.

## Application update architecture

Both user-facing applications consume one stable GitHub Releases manifest:

```text
https://github.com/NnopponS/WheelAthelse/releases/latest/download/latest.json
```

The release manifest is generated only from final build artifacts and carries schema/channel/version metadata plus exact byte size and SHA-256 for Android and Windows downloads.

- Mobile release/profile builds perform a lightweight check after startup and every six hours. Android downloads a verified APK and delegates installation to the Android system package installer. iOS delegates installation to App Store/TestFlight.
- Installed Windows PyInstaller/Inno builds check after startup and every six hours, verify the installer, then may relaunch through the stable Inno AppId.
- Source/demo/portable Windows execution is never self-replacing.
- Neither application starts installation while acquisition is active.
- Firmware update is deliberately outside this application updater; BLE firmware/protocol remain independently versioned.

Release automation is under `.github/workflows/release.yml`; shared manifest tooling is under `release/`.

## Packaging

Windows packaging is self-contained under `applications/wheelathlete_windows/`:

- build sources: `applications/wheelathlete_windows/packaging/windows/`
- generated work directory: `applications/wheelathlete_windows/build/`
- generated packages: `applications/wheelathlete_windows/release/`

Generated directories are ignored by Git.

## Versioning

Current application release:

- product/application release: `1.8.0`
- WheelAthlete Mobile Application: `1.8.0+10`
- WheelAthlete Windows Research Application package: `1.8.0`
- M5StickC Plus2 firmware: `1.8.0`
- XIAO nRF52840 Sense firmware: `1.8.0`
- BLE protocol: `1.8.0`

The root `VERSION` tracks the user-facing application/product release. Firmware and BLE protocol are intentionally not bumped when an application-only release does not change the wire contract.

## Retired implementations

Retired code remains available through Git history where applicable:

- Flutter Windows desktop implementation
- Flutter Web scaffold
- legacy Tkinter/Matplotlib desktop GUI
