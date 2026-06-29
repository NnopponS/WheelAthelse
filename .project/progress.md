# Progress Tracker

| # | Subtask | Skill | Status | Started | Completed | Commit |
|---|---------|-------|--------|---------|-----------|--------|
| 1 | Scaffolding + monorepo + git/GitHub + BLE/sync/folder protocol spec | git-workflow | completed | 2026-06-28 | 2026-06-28 | f10ffd6 |
| 2 | Firmware: IMU read + display + serial debug | cpp-coding-standards + tdd-workflow + cpp-testing | completed | 2026-06-28 | 2026-06-28 | c8301ce → b019f74 (TDD fix) |
| 3 | Firmware: BLE GATT + time-sync support | cpp-coding-standards + tdd-workflow + cpp-testing + gateguard + intent-driven-development + latency-critical-systems | completed | 2026-06-28 | 2026-06-28 | dace23b |
| 4 | Flutter: design system / theme / components (UI สวย) | impeccable + ui-ux-pro-max | completed | 2026-06-28 | 2026-06-28 | 9583327 |
| 5 | Flutter: scan + connect 2 devices + state | dart-flutter-patterns + tdd-workflow + gateguard + intent-driven-development + flutter-dart-code-review + verification-loop | completed | 2026-06-29 | 2026-06-29 | (commit pending) |
| 6 | Flutter: parse packet + realtime display | dart-flutter-patterns | pending | - | - | - |
| 7 | Flutter: clock sync engine (offset/drift/common timeline) | dart-flutter-patterns | pending | - | - | - |
| 8 | Flutter: recording + Mark Event + folder topic/trial | dart-flutter-patterns | pending | - | - | - |
| 9 | Flutter: CSV export (synced) + folder hierarchy + share | dart-flutter-patterns | pending | - | - | - |
| 10 | Docs: data-collection protocol + field test (verify sync) | tdd-workflow | pending | - | - | - |

## Notes / Blockers
- 2026-06-28: subtask #1 done. Repo: https://github.com/NnopponS/WheelAthlete (private)
  - BLE protocol v1.0.0 in docs/ble-protocol.md (UUIDs, packet layout, control/sync/info, CSV schema, folder model)
  - Next: #2 (firmware IMU) and #4 (Flutter design system) can run in parallel after #1
- 2026-06-28: subtask #2 TDD fix done (commit b019f74). Found 6 bugs via cpp-testing review:
  - timestamp: all samples in batch got same micros() → interpolated per-sample
  - FIFO overflow: not detected → now checks INT_STATUS + byte count >= 512
  - rate validation: accepted arbitrary rates → only 50/100/200 Hz
  - static_assert(sizeof(ImuSample)==20) added (BLE packet size guarantee)
  - ES.46 narrowing fix in FIFO byte parsing
  - extracted pure logic to imu_types.h (host-testable)
  Tests: 28 Python unit tests (test_imu_types.py) + C++ Unity test file + evidence report
  (docs/testing/subtask-02-fix.tdd.md). pytest 28/28 PASS, pio run left/right SUCCESS.
