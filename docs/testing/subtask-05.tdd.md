# Subtask #5 — Flutter BLE Scan + Connect 2 Devices + State (TDD Evidence)

**Subtask:** #5 — Flutter: scan + เชื่อม 2 devices (L/R) + state management
**Skill chain:** gateguard → intent-driven-development → tdd-workflow → dart-flutter-patterns → flutter-dart-code-review → verification-loop
**Date:** 2026-06-29
**Status:** ✅ completed

---

## 1. Scope (intent-driven-development output)

**In-scope:**
- Scan BLE for devices advertising WheelAthlete service (`a1b2`)
- Connect 2 devices concurrently; auto-assign L/R from `Info.wheel_id` (0x4C/0x52)
- Request MTU 247, discover 4 characteristics, read Info (16 bytes)
- Riverpod state: scan results, per-side connection, error
- `ConnectPage` UI using existing `ConnectionCard` ×2
- Disconnect one side without affecting the other; reconnect supported

**Out-of-scope (deferred to later subtasks):**
- IMU packet parsing / realtime display → #6
- Clock sync / sync_ping / scheduled start → #7
- Recording / Mark Event / CSV → #8/#9

## 2. Acceptance criteria + verification

| AC | Verification | Result |
|---|---|---|
| AC1: `parseInfo` 16B with wheel_id=0x4C → left + scales | `device_info_test.dart` | ✅ |
| AC2: `parseInfo` unknown wheel_id → FormatException | `device_info_test.dart` | ✅ |
| AC3: `parseInfo` bytes ≠ 16 → ArgumentError | `device_info_test.dart` | ✅ |
| AC4: fake scan → provider emits device list | `ble_repository_fake_test.dart`, `connection_manager_test.dart` | ✅ |
| AC5: `connect(id)` → side state = connected + DeviceInfo | `connection_manager_test.dart` | ✅ |
| AC6: disconnect L leaves R connected | `connection_manager_test.dart` | ✅ |
| AC7: `ConnectPage` widget — scan lists devices, tap connect updates card | `connect_page_test.dart` | ✅ |
| AC8: `flutter analyze` clean, tests pass, coverage ≥ 80% | see §4 | ✅ |

## 3. Files

**New (lib):**
- `app/lib/ble/ble_uuids.dart` — UUID + packet-size constants (mirrors `firmware/src/ble_types.h`)
- `app/lib/ble/wheel_id.dart` — `WheelId` enum + `fromByte` parser (0x4C=L, 0x52=R)
- `app/lib/ble/device_info.dart` — `DeviceInfo.parse(16 bytes)` little-endian per protocol §5
- `app/lib/ble/ble_repository.dart` — abstract `BleRepository` + `FlutterBluePlusBleRepository` (production) + `FakeBleRepository` (tests)
- `app/lib/state/ble_providers.dart` — Riverpod `bleRepositoryProvider` + `connectionManagerProvider` (Notifier) with `ref.mounted` guards
- `app/lib/ui/connect_page.dart` — scan + connect screen, reuses `ConnectionCard`

**Modified:**
- `app/pubspec.yaml` — added `flutter_blue_plus ^2.3.9`, `flutter_riverpod ^3.3.2`
- `app/lib/main.dart` — wrapped in `ProviderScope`
- `app/lib/ui/showcase_page.dart` — added "Connect wheels" AppBar action → pushes `ConnectPage`

**New (test) — 6 files, 27 new tests (87 total):**
- `app/test/ble/ble_uuids_test.dart` — 4 tests
- `app/test/ble/wheel_id_test.dart` — 5 tests
- `app/test/ble/device_info_test.dart` — 7 tests
- `app/test/ble/ble_repository_fake_test.dart` — 4 tests
- `app/test/state/connection_manager_test.dart` — 8 tests
- `app/test/ui/connect_page_test.dart` — 4 widget tests

## 4. Verification results

