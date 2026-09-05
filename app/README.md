# WheelAthlete Mobile App

Flutter application for **iOS and Android only**. The mobile app connects directly to the left/right WheelAthlete BLE sensors, previews realtime IMU data, records synchronized sessions, manages experiment metadata, and exports research data.

Current version: `1.8.0+9`

## Supported platforms

- Android
- iOS

The Flutter Windows and Web targets were retired and removed. Windows users should use the Python Research Edition in `../tools/pc_gui/`.

## Stack

- Flutter / Dart
- `flutter_blue_plus` — BLE
- `flutter_riverpod` — state management
- `fl_chart` — realtime/session charts
- `path_provider` — app storage
- `csv` / `excel` / `archive` — export
- `share_plus` / `file_picker` — sharing and save-to-device workflows

## Main capabilities

- scan/connect left and right sensor boards;
- automatic wheel-side/device-info handling;
- 50/100/200 Hz acquisition configuration;
- realtime Accel XYZ + Gyro XYZ values/charts;
- clock synchronization and synchronized recording lifecycle;
- topic/trial/session organization;
- protocol templates and experiment progress;
- tags, search/filter, preview, statistics, and quality indicators;
- CSV, Excel, and ZIP export workflows.

## Layout

```text
app/
├── android/              # Android runner/config
├── ios/                  # iOS runner/config
├── lib/
│   ├── main.dart         # mobile-only application entry point
│   ├── ble/              # BLE contract/parsing/adapters
│   ├── state/            # Riverpod state + sync/recording logic
│   ├── records/          # session/protocol/storage domain
│   ├── export/           # CSV/Excel/ZIP/export actions
│   ├── ui/               # user-facing pages
│   ├── widgets/          # reusable UI components
│   └── theme/            # design system
├── test/                 # unit + widget tests
└── pubspec.yaml
```

## Run and verify

```bash
flutter pub get
flutter run -d <physical-device-id>
flutter test
flutter analyze
```

BLE integration requires a physical device for real hardware validation.

## Release builds

```bash
flutter build apk --release
flutter build appbundle --release
# macOS + Xcode required:
flutter build ios --release
```

## Protocol

The canonical BLE contract is `../docs/ble-protocol.md`. Mobile, both firmware targets, and the Windows acquisition daemon must preserve compatible protocol semantics.
