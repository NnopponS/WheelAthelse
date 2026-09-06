# Build Guide

Current release line: `v1.8.0`.

## Flutter mobile app — Android / iOS

```bash
cd applications/wheelathlete_mobile
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
applications/wheelathlete_windows/run_wheelathlete_windows.bat
```

Demo mode without hardware:

```bat
applications/wheelathlete_windows/run_wheelathlete_windows.bat --demo
```

The GUI starts/reuses the local acquisition daemon automatically.

## Python Windows app — portable EXE + installer

Prerequisites:

- Python and WheelAthlete Python dependencies
- PyInstaller
- Inno Setup 6

Build from repository root:

```bat
applications\wheelathlete_windows\packaging\windows\build_installer.bat
```

Outputs:

```text
release/WheelAthlete-1.8.0-portable.zip
release/WheelAthleteSetup-1.8.0.exe
```

The daemon executable is bundled with the GUI distribution. See `applications/wheelathlete_windows/packaging/windows/README.md` for packaging details.

## M5StickCPlus2 firmware

```bash
cd hardware_firmware/m5stickc_plus2
pio run -e left
pio run -e right
pio run -e left -t upload
pio run -e right -t upload
```

## XIAO nRF52840 Sense firmware

```bash
cd hardware_firmware/xiao_nrf52840_sense
pio run -e left
pio run -e right
pio run -e left -t upload
pio run -e right -t upload
```

Both targets use firmware version `1.8.0` and implement the canonical BLE contract in `docs/ble-protocol.md`.

## Verification

```bash
# Mobile
cd applications/wheelathlete_mobile
flutter test
flutter analyze

# Windows Python, from repo root
python -m pytest applications/wheelathlete_windows/tools/pc_acquisition/tests applications/wheelathlete_windows/tools/pc_gui/tests -q
python -m compileall -q applications/wheelathlete_windows/tools/pc_acquisition applications/wheelathlete_windows/tools/pc_gui
```

Physical BLE throughput and real left/right start skew require hardware acceptance; automated tests do not prove RF behavior.
