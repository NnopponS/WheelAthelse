---
PROMPT FOR SUBTASK #15: Board Settings screen (name/wheel/rate)
---
Use `dart-flutter-patterns` + `tdd-workflow` + `gateguard` + `verification-loop` for this subtask.

Context:
- Feature: Phase 2 app connectivity (Issue #2)
- Branch: `feat/phase2-app-conn-issue-2`
- Subtask: #15
- Goal: Add a Board Settings screen reachable from the Connect page per connected wheel, to edit board name, wheel side (L/R), and sample rate (50/100/200 Hz) via the Config char + SET_NAME/SET_WHEEL/SET_RATE commands.
- Files: `app/lib/ble/ble_repository.dart`, `app/lib/ble/ble_uuids.dart`, `app/lib/ble/control_command.dart`, `app/lib/state/ble_providers.dart`, `app/lib/ui/board_settings_page.dart` (NEW), `app/lib/ui/connect_page.dart`, `app/test/...` (new tests)
- Stack: Flutter / Dart, flutter_blue_plus, flutter_riverpod

Steps:
1. Read `.project/plan.md` (Phase 2) + `.project/architecture.md` + `.project/progress.md`.
2. gateguard: confirm firmware Config char (a1b7) layout + SET_NAME/SET_WHEEL command IDs from subtask #12 / `docs/ble-protocol.md` v1.1.0 before writing app parsers.
3. TDD: write tests first — `BoardConfig.parse(List<int>)` for the 22B Config char; `ControlCommand.setName` / `setWheel` encoders; a `BoardSettingsNotifier` that reads Config + writes commands via FakeBleRepository.
4. Add `readConfig(deviceId)` to `BleRepository` + impls; add `setName` / `setWheel` to `ControlCommand`.
5. Implement `BoardSettingsPage`: form with name (text field, max 16), wheel side (segmented L/R), rate (dropdown 50/100/200), Save button that writes the three commands; loads current values from Config on open.
6. Wire entry point: per-wheel "Settings" action on `ConnectPage` ConnectionCard → push `BoardSettingsPage`.
7. Verify: `flutter analyze` clean; `flutter test` green; widget test for the settings page.
8. Commit: `feat(app): board settings screen — name/wheel/rate (#15)`
9. Update `.project/progress.md` row #15.

Definition of done: user can read + edit board name/wheel/rate in-app; changes persist on the board (NVS); unit + widget tested; flutter analyze + test green.