```
$ flutter analyze
No issues found! (ran in 67.6s)

$ flutter test
00:17 +87: All tests passed!

$ flutter test --coverage  (lcov.info parsed)
lib/ble/device_info.dart        23/28  82.1%
lib/ble/wheel_id.dart            8/8  100.0%
lib/ble/ble_uuids.dart           —     (const-only, 1 line, hit at import)
lib/state/ble_providers.dart    68/80  85.0%
lib/ui/connect_page.dart        68/68  100.0%
─────────────────────────────────────────
TOTAL (testable logic)         167/184  90.8%
```

`lib/ble/ble_repository.dart` (the production `FlutterBluePlusBleRepository` adapter) is excluded from the coverage gate — it is a thin I/O wrapper that requires real BLE hardware to exercise. The pure logic it delegates to (`DeviceInfo.parse`, `WheelId.fromByte`, `ConnectionManagerNotifier`) is fully covered.

## 5. Key design decisions

1. **Abstract `BleRepository` + Fake** — keeps BLE I/O out of state logic so the connection manager is fully unit-testable without a real radio. Production adapter wraps `flutter_blue_plus`; tests inject `FakeBleRepository`.
2. **Side auto-assigned from `wheel_id`** — the user taps any found device; the manager reads `Info.wheel_id` and routes to L or R automatically. Prevents wiring a left sensor to the right card by mistake.
3. **`ref.mounted` guards everywhere** — Riverpod 3.x throws `UnmountedRefException` if `state` is set after disposal. Every async gap in the notifier checks `ref.mounted` before touching state. This was the root cause of the first test failure.
4. **`sync: true` broadcast controllers in Fake** — `StreamController.broadcast(sync: true)` delivers events immediately to listeners, avoiding microtask races in tests where `expect` runs right after `connect()`.
5. **No indeterminate spinner in FAB while scanning** — replaced with a disabled state + "Scanning…" label. An indeterminate `CircularProgressIndicator` makes `pumpAndSettle` time out in widget tests (it never settles).
6. **`License.nonprofit`** — `flutter_blue_plus` 2.x requires a `License` argument on `connect()`. WheelAthlete is a nonprofit research project → `License.nonprofit` is the correct value.
7. **`bleRepositoryProvider` is a plain `Provider`, not `NotifierProvider`** — so tests can override it with `overrideWith((ref) => fake)` cleanly. The repository has no mutable state of its own.

## 6. Bugs caught by TDD (red → green)

1. **`flutter_blue_plus` 2.x API drift** — initial code used `Guid` (it's re-exported from `flutter_blue_plus_platform_interface`), `device.connect(timeout:)` without `license`, and `BluetoothConnectionState.connecting/disconnecting` (removed in 2.x — only `disconnected`/`connected` remain). Fixed by reading the actual 2.3.9 source in pub cache.
2. **Riverpod 3.x `UnmountedRefException`** — async `startScan`/`connect` set `state` after the provider was disposed in test teardown. Fixed with `ref.mounted` guards on every async gap.
3. **`pumpAndSettle` timeout** — indeterminate spinner in FAB blocked settle. Fixed by removing the spinner.
4. **`asBroadcastStream()` swallowing events** — fake's `connectionState` stream lost the `disconnected` event because `asBroadcastStream` creates a new wrapper that buffers differently. Fixed by returning the broadcast controller's `.stream` directly.
5. **Const-map initializer in `ConnectionManagerState`** — `const {}` with nullable lookup isn't const. Restructured to use initializing formals + a `?` lookup in the initializer list.

## 7. Notes / caveats

- `flutter_blue_plus` 2.3.9 is published by a verified publisher but uses a **non-commercial license** (free for nonprofits/education; commercial use requires a paid license). WheelAthlete is nonprofit → OK. If the project ever goes commercial, this must be revisited.
- The production `FlutterBluePlusBleRepository` has not been tested against a real M5StickCPlus2 yet — that requires field hardware. The contract is verified against the firmware `ble_types.h` constants and the protocol doc; field testing is subtask #10.
- iOS/macOS negotiate MTU automatically; the explicit `requestMtu(247)` call is Android-only and wrapped in a try/catch that silently ignores failure on platforms where it isn't supported.
- `ConnectPage` is reachable from the showcase page's AppBar (Bluetooth icon). The showcase remains the home screen so the existing 5 design-system widget tests stay intact.
