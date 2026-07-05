# WheelAthlete — Phase 2: Field-Ready App & Firmware Enhancements

> Phase 1 (data collection) is complete — see `.project/phases/phase1/plan.md` and
> `.project/progress.md` (subtasks #1–#10). This plan covers the 6 enhancements
> the user requested after field testing, grouped into 3 GitHub issues by layer.

## Objective
Harden the WheelAthlete data-collection system for real field use: show live
battery % and RSSI after connect, make the board configurable in-app (name /
wheel side / sample rate), allow editing folder/topic/session metadata, make
share/export actually save or share CSV files, add realtime per-axis IMU line
charts, and rework the Record flow to sync time with the board, run a 5-second
countdown with 3-2-1 beep on the M5, and stamp each session with a UTC start
instant for camera alignment (hybrid UTC — inter-wheel sync still uses the
phone clock; UTC is for camera alignment only).

## Issues (grouped by layer)
- **Issue #1** — `feat(fw): Phase 2 firmware` → branch `feat/phase2-firmware-issue-1`
  - Battery Service, board config (NVS), UTC epoch command
- **Issue #2** — `feat(app): Phase 2 connectivity` → branch `feat/phase2-app-conn-issue-2`
  - Battery/RSSI display, board settings screen, record countdown + UTC stamp
- **Issue #3** — `feat(app): Phase 2 data` → branch `feat/phase2-app-data-issue-3`
  - Folder/topic/session editing, working share/export, realtime IMU charts

## Architecture changes (delta on Phase 1)
- **BLE**: add standard Battery Service `0x180F` + `0x2A19` (notify) alongside
  the existing custom service. Add a `Config` read characteristic (name /
  wheel_id / rate_hz / fw). Add Control commands `SET_NAME`, `SET_WHEEL`,
  `SET_UTC`. Bump protocol `docs/ble-protocol.md` to **v1.1.0**.
- **Time sync (hybrid UTC)**: keep the phone clock as the inter-wheel common
  timeline (`timestamp_synced_ms` unchanged). ADD: phone sends UTC epoch to the
  board on connect + on record start (`SET_UTC`); board stamps the scheduled
  `START_FIRED` event with the UTC instant; app writes `utc_start_ms` into
  `session_*_meta.json` so sessions can be aligned with the camera clock
  post-hoc. No NTP/RTC on the board — UTC is supplied by the phone.
- **Record flow**: tap "Start Recording" → SYNC_PING burst (offset estimate) →
  compute `T_start = now_phone + 5s` → send `SET_UTC` + scheduled `START` to
  both wheels → in-app countdown 5-4-3-2-1 → board beeps 3-2-1 → all start
  together. Cancellable.
- **Storage**: `StorageRepository` gains `renameTopic`, `updateTopicDescription`,
  `updateSessionMeta` (notes / video filename).
- **Charts**: `fl_chart` `LineChart` rolling window (~5s) per wheel, decimated
  to ~50 pts for performance.

## Tech stack
- Firmware: PlatformIO + Arduino C++ (ESP32), M5Unified, NimBLE-Arduino, `Preferences` (NVS)
- App: Flutter / Dart, flutter_blue_plus, flutter_riverpod, fl_chart, share_plus, path_provider, file_picker (new)
- Repo: Monorepo (firmware/ + app/)

## Subtasks (each = 1 session = 1 commit)

### Issue #1 — Firmware (branch `feat/phase2-firmware-issue-1`)
- [ ] **#11** Battery Service `0x180F` + `0x2A19` notify (battery % from `M5.Power.getBatteryLevel()`)
      — skill: `cpp-coding-standards` + `cpp-testing` + `tdd-workflow`
- [ ] **#12** Board config: `SET_NAME` / `SET_WHEEL` / persist `SET_RATE` to NVS + `Config` read char
      — skill: `cpp-coding-standards` + `cpp-testing` + `tdd-workflow` + `gateguard`
- [ ] **#13** `SET_UTC` command + `UTC_SET` Sync event + `START_FIRED` UTC stamp + protocol doc v1.1.0
      — skill: `cpp-coding-standards` + `cpp-testing` + `tdd-workflow` + `intent-driven-development`

### Issue #2 — App connectivity (branch `feat/phase2-app-conn-issue-2`)
- [ ] **#14** Battery % + RSSI live display (subscribe Battery Service + periodic `readRssi` + ConnectionCard)
      — skill: `dart-flutter-patterns` + `flutter-dart-code-review` + `tdd-workflow` + `verification-loop`
- [ ] **#15** Board Settings screen (read Config char, write SET_NAME/SET_WHEEL/SET_RATE)
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `gateguard` + `verification-loop`
- [ ] **#16** Record countdown + scheduled start + UTC session stamp (uses `ScheduledStart`, `MinRttTracker`)
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `latency-critical-systems` + `intent-driven-development` + `verification-loop`

### Issue #3 — App data (branch `feat/phase2-app-data-issue-3`)
- [ ] **#17** Edit folder/topic/session metadata (rename topic, edit description + session notes/video)
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `verification-loop`
- [ ] **#18** Wire share/export (share_plus sheet + save-to-device via file_picker)
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `verification-loop`
- [ ] **#19** Realtime IMU line charts (fl_chart, per axis, rolling window, decimated)
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `latency-critical-systems` + `verification-loop`

## Dependency graph
```
Issue #1 (firmware)
  #11 (battery svc) ──┐
  #12 (config+NVS) ───┤
  #13 (UTC cmd) ──────┘
        │
        ▼  (new chars/commands available; can be stubbed via FakeBleRepository earlier)
Issue #2 (app connectivity)
  #14 (battery/RSSI) ◄── #11
  #15 (board settings) ◄── #12
  #16 (record countdown+UTC) ◄── #13 + sync_engine (#7)

Issue #3 (app data)  — independent of #1/#2
  #17 (folder editing)
  #18 (share/export)
  #19 (realtime charts) ◄── imuStreamProvider (#6)
```
- Issue #3 is independent and can proceed in parallel with #1/#2.
- #14/#15/#16 can start against `FakeBleRepository` stubs before firmware #1 lands.

## Stack-specific skills to use
| Layer | Build skill | Test skill | Verify skill |
|---|---|---|---|
| Firmware C++ | `cpp-coding-standards` | `cpp-testing` + `tdd-workflow` | `cpp-build` (pio run) |
| Flutter app | `dart-flutter-patterns` | `tdd-workflow` + `flutter-dart-code-review` | `verification-loop` (flutter analyze + test) |
| Cross-cutting | `gateguard` (investigate before edit), `intent-driven-development` (acceptance criteria), `latency-critical-systems` (sync/charts) | — | — |

## Progress
See `.project/progress.md` (Phase 2 subtasks #11–#19 appended below Phase 1).

## How to continue (cross-session)
1. New session → run the **build** skill, or paste a subtask prompt from `.project/prompts/phase2/`.
2. build skill reads this `plan.md` + `architecture.md` + `progress.md` first.
3. One subtask per session: write tests first (TDD), implement, verify, commit, update `progress.md`.
