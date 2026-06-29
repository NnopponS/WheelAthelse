# Progress Tracker

| # | Subtask | Skill | Status | Started | Completed | Commit |
|---|---------|-------|--------|---------|-----------|--------|
| 1 | Scaffolding + monorepo + git/GitHub + BLE/sync/folder protocol spec | git-workflow | completed | 2026-06-28 | 2026-06-28 | f10ffd6 |
| 2 | Firmware: IMU read + display + serial debug | cpp-coding-standards + tdd-workflow + cpp-testing | completed | 2026-06-28 | 2026-06-28 | c8301ce → b019f74 (TDD fix) |
| 3 | Firmware: BLE GATT + time-sync support | cpp-coding-standards + tdd-workflow + cpp-testing + gateguard + intent-driven-development + latency-critical-systems | completed | 2026-06-28 | 2026-06-28 | dace23b |
| 4 | Flutter: design system / theme / components (UI สวย) | impeccable + ui-ux-pro-max | completed | 2026-06-28 | 2026-06-28 | 9583327 |
| 5 | Flutter: scan + connect 2 devices + state | dart-flutter-patterns + tdd-workflow + gateguard + intent-driven-development + flutter-dart-code-review + verification-loop | completed | 2026-06-29 | 2026-06-29 | 3d132fc |
| 6 | Flutter: parse packet + realtime display | dart-flutter-patterns + tdd-workflow + gateguard + latency-critical-systems + verification-loop | completed | 2026-06-29 | 2026-06-29 | 9b0e199 |
| 7 | Flutter: clock sync engine (offset/drift/common timeline) | dart-flutter-patterns + tdd-workflow + gateguard + latency-critical-systems + intent-driven-development + verification-loop | completed | 2026-06-29 | 2026-06-29 | f604f32 |
| 8 | Flutter: recording + Mark Event + folder topic/trial | dart-flutter-patterns + tdd-workflow + gateguard + verification-loop | completed | 2026-06-29 | 2026-06-29 | (see commit) |
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
- 2026-06-29: subtask #6 done. Parse IMU binary packet + realtime display.
  - new lib: ble/imu_packet.dart (ImuSample.parse 20B little-endian per §2.1,
    toReading converts raw→g/dps via DeviceInfo scales §2.3, ImuPacketParser.
    parseBatch [count][samples] §2.2 with length validation, ImuSeqTracker
    detects forward gaps + uint32 wrap + cumulative dropCount,
    parseBatchWithGaps combines both), state/imu_providers.dart
    (ImuStreamNotifier Riverpod Notifier: subscribes to BleRepository.imuData,
    parses batches, updates WheelImuState per side with latest ImuReading +
    sampleCount + dropCount, ref.mounted guards, start/stop methods, error
    handling stops streaming, stop retains latest for UI), ui/live_page.dart
    (two _WheelPanel cards with per-side identity colors from design system,
    6 LiveMetricTile per panel ax/ay/az/gx/gy/gz, sample+drop count stats,
    single Start/Stop FAB toggles both connected wheels, SingleChildScrollView
    so both panels always render, static _LiveDot no animation to avoid
    pumpAndSettle timeout).
  - modified: ble/ble_repository.dart (+imuData abstract + FlutterBluePlus impl
    using servicesList+lastValueStream broadcast controller since fbp 2.x
    deprecated servicesStream + FakeBleRepository.imuData with sync broadcast
    controllers + imuController test helper), ui/connect_page.dart (+Live IMU
    AppBar action pushes LivePage when any wheel connected).
  - bugs caught by TDD: BytesBuilder.add returns void (cascade broke),
    test gyro scale 1/16384 vs protocol 1/16.4, servicesStream deprecated
    in fbp 2.x, FloatingActionButton not FilledButton, _LiveDot infinite
    animation pumpAndSettle timeout, ListView off-screen children not built.
  - Tests: 46 new (26 imu_packet + 12 imu_providers + 8 live_page) = 145
    total PASS. flutter analyze clean. Coverage: imu_packet 100%, imu_providers
    98.4%, live_page 100%, ble_repository 100% testable (adapter excluded).
  - Build: flutter build apk failed due to malformed NDK download (env issue,
    not code — delete ndk\28.2.13676358 and re-download).
  - Evidence: docs/testing/subtask-06.tdd.md
  - Next: #7 (clock sync engine) needs #6 stream + #3 firmware sync support.
