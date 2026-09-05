# Build Guide

Current release line: `v1.8.0`.

## Flutter mobile app — Android / iOS

```bash
cd app
flutter pub get
flutter run -d <physical-device-id>
flutter test
flutter analyze

flutter build apk --release
flutter build appbundle --release
# macOS + Xcode required:
flutter build ios --release
```

The Flutter product is mobile-only. There is no supported Flutter Windows or Web build target.

## Python Windows app — source

From repository root:

```bat
run_python_pc_app.bat
```

Demo mode without hardware:

```bat
run_python_pc_app.bat --demo
```

The GUI starts/reuses the local acquisition daemon automatically.

## Python Windows app — portable EXE + installer

Prerequisites:

- Python and WheelAthlete Python dependencies
- PyInstaller
- Inno Setup 6

Build from repository root:

```bat
packaging\windows\build_installer.bat
```

Outputs:

```text
release/WheelAthlete-1.8.0-portable.zip
release/WheelAthleteSetup-1.8.0.exe
```

The daemon executable is bundled with the GUI distribution. See `packaging/windows/README.md` for packaging details.

## M5StickCPlus2 firmware

```bash
cd M5plus2_firmware
pio run -e left
pio run -e right
pio run -e left -t upload
pio run -e right -t upload
```

## XIAO nRF52840 Sense firmware

```bash
cd Xiao_firmware
pio run -e left
pio run -e right
pio run -e left -t upload
pio run -e right -t upload
```

Both targets use firmware version `1.8.0` and implement the canonical BLE contract in `docs/ble-protocol.md`.

## Verification

```bash
# Mobile
cd app
flutter test
flutter analyze

# Windows Python, from repo root
python -m pytest tools/pc_acquisition/tests tools/pc_gui/tests -q
python -m compileall -q tools/pc_acquisition tools/pc_gui
```

Physical BLE throughput and real left/right start skew require hardware acceptance; automated tests do not prove RF behavior.
