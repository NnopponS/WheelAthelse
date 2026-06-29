---
PROMPT FOR SUBTASK #14: Battery % + RSSI live display after connect
---
Use `dart-flutter-patterns` + `flutter-dart-code-review` + `tdd-workflow` + `verification-loop` for this subtask.

Context:
- Feature: Phase 2 app connectivity (Issue #2)
- Branch: `feat/phase2-app-conn-issue-2`
- Subtask: #14
- Goal: After connect, show live battery % (from Battery Service 0x2A19) and RSSI (refreshed periodically) on each ConnectionCard.
- Files: `app/lib/ble/ble_repository.dart`, `app/lib/ble/ble_uuids.dart`, `app/lib/state/ble_providers.dart`, `app/lib/widgets/connection_card.dart`, `app/test/...` (new tests), `app/pubspec.yaml` (if needed)
- Stack: Flutter / Dart, flutter_blue_plus, flutter_riverpod

Steps:
1. Read `.project/plan.md` (Phase 2) + `.project/architecture.md` + `.project/progress.md`.
2. Read `app/lib/state/ble_providers.dart` — note `WheelConnection` has `rssi` but `connect()` never sets it; no battery field exists.
3. TDD: write tests first using `FakeBleRepository` — add a `batteryLevel(deviceId)` stream + `readRssi` polling; assert `WheelConnection` gets `batteryPercent` + `rssi` updated.
4. Add `batteryLevel(String deviceId)` stream to `BleRepository` (subscribe to 0x2A19) + impl in `FlutterBluePlusBleRepository` + `FakeBleRepository`.
5. Add `batteryPercent` to `WheelConnection`; in `ConnectionManagerNotifier.connect()` subscribe to battery + start a periodic `readRssi` (every 2s while connected) and update state.
6. Update `ConnectionCard` to render battery % (icon + number) and RSSI dBm when connected.
7. Verify: `flutter analyze` clean; `flutter test` green; coverage on new logic >= 90%.
8. Commit: `feat(app): live battery % + RSSI display after connect (#14)`
9. Update `.project/progress.md` row #14.

Definition of done: both ConnectionCards show battery % + RSSI live after connect; unit-tested with FakeBleRepository; flutter analyze + test green.
