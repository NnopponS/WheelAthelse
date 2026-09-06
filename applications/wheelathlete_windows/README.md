# WheelAthlete Windows Research Application

The **WheelAthlete Windows Research Application** is the reliability-first Windows acquisition and research client. It uses a PySide6 operator interface and a separate Python acquisition daemon so BLE capture and authoritative raw-data recording remain isolated from UI rendering and optional analysis workloads.

Current package version: `1.8.0`

## Architecture

- `tools/pc_acquisition/` â€” authoritative BLE acquisition daemon, synchronization, sequence/loss accounting, journal storage, QC, and recovery.
- `tools/pc_gui/` â€” PySide6 operator interface, Results workflow, diagnostics, export, and optional offline MODEL integration.
- `packaging/windows/` â€” PyInstaller and Inno Setup packaging sources.
- `run_wheelathlete_windows.bat` â€” source launcher.
- `build/` and `release/` â€” generated artifacts; excluded from Git.

## Run from source

```bat
cd applications\wheelathlete_windows
run_wheelathlete_windows.bat
```

Demo UI without physical boards:

```bat
run_wheelathlete_windows.bat --demo
```

## Verify

```bat
python -m pytest tools\pc_acquisition\tests tools\pc_gui\tests -q
python -m compileall -q tools\pc_acquisition tools\pc_gui
```

## Build the Windows package

Prerequisites: Python 3.10+, PyInstaller, and Inno Setup 6.

```bat
packaging\windows\build_installer.bat
```

Generated packages are written to `release/`.

## Automatic updates

The installed PyInstaller application checks `releases/latest/download/latest.json` after startup and every six hours. Manual checking is available from the header. Installer downloads are accepted only from this repository's HTTPS GitHub Release path and must match both the exact manifest size and SHA-256.

An update can be downloaded while the UI is idle, but installation is blocked while Live preview, countdown, or recording is active. Once confirmed, WheelAthlete launches the verified Inno Setup installer with `/AUTOUPDATE=1`, exits cleanly, updates the existing stable AppId, and relaunches automatically. Source/demo mode can inspect releases but deliberately does not replace itself.

For the detailed operator/developer workflow, see [`tools/pc_gui/README.md`](tools/pc_gui/README.md). For the overall product architecture, see the repository-level [`README.md`](../../README.md) or [`README.th.md`](../../README.th.md).
