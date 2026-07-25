# Build Guide

> v0.1.0 — Data Collection MVP

## Prerequisites

### Firmware
- [PlatformIO](https://platformio.org/) — VS Code extension or CLI
- USB-C cable (data + power)
- 2× M5StickCPlus2

### App
- [Flutter](https://flutter.dev/) 3.x (`flutter --version` → SDK `^3.11.5`)
- For iOS: macOS + Xcode
- For Android: Android Studio or Android SDK
- A physical phone (BLE doesn't work on emulators)

---

## Firmware — Build & Flash

```bash
cd firmware

# Build for each wheel
pio run -e left          # build left wheel firmware
pio run -e right         # build right wheel firmware

# Flash to M5StickCPlus2 (connect via USB-C first)
pio run -e left -t upload     # flash left M5
pio run -e right -t upload    # flash right M5

# Monitor serial debug output (115200 baud)
pio device monitor

# Run host-side pure-logic tests (no hardware needed)
pio test -e native
```

### Environments

| Env | Purpose | `WHEEL_ID` |
|-----|---------|------------|
| `left`   | Left wheel firmware   | `0x4C` ('L') |
| `right`  | Right wheel firmware  | `0x52` ('R') |
| `native` | Host-side Unity tests  | — |

### Build flags

Defined in `platformio.ini`:
- `-std=c++17`
- `-DCORE_DEBUG_LEVEL=3`
- `-DWheelAthlete_FW_MAJOR=1`
- `-DWheelAthlete_FW_MINOR=4`
- `-DWheelAthlete_FW_PATCH=0`
- `-DWHEEL_ID=0x4C` or `0x52` (per env)

### Libraries

- `m5stack/M5Unified @ ^0.1.16` — IMU + display
- `h2zero/NimBLE-Arduino @ ^1.4.1` — BLE

### Changing wheel side at runtime

Wheel side can be changed without reflashing via the `SET_WHEEL` BLE
command from the app's Board Settings page. The change is persisted to
NVS by `config_store` and survives power cycles.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| `pio: command not found` | Install PlatformIO (VS Code extension or `pip install platformio`) |
| Upload fails | Hold the M5 power button, retry; check USB-C cable is data-capable |
| `platformio.ini` env not found | Run `pio project init` if migrating |
| Monitor shows garbage | Check baud rate = 115200 |
| BLE not advertising | Power-cycle the M5; verify firmware flashed successfully |

---

## App — Build & Run

```bash
cd app

flutter pub get
flutter run -d <device-id>          # run on phone
flutter test                        # all unit + widget tests
flutter analyze                     # static analysis (strict config)

# Release builds
flutter build apk --release         # Android APK
flutter build appbundle --release   # Android App Bundle
flutter build ios --release         # iOS (requires macOS + Xcode)
```

### Find your device ID

```bash
flutter devices
```

Pick the physical phone (not emulators — BLE requires real hardware).

### Key dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_blue_plus` | `^2.3.9` | BLE |
| `flutter_riverpod` | `^3.3.2` | State management |
| `fl_chart` | `^1.2.0` | Charts |
| `csv` | `^8.0.0` | CSV export |
| `excel` | `^4.0.6` | Excel export |
| `share_plus` | `^13.2.0` | OS share sheet |
| `path_provider` | `^2.1.6` | Filesystem paths |
| `file_picker` | `12.0.0-beta.7` | Directory picker (pinned for share_plus compat) |
| `google_fonts` | `^8.1.0` | Inter + JetBrains Mono |

> `file_picker` is pinned to `12.0.0-beta.7` because it's the only series
> compatible with `share_plus 13.x` (win32 ^6). The stable 11.x line
> conflicts on win32 ^5.

### Strict analysis config

`analysis_options.yaml` enables:
- `strict-casts`
- `strict-inference`
- `strict-raw-types`
- `unawaited_futures: error`
- `always_use_package_imports`
- Extra lints (const, final, etc.)

`flutter analyze` must be clean before commit.

### iOS-specific

- Requires macOS + Xcode
- Open `ios/Runner.xcworkspace` in Xcode to set signing team
- BLE capability requires `NSBluetoothAlwaysUsage` in `Info.plist`
  (already configured)

### Android-specific

- Min SDK: check `android/app/build.gradle` (flutter_blue_plus requires 21+)
- BLE permissions: `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` (Android 12+)
  already in `AndroidManifest.xml`

### Troubleshooting

| Problem | Fix |
|---------|-----|
| `flutter_blue_plus` not found | `flutter pub get`; check pubspec.yaml |
| BLE scan finds nothing | Enable Bluetooth on phone; power on M5 modules; move closer |
| Connect fails | M5 may be connected to another phone — power-cycle it |
| App crashes on export | Check storage permissions on Android |
| `flutter analyze` errors | Fix all — strict config treats many as errors |
| iOS build fails | Check signing team in Xcode; ensure bundle ID is unique |

---

## Verifying the build

After flashing firmware and building the app:

1. Power on both M5 modules — LCD should show "WheelAthlete-L" / "-R"
2. Open the app → Connect tab → Scan
3. Both modules should appear as `WheelAthlete-L` and `WheelAthlete-R`
4. Connect both — Live tab should show realtime IMU values
5. Record a short session → check Browse → preview → export CSV
6. Open the CSV — verify `timestamp_synced_ms` is populated and L/R data
   is present

If all of the above works, the build is good.
