---
PROMPT FOR SUBTASK #11: Battery Service 0x180F + 0x2A19 notify
---
Use `cpp-coding-standards` + `cpp-testing` + `tdd-workflow` for this subtask.

Context:
- Feature: Phase 2 firmware (Issue #1)
- Branch: `feat/phase2-firmware-issue-1`
- Subtask: #11
- Goal: Expose battery % over the standard BLE Battery Service so the app can show it after connect.
- Files: `firmware/src/ble_service.h`, `firmware/src/ble_service.cpp`, `firmware/src/ble_types.h`, `firmware/test/test_ble_types.py`, `docs/ble-protocol.md`
- Stack: PlatformIO + Arduino C++ (ESP32), M5Unified, NimBLE-Arduino

Steps:
1. Read `.project/plan.md` (Phase 2) + `.project/architecture.md` + `.project/progress.md` for full context.
2. Read `firmware/src/ble_service.cpp` to see how the existing custom GATT service is built with NimBLE.
3. Update `docs/ble-protocol.md` to v1.1.0: document the new Battery Service (0x180F) + Battery Level char (0x2A19, notify, uint8 0-100%).
4. Write tests first (TDD): add Python host tests in `firmware/test/test_ble_types.py` for any new pure logic (e.g. battery-level clamping/encoding helpers in `ble_types.h`).
5. Implement: add a second NimBLE service (Battery Service) with a `0x2A19` characteristic that notifies `M5.Power.getBatteryLevel()` (0-100). Update battery level periodically (e.g. every 5s) in `loop()` / `bleTask()`, and notify only on change.
6. Verify: `pio run left/right` SUCCESS; `pytest firmware/test` all PASS.
7. Commit with conventional commit message: `feat(fw): expose battery level over BLE Battery Service (#11)`
8. Update `.project/progress.md` row #11 with status + commit hash.

Definition of done: Battery Service advertises alongside the custom service; app can subscribe to 0x2A19 and receive 0-100% updates; pure logic unit-tested; pio + pytest green.
