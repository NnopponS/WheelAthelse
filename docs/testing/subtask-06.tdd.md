# Subtask #6 — TDD Evidence Report

## Scope
Flutter: parse IMU binary packet + realtime display using the design system.

## What was built

### Pure logic (host-testable, no Flutter/BLE)
- `app/lib/ble/imu_packet.dart`:
  - `ImuSample.parse(bytes, {offset})` — parses one 20-byte sample at exact
    byte offsets from BLE protocol §2.1 (seq u32 @0, t_device_us u32 @4,
    ax/ay/az/gx/gy/gz int16 @8–18, all little-endian).
  - `ImuSample.toReading(DeviceInfo)` — converts raw LSB → physical units
    (g, dps) using `accelScale` / `gyroScale` from Info (§2.3, §5).
  - `ImuPacketParser.parseBatch(bytes)` — parses `[uint8 count][sample_0]…`
    (§2.2). Validates count > 0, exact length match (no truncation/trailing).
  - `ImuSeqTracker` — stateful seq-gap tracker across batches. Detects
    forward gaps (dropped samples), handles uint32 wrap, ignores late/
    duplicate samples. Cumulative `totalGaps` counter.
  - `ImuPacketParser.parseBatchWithGaps(bytes, tracker)` — combines batch
    parsing + gap tracking, returns `ParsedBatch{samples, newGaps}`.

### State layer (Riverpod)
- `app/lib/state/imu_providers.dart`:
  - `WheelImuState` — per-side: streaming flag, latest ImuReading,
    sampleCount, dropCount, error.
  - `ImuStreamNotifier` — subscribes to `BleRepository.imuData(deviceId)`,
    parses batches via `ImuPacketParser.parseBatchWithGaps`, updates state
    with latest reading + cumulative counts. `start(side)` / `stop(side)`.
    `ref.mounted` guards on every async gap. Parse/stream errors set
    `error` + stop streaming. `stop` retains `latest` for UI.

### BLE repository extension
- `app/lib/ble/ble_repository.dart`:
  - Added `Stream<List<int>> imuData(String deviceId)` to abstract interface.
  - `FlutterBluePlusBleRepository.imuData` — resolves IMU Data characteristic
    from `servicesList` (flutter_blue_plus 2.x removed `servicesStream`),
    enables notify, forwards `lastValueStream` via a broadcast controller.
    (coverage-excluded — needs real hardware; field test is subtask #10.)
  - `FakeBleRepository.imuData` — returns a `sync: true` broadcast controller
    per device. `imuController(deviceId)` exposes it for test injection.

### UI layer
- `app/lib/ui/live_page.dart`:
  - `LivePage` — ConsumerWidget with two `_WheelPanel`s (L/R) in a
    `SingleChildScrollView` (so both panels always render, not just the
    visible viewport). Single Start/Stop FAB toggles streaming for all
    connected wheels.
  - `_WheelPanel` — Card with per-side identity color (`role.container`),
    `StatusBadge` (L/R tone), `_LiveDot` (static red dot — no animation to
    avoid `pumpAndSettle` timeout), `_MetricGrid` with 6 `LiveMetricTile`s
    (ax/ay/az in g, gx/gy/gz in °/s), sample count + drop count stats line.
  - Error text shown at panel level (even when no data yet).
- `app/lib/ui/connect_page.dart`:
  - Added "Live IMU" AppBar action (chart icon) — pushes `LivePage` when
    at least one wheel is connected, disabled otherwise.

## TDD workflow
1. RED: wrote `test/ble/imu_packet_test.dart` (26 tests) — parser, batch,
   gap tracker, wrap, truncation, scale conversion.
2. GREEN: implemented `imu_packet.dart` — all 26 pass.
3. RED: wrote `test/state/imu_providers_test.dart` (12 tests) — start/stop,
   notify updates, gap accumulation, error handling, dispose cleanup.
4. GREEN: extended `ble_repository.dart` + implemented `imu_providers.dart`
   — all 12 pass.
5. RED: wrote `test/ui/live_page_test.dart` (8 tests) — idle state, Start
   enable/disable, live values, Stop retains value, drop badge, error,
   both wheels independent.
6. GREEN: implemented `live_page.dart` + wired navigation — all 8 pass.

## Test results
- `flutter analyze`: **clean** (0 issues, strict mode)
- `flutter test`: **145/145 PASS** (was 99 before #6; +46 new tests)
  - `test/ble/imu_packet_test.dart`: 26 tests
  - `test/state/imu_providers_test.dart`: 12 tests
  - `test/ui/live_page_test.dart`: 8 tests
- Coverage (new files):
  - `lib/ble/imu_packet.dart`: **100%** (54/54 lines)
  - `lib/state/imu_providers.dart`: **98.4%** (62/63 lines)
  - `lib/ui/live_page.dart`: **100%** (97/97 lines)
  - `lib/ble/ble_repository.dart`: 100% of testable lines (FlutterBluePlus
    adapter coverage-excluded — needs real BLE hardware)
- `flutter build apk --debug`: failed due to malformed NDK download
  (environment issue, not code — delete `C:\Users\worap\Android\Sdk\ndk\
  28.2.13676358` and re-download). Code correctness verified by analyze +
  tests.

## Bugs caught by TDD
- `BytesBuilder.add()` returns `void` in Dart — cascade chain broke.
  Fixed by building body separately.
- Test scale values: initially used `1/16384` for gyro (wrong — protocol
  says `1/16.4` for ±2000 dps). Fixed test to use self-consistent scales.
- `servicesStream` deprecated in flutter_blue_plus 2.x (yields empty).
  Switched to `servicesList` (cached from connect) + broadcast controller.
- `FloatingActionButton.extended` is not `FilledButton` — test type
  assertion fixed to check `onPressed` nullability.
- `_LiveDot` infinite `AnimationController.repeat()` caused
  `pumpAndSettle` timeout — replaced with static dot.
- `ListView` doesn't build off-screen children in tests — switched to
  `SingleChildScrollView` + `Column` so both panels always render.

## Skills used
dart-flutter-patterns, tdd-workflow, gateguard, latency-critical-systems,
verification-loop
