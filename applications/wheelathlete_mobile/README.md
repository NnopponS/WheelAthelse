# WheelAthlete Mobile Application

Flutter application for **iOS and Android only**. The mobile app connects directly to the left/right WheelAthlete BLE sensors, previews realtime IMU data, records synchronized sessions, manages experiment metadata, and exports research data.

Current version: `1.8.0+10`

## Supported platforms

- Android
- iOS

The Flutter Windows and Web targets were retired and removed. Windows users should use the Python Research Edition in `../wheelathlete_windows/tools/pc_gui/`.

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
- automatic wheel-side/device-info handling for **M5StickC Plus2** and **Seeed XIAO nRF52840 Sense** firmware `1.8.0`;
- 50/100/200 Hz acquisition configuration;
- realtime Accel XYZ + Gyro XYZ values/charts;
- PC-parity clock synchronization and scheduled START/STOP recording lifecycle;
- topic/trial/session organization;
- protocol templates and experiment progress;
- tags, search/filter, preview, statistics, and quality indicators;
- CSV, Excel, and ZIP export workflows;
- experimental BiWheel3D 2D trajectory inference from a finalized dual-wheel session.

## BLE reliability and firmware 1.8.0

The mobile acquisition path follows the same reliability rules as the Python Research Edition:

```text
BLE notification callback
  -> immutable byte copy
  -> bounded 512-notification queue per wheel
  -> long-lived parser isolate
  -> sequence/replay recovery
  -> Live / Recording consumers
```

The callback never performs chart rendering, model inference, or heavy packet processing. Queue overflow and malformed packets fail closed and are surfaced as acquisition faults instead of silently overwriting unread data. Before a recording is finalized, accepted notifications are drained with a join barrier so data already received by BLE cannot be lost during Stop.

Live and Record both synchronize device clocks using completed round trips, midpoint observations, uint32 `micros()` rollover unwrapping, and a lowest-RTT clock fit. Both wheels receive device-local scheduled START targets derived from one common phone-monotonic start instant; normal operation does not use `START(0)`.

## BiWheel3D trajectory preview

Session Preview runs the validated **BiWheel3D M4 TCN + bidirectional LSTM** model directly on the phone using ONNX Runtime. No PC, Wi-Fi, internet connection, or inference server is required.

The mobile pipeline keeps the Windows research adapter contract:

```text
finalized dual-wheel session
  -> synchronize and resample to 100 Hz
  -> acceleration g -> m/s^2
  -> gyro deg/s -> rad/s
  -> group raw samples as (T, 5, 12)
  -> BiWheel3D 90-feature extraction
  -> bundled ONNX normalization + TCN/BiLSTM + physics integration
  -> initial-travel XY alignment
  -> equal-scale 2D trajectory plot
```

The bundled model asset is `assets/models/wheelathlete_biwheel3d_m4.onnx` (about 6.44 MB). Its ONNX output was numerically checked against the PyTorch M4 reference over dynamic sequence lengths from 40 to 1,535 model steps; the largest observed absolute difference was below `7e-6`. A Python-generated fixture also verifies the Dart 90-feature extractor.

Because M4 contains a **bidirectional LSTM**, trajectory analysis is intentionally offline/buffered: record and finalize the session first, then select **Generate 2D trajectory** in Session Preview. It is not a causal zero-latency position estimator.

The BiWheel3D model/runtime material is distributed under its MIT license; the license notice is bundled beside the model asset as `assets/models/BIWHEEL3D_LICENSE.txt`.

## Layout

```text
applications/wheelathlete_mobile/
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

## Automatic updates

Release/profile builds check the stable WheelAthlete GitHub Releases manifest after startup and every six hours. Manual **Software update** checking is always available from the Home AppBar.

Android downloads the release APK to the app cache, verifies the manifest byte size and SHA-256, then hands the file to Android's system installer through a private `FileProvider`. Installation is never launched during Live, countdown, or recording. Android may ask the operator to enable **Install unknown apps** for WheelAthlete. Public/direct-GitHub releases must always use the same persistent signing key.

iOS uses the same update manifest for discovery but opens the configured App Store/TestFlight page for installation.

## Release builds

```bash
flutter build apk --release
flutter build appbundle --release
# macOS + Xcode required:
flutter build ios --release
```

## Protocol

The canonical BLE contract is `../../docs/ble-protocol.md`. Mobile, both firmware targets, and the Windows acquisition daemon must preserve compatible protocol semantics.
