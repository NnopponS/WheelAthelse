# WheelAthlete Windows Packaging

This folder contains the only supported Windows packaging path for the Python Research Edition.

## Inputs

- `../../../../VERSION` — coordinated product version
- `../../tools/pc_gui/` — PySide6 GUI
- `../../tools/pc_acquisition/` — acquisition daemon
- `../../../../assets/wheelathlete-logo.ico` — application/installer icon

## Prerequisites

- Python with the Windows app dependencies installed
- PyInstaller (`python -m pip install pyinstaller`)
- Inno Setup 6 installed at the standard per-user location

## Build

From the repository root:

```bat
applications\wheelathlete_windows\packaging\windows\build_installer.bat
```

The script builds the GUI, builds a standalone `WheelAthleteDaemon.exe`, bundles the daemon into the GUI distribution, creates a portable ZIP, then creates the Inno Setup installer.

## Outputs

Generated files are written to the ignored `applications/wheelathlete_windows/release/` directory:

- `WheelAthlete-<version>-portable.zip`
- `WheelAthleteSetup-<version>.exe`

Intermediate PyInstaller files are written under ignored `applications/wheelathlete_windows/build/pyinstaller/`.

The GUI bundle includes the root `VERSION` file so the updater can identify the installed version. Inno Setup preserves one AppId across releases and understands `/AUTOUPDATE=1` so a verified in-app update can close the GUI, replace files, and relaunch WheelAthlete. The build script prints the final installer SHA-256 and byte size used by the shared release manifest.

Do not commit generated EXE/ZIP/build output. Commit only the packaging source in this folder.
