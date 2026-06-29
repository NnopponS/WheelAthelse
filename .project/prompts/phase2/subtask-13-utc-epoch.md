---
PROMPT FOR SUBTASK #13: SET_UTC command + UTC_SET event + START_FIRED UTC stamp
---
Use `cpp-coding-standards` + `cpp-testing` + `tdd-workflow` + `intent-driven-development` for this subtask.

Context:
- Feature: Phase 2 firmware (Issue #1)
- Branch: `feat/phase2-firmware-issue-1`
- Subtask: #13
- Goal: Accept UTC epoch ms from the phone, echo it back via a Sync event, and stamp the scheduled START_FIRED event with the UTC start instant so the app can record it in session meta for camera alignment.
- Files: `firmware/src/ble_service.{h,cpp}`, `firmware/src/ble_types.h`, `firmware/test/test_ble_types.py`, `docs/ble-protocol.md`, `app/lib/ble/control_command.dart`, `app/lib/ble/sync_packet.dart` (mirror)
- Stack: PlatformIO + Arduino C++ (ESP32), NimBLE-Arduino

Steps:
1. Read `.project/plan.md` (Phase 2) + `.project/architecture.md` (§4 Time Sync) + `.project/progress.md`.
2. intent-driven-development: write explicit acceptance criteria for the UTC stamp contract (what the app expects in START_FIRED, edge cases when UTC not set).
3. Update `docs/ble-protocol.md` v1.1.0: document `SET_UTC` Control command (0x09, uint64 LE epoch ms), new Sync event `UTC_SET` (event_id + uint64 epoch echo), and the extended `START_FIRED` event payload (existing fields + uint64 utc_start_ms; 0 if UTC never set).
4. TDD: extend `firmware/test/test_ble_types.py` for `SET_UTC` encoding, `UTC_SET` parsing, and extended `START_FIRED` parsing (pure logic in `ble_types.h`).
5. Implement: store UTC epoch in RAM (set on `SET_UTC`); on scheduled start fire, compute `utc_start_ms = utc_epoch + (target_start_us - now_us)/1000` and include in `START_FIRED`. Emit `UTC_SET` echo on `SET_UTC`.
6. Mirror in app: add `setUtc` to `app/lib/ble/control_command.dart`; extend `sync_packet.dart` to parse `UTC_SET` + extended `START_FIRED`.
7. Verify: `pio run left/right` SUCCESS; `pytest firmware/test` all PASS; `flutter analyze` clean; `flutter test` green (new parsing tests).
8. Commit: `feat(fw): SET_UTC command + UTC_SET event + START_FIRED UTC stamp (#13)`
9. Update `.project/progress.md` row #13.

Definition of done: phone can set UTC; board echoes; START_FIRED carries UTC start instant; firmware + app parsing unit-tested; pio + pytest + flutter test green; protocol doc updated.