- 2026-06-28: subtask #3 done (commit dace23b). BLE GATT via NimBLE-Arduino:
  - GATT Service (a1b2) + 4 chars: IMU Data (a1b3 Notify), Control (a1b4 Write),
    Sync (a1b5 Notify+Indicate), Info (a1b6 Read)
  - IMU batch notify: [count][samples], max batch from MTU (12 at MTU 247)
  - Control: START/STOP/SET_RATE/SYNC_PING/SET_RANGE/BEEP/RESET_SEQ + CMD_NACK
  - Sync: SYNC_RESPONSE (12B) + events (START_FIRED/STOP_FIRED/DROP_COUNT/CMD_NACK)
  - Info: 16B (wheel_id, fw, ranges, scales, reserved)
  - Time-sync: sync_ping captured in NimBLE callback (lowest latency path)
  - Scheduled start: wait micros >= target_start_us + countdown beep 3-2-1
  - Beep: M5.Speaker.tone() — 880 Hz countdown + 1320 Hz start
  - BLE streaming in Arduino loop (Core 1), separate from IMU acquisition (Core 0)
  - Pure logic in ble_types.h (host-testable), hardware in ble_service.cpp
  Tests: 34 new tests (test_ble_types.py) + 28 imu = 62 total PASS
  pio run left/right SUCCESS. Evidence: docs/testing/subtask-03.tdd.md


  - deps: google_fonts, fl_chart. Design system in app/lib/theme/ (palette, dimens, typography,
    WheelAthleteColors ThemeExtension for L=blue/R=orange + semantic, light+dark high-contrast ThemeData).
  - components in app/lib/widgets/: ConnectionCard, LiveMetricTile, PrimaryActionButton,
    MarkEventButton, SessionListItem, StatusBadge, EmptyState, LoadingState, ErrorState.
  - app/lib/ui/showcase_page.dart = living style guide (home), theme toggle, animated mock metrics.
  - verify: `flutter analyze` clean; widget test passes (renders + theme toggle). UI not wired to BLE (mock).
  - Next: #5 (BLE scan + connect 2 devices) reuses theme + ConnectionCard.
- 2026-06-28: subtask #4 code review (flutter-dart-code-review + tdd-workflow) follow-up:
  - hardened analysis_options.yaml: strict-casts/inference/raw-types + extra lints (const, final,
    unawaited_futures=error, always_use_package_imports, etc). Converted lib/ to package: imports,
    fixed const issues. `flutter analyze` clean under strict config.
  - added test suite: 34 tests across theme + every component (WheelAthlete_colors, status_badge,
    live_metric_tile, primary_action_button, mark_event_button, connection_card, session_list_item,
    state_views) + test/helpers/pump.dart. Coverage 95.2% lines (501/526).
- 2026-06-29: subtask #5 done. BLE scan + connect 2 devices + Riverpod state.
  - deps: flutter_blue_plus ^2.3.9 (nonprofit license), flutter_riverpod ^3.3.2.
  - new lib: ble/ble_uuids.dart (UUIDs sync firmware ble_types.h), ble/wheel_id.dart
    (0x4C=L/0x52=R parser), ble/device_info.dart (Info 16B little-endian parser),
    ble/ble_repository.dart (abstract + FlutterBluePlus impl + Fake for tests),
    state/ble_providers.dart (connectionManagerProvider Notifier with ref.mounted guards,
    auto-assigns side from wheel_id), ui/connect_page.dart (scan + connect, reuses
    ConnectionCard ×2).
  - modified: main.dart (ProviderScope), showcase_page.dart (AppBar "Connect wheels"
    action → push ConnectPage), pubspec.yaml (+deps).
  - design: abstract BleRepository + Fake keeps BLE I/O out of state logic → fully
    unit-testable. Side auto-assigned from Info.wheel_id (user can't wire L sensor to
    R card). ref.mounted guards on every async gap (Riverpod 3.x throws
    UnmountedRefException otherwise). Fake uses sync broadcast controllers to avoid
    microtask races in tests. No indeterminate spinner in FAB (would block
    pumpAndSettle).
  - bugs caught by TDD: flutter_blue_plus 2.x API drift (Guid re-export, License
    required arg, connecting/disconnecting states removed), UnmountedRefException
    on async state set after dispose, pumpAndSettle timeout from spinner,
    asBroadcastStream swallowing events, const-map initializer issue.
  - Tests: 27 new (87 total) PASS. flutter analyze clean. Coverage on testable
    logic 90.8% (device_info 82%, wheel_id 100%, ble_providers 85%, connect_page
    100%). Production FlutterBluePlusBleRepository adapter excluded (needs real
    hardware — field test is subtask #10).
  - Evidence: docs/testing/subtask-05.tdd.md
  - Next: #6 (parse IMU packet + realtime display) needs #5 connect + #3 firmware.