- 2026-06-29: subtask #7 done. Clock sync engine (offset/drift/scheduled start).
  - new lib: ble/sync_packet.dart (SyncEvent.parse sealed class — parses
    [event_id][payload] notify payloads verified against firmware ble_service.cpp
    handleSyncPing: SyncResponseEvent 0x00 13B, DropCountEvent 0x10 5B,
    CmdNackEvent 0x20 2B, StartFiredEvent 0x30 5B, StopFiredEvent 0x40 9B,
    throws ArgumentError on truncated, FormatException on unknown),
    ble/control_command.dart (ControlCommand encoders for all §3.1 commands:
    START 5B, STOP 1B, SET_RATE 3B validates 50/100/200, SYNC_PING 5B,
    SET_RANGE 3B validates 0-3, BEEP 4B validates count>0, RESET_SEQ 1B),
    state/sync_engine.dart (OffsetEstimate.compute NTP-lite §4.2 RTT+offset,
    MinRttTracker keeps lowest-RTT estimate, DriftFit.fit OLS linear regression
    §4.3 slope+intercept+residualRMS+toSyncedMs, ScheduledStart.compute §3.2
    phone→device micros conversion), state/sync_providers.dart
    (SyncEngineNotifier Riverpod: sendPing writes SYNC_PING + records T1
    relative to first ping to fit uint32, startListening subscribes to
    BleRepository.syncData + dispatches SyncEvent subclasses to update state,
    sendStart/sendStop/sendResetSeq write Control commands, ref.mounted guards,
    error handling).
  - modified: ble/ble_repository.dart (+syncData stream abstract + FlutterBluePlus
    impl using servicesList+lastValueStream broadcast + Fake with sync: true
    controllers + syncController test helper + writeControl abstract + impl +
    Fake with lastControlWrite recorder).
  - bugs caught by TDD: uint32 overflow (DateTime.now().millisecondsSinceEpoch
    ~1.78e12 overflows uint32 t_app_ms → fixed with relative timestamps),
    test offset expectations (RTT ~4ms not 0 with sync controller → range-based
    assertions), first ping t_app_ms=0 (relative → >= 0 not > 0), copyWith
    sentinel pattern (Object? not PendingPing?), unused seqPing pattern
    variable, dangling library doc comment (added library;), fake repos in
    connection_manager_test missing new abstract methods.
  - Tests: 59 new (13 sync_packet + 13 control_command + 18 sync_engine +
    15 sync_providers) = 204 total PASS. flutter analyze clean.
    Coverage: sync_packet 95.5%, control_command 100%, sync_engine 100%,
    sync_providers 92.6%, ble_repository 100% testable.
  - Evidence: docs/testing/subtask-07.tdd.md
  - Next: #8 (recording session + Mark Event + folder topic/trial) needs #7
    sync + #6 IMU stream.
- 2026-06-29: subtask #8 done. Recording session + Mark Event + folder topic/trial.
  - new lib: records/session_model.dart (MarkerEvent sync marker, SessionConfig
    pre-recording config with trialFolderName zero-pad + sessionId hex timestamp,
    SessionMeta post-recording metadata with full JSON ser/deser + null-safe
    optional fields, BufferedSample IMU+wheel+timestamps+marker for CSV rows),
    records/storage_repository.dart (StorageRepository abstract: listTopics/
    createTopic/deleteTopic/nextTrialNumber/saveSession/readSessionMeta/
    listSessions/deleteSession + PathProviderStorageRepository production impl
    using path_provider+dart:io creating WheelAthleteData/<topic>/trial_<NN>/
    hierarchy per §5 + InMemoryStorageRepository fake for tests + TopicEntry),
    state/recording_providers.dart (RecordingNotifier Riverpod state machine:
    startRecording starts IMU streaming both sides + subscribes to raw BLE IMU
    to buffer samples with synced timestamps from DriftFit, markEvent records
    MarkerEvent + sets _markNextBatch flag for next batch marker=true,
    stopRecording stops IMU + builds SessionMeta with sync quality from
    SyncEngineNotifier + saves to StorageRepository, reset returns to idle),
    ui/record_page.dart (RecordPage three-state UI: idle topic dropdown +
    trial info + Start Recording + new topic dialog, recording live stats +
    MarkEventButton + Stop Recording, stopped Session saved + New Recording).
  - modified: state/ble_providers.dart (+storageRepositoryProvider),
    ui/live_page.dart (+Record icon button in AppBar navigates to RecordPage),
    pubspec.yaml (+path_provider 2.1.6).
  - bugs caught by TDD: widget test async hang (await storage.saveSession()
    inside stopRecording hangs in widget tests because test framework zone
    doesn't pump microtasks from async methods without real async work →
    fixed with tester.runAsync), FutureBuilder infinite rebuild (_TopicDropdown
    created new Future on every build → cached in initState), duplicate
    saveSession call from debug prints, BuildContext across async gaps
    (ScaffoldMessenger.of(context) after await → if (!context.mounted) return),
    unused imports, prefer_const_constructors.
  - Tests: 45 new (10 session_model + 13 storage_repository + 12 recording_providers
    + 10 record_page) = 249 total PASS. flutter analyze clean.
    Coverage: session_model 100%, storage_repository 100% testable,
    recording_providers 94.6%, record_page 76.8%.
  - Evidence: docs/testing/subtask-08.tdd.md
  - Next: #9 (CSV export synced + folder hierarchy + share) needs #8 recording
    + #7 sync.
