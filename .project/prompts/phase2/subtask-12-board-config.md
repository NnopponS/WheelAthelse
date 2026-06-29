---
PROMPT FOR SUBTASK #12: Board config (name/wheel/rate) + NVS + Config char
---
Use `cpp-coding-standards` + `cpp-testing` + `tdd-workflow` + `gateguard` for this subtask.

Context:
- Feature: Phase 2 firmware (Issue #1)
- Branch: `feat/phase2-firmware-issue-1`
- Subtask: #12
- Goal: Make board name, wheel side, and sample rate runtime-configurable and persisted to NVS; expose current config via a new read characteristic.
- Files: `firmware/src/ble_service.{h,cpp}`, `firmware/src/ble_types.h`, `firmware/src/config_store.{h,cpp}` (NEW), `firmware/src/main.cpp`, `firmware/test/test_ble_types.py`, `firmware/test/test_config_store.py` (NEW), `docs/ble-protocol.md`, `app/lib/ble/ble_uuids.dart` (mirror UUIDs)
- Stack: PlatformIO + Arduino C++ (ESP32), NimBLE-Arduino, `Preferences` (NVS)

Steps:
1. Read `.project/plan.md` (Phase 2) + `.project/architecture.md` + `.project/progress.md`.
2. gateguard: investigate how `WHEEL_ID` build flag flows into `main.cpp` + `ble_service.cpp`, and how `imu().setRate()` is called, before editing.
3. Update `docs/ble-protocol.md` v1.1.0: document new Control commands `SET_NAME` (0x07, 16-byte name), `SET_WHEEL` (0x08, 0x4C/0x52) and the new `Config` read characteristic (UUID a1b7) layout: `[name 16B][wheel_id 1B][rate_hz 2B LE][fw_major 1B][fw_minor 1B][fw_patch 1B]` = 22B.
4. TDD: write `firmware/test/test_config_store.py` + extend `test_ble_types.py` for new command parsing/encoding (pure logic in `config_store.h` / `ble_types.h`).
5. Implement `config_store` using `Preferences` (NVS namespace "wacfg"): load on boot, save on SET_NAME/SET_WHEEL/SET_RATE. Cache rate in RAM, persist on stop/disconnect to limit NVS wear.
6. Implement `Config` read characteristic (a1b7) returning the 22B layout. Handle `SET_NAME`/`SET_WHEEL` in the Control write callback; update advertised name + Info `wheel_id` on `SET_WHEEL`.
7. Update `main.cpp` boot sequence: load config from NVS before `ble().begin()`; pass name + wheel to BLE init.
8. Mirror new UUIDs/constants in `app/lib/ble/ble_uuids.dart`.
9. Verify: `pio run left/right` SUCCESS; `pytest firmware/test` all PASS.
10. Commit: `feat(fw): runtime board config + NVS persistence + Config char (#12)`
11. Update `.project/progress.md` row #12.

Definition of done: name/wheel/rate settable at runtime, survive reboot; Config char readable; pure logic unit-tested; pio + pytest green; protocol doc + app UUIDs updated.
