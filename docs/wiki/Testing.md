# Testing

> v0.1.0 — Data Collection MVP

## Strategy

The codebase uses TDD throughout. Pure logic is separated from hardware
I/O so it can be tested on a host without any physical device.

### Three test layers

1. **Host-side pure-logic tests** (no hardware)
   - Firmware: Unity tests via `pio test -e native` + Python mirrors
   - App: Dart unit tests via `flutter test`

2. **Widget tests** (app only)
   - Every reusable component and every page has widget tests
   - Use Fake repositories (no real BLE or filesystem)

3. **Field test** (integration, manual)
   - The real `FlutterBluePlusBleRepository` adapter is excluded from
     automated coverage because it requires real BLE hardware
   - The field data collection protocol is the integration test

## Firmware tests

### Unity host tests (`pio test -e native`)

Cover pure logic in:
- `imu_types.h` — struct size (20 B), scale tables, rate math, FIFO byte
  parsing, timestamp interpolation
- `ble_types.h` — packet layout, command parsing, sync event encoding

### Python mirrors

`firmware/test/test_imu_types.py` and `test_ble_types.py` mirror the C++
tests for fast iteration without PlatformIO.

### Running

```bash
cd firmware
pio test -e native          # Unity tests
pytest test/                # Python mirrors
```

### Evidence reports

TDD evidence reports live in `docs/testing/`:
- `subtask-02-fix.tdd.md` — IMU acquisition bugs found + fixed
- `subtask-03.tdd.md` — BLE GATT implementation evidence
- (and others per subtask)

## App tests

### Unit tests

Cover:
- BLE packet parsing (`imu_packet_test.dart`)
- Device info parsing (`device_info_test.dart`)
- Wheel ID parsing (`wheel_id_test.dart`)
- Clock sync engine (`sync_engine_test.dart`)
- Recording state (`recording_providers_test.dart`)
- Storage repository (`storage_repository_test.dart`)
- Session stats (`session_stats_test.dart`)
- Quality badges (`quality_badge_test.dart`)
- Protocol templates (`protocol_template_test.dart`)
- CSV/Excel export (`csv_exporter_test.dart`, `excel_exporter_test.dart`)
- Resampler (`resampler_test.dart`)

### Widget tests

Cover:
- Every reusable component in `lib/widgets/`
- Every page in `lib/ui/`
- Theme + design system

### Running

```bash
cd app
flutter test                # all tests
flutter test --coverage     # with coverage report
flutter analyze             # static analysis (strict config)
```

### Coverage

- Testable logic coverage: ~90%+ across most modules
- `FlutterBluePlusBleRepository` excluded (needs real hardware)
- Coverage reports generated in `coverage/` after `flutter test --coverage`

### Strict analysis

`analysis_options.yaml` enables:
- `strict-casts`
- `strict-inference`
- `strict-raw-types`
- `unawaited_futures: error`
- `always_use_package_imports`
- Extra lints (const, final, etc.)

`flutter analyze` must be clean before any commit.

## Bugs caught by TDD (highlights)

### Firmware
- All samples in a batch got the same `micros()` → interpolated per-sample
- FIFO overflow not detected → now checks `INT_STATUS` + byte count ≥ 512
- Rate validation accepted arbitrary rates → only 50/100/200 Hz
- `static_assert(sizeof(ImuSample)==20)` added (BLE packet size guarantee)
- ES.46 narrowing fix in FIFO byte parsing

### App
- `flutter_blue_plus` 2.x API drift (Guid re-export, License required arg,
  connecting/disconnecting states removed)
- `UnmountedRefException` on async state set after dispose → `ref.mounted`
  guards on every async gap
- `pumpAndSettle` timeout from infinite spinner animation → removed
- `asBroadcastStream` swallowing events in tests
- `BytesBuilder.add` returns void (cascade broke)
- `servicesStream` deprecated in fbp 2.x → `servicesList + lastValueStream`
- `FloatingActionButton` vs `FilledButton` API confusion
- `ListView` off-screen children not built in tests

## CI

No CI pipeline is configured in v0.1.0. Tests run locally before commit.
Future: GitHub Actions for `flutter test` + `flutter analyze` + `pio test`.

## Test counts (v0.1.0)

- Firmware: 62+ host-side tests (Unity + Python)
- App: 200+ unit + widget tests
- All passing as of v0.1.0 tag
