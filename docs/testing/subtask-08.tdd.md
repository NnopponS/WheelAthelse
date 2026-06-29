# Subtask #8 — TDD Evidence Report

## Scope
Flutter: recording session lifecycle (start/stop), Mark Event, folder
topic/trial hierarchy, buffered samples with synced timestamps.

## What was built

### Pure models (no I/O)
- `app/lib/records/session_model.dart`:
  - `MarkerEvent` — sync marker (timestampAppMs, offsetFromStartMs, label).
  - `SessionConfig` — pre-recording config (topic, trialNumber, sampleRateHz,
    athleteName, notes). `trialFolderName` zero-pads to 2 digits. `sessionId`
    is hex timestamp.
  - `SessionMeta` — post-recording metadata written to `session_<id>_meta.json`.
    Full JSON serialization/deserialization with null-safe optional fields
    (offsetUs, driftResidual, athleteName, notes, videoFileName).
  - `BufferedSample` — one IMU sample enriched with wheel side, timestampAppMs,
    timestampSyncedMs, marker flag. Maps to CSV row per §3 of architecture.md.

### Storage repository (abstract + path_provider + in-memory fake)
- `app/lib/records/storage_repository.dart`:
  - `StorageRepository` abstract interface: listTopics, createTopic, deleteTopic,
    nextTrialNumber, saveSession, readSessionMeta, listSessions, deleteSession.
  - `PathProviderStorageRepository` — production impl using `path_provider` +
    `dart:io`. Creates `WheelAthleteData/<topic>/trial_<NN>/` hierarchy per §5.
  - `InMemoryStorageRepository` — in-memory fake for tests (maps, lists, no I/O).
  - `TopicEntry` — topic folder metadata (name, description, createdAt).

### Recording state machine (Riverpod)
- `app/lib/state/recording_providers.dart`:
  - `RecordingStatus` enum: idle, recording, stopped.
  - `RecordingState` — status, config, startTime, sampleCount, markerCount,
    markers, savedSessionId, error.
  - `RecordingNotifier` — state machine:
    - `startRecording(config)`: validates not already recording, starts IMU
      streaming on both sides via `ImuStreamNotifier`, subscribes to raw BLE
      IMU data to buffer samples with synced timestamps (from `DriftFit`).
    - `markEvent(label)`: records `MarkerEvent`, sets `_markNextBatch` flag so
      the next IMU batch gets `marker=true` in their `BufferedSample`.
    - `stopRecording()`: stops IMU streaming, builds `SessionMeta` with sync
      quality (offset + drift residual from `SyncEngineNotifier`), saves to
      `StorageRepository`.
    - `reset()`: returns to idle, clears buffer.

### UI
- `app/lib/ui/record_page.dart`:
  - `RecordPage` (ConsumerStatefulWidget) — three-state UI:
    - idle: topic dropdown + trial info + "Start Recording" button + new topic dialog.
    - recording: live stats card (samples, markers, elapsed) + MarkEventButton +
      "Stop Recording" button.
    - stopped: "Session saved" card + "New Recording" button.
  - `_TopicDropdown` — cached FutureBuilder for topic list + new topic IconButton.
  - `_NewTopicDialog` — AlertDialog with TextField for topic name.
  - `_TrialInfo` — shows `trial_NN` with "(auto)" label.
- `app/lib/ui/live_page.dart`: added Record icon button in AppBar (navigates to
  RecordPage when wheels are connected).
- `app/lib/state/ble_providers.dart`: added `storageRepositoryProvider`.

### Dependencies
- Added `path_provider: ^2.1.6` to pubspec.yaml.

## TDD workflow
1. RED: `test/records/session_model_test.dart` (10 tests) — MarkerEvent,
   SessionConfig (trialFolderName, sessionId), SessionMeta (JSON round-trip,
   null fields), BufferedSample (fields, marker default).
2. GREEN: `session_model.dart` — all 10 pass.
3. RED: `test/records/storage_repository_test.dart` (13 tests) — topics (list,
   create, duplicate, sorted), trials (nextTrialNumber, increment, max),
   save+read (meta round-trip, null, listSessions, empty), delete (session,
   topic).
4. GREEN: `storage_repository.dart` — all 13 pass.
5. RED: `test/state/recording_providers_test.dart` (12 tests) — initial state,
   startRecording (status, config, throws if already, starts IMU), buffer
   samples, markEvent (count, marker, throws if not recording), stopRecording
   (status, saves, stops IMU, throws if not), reset, markEvent flag.
6. GREEN: `recording_providers.dart` — all 12 pass.
7. RED: `test/ui/record_page_test.dart` (10 tests) — idle view, start, stop,
   mark event, new topic dialog, sample count, trial number, new recording
   button, reset.
8. GREEN: `record_page.dart` + live_page navigation — all 10 pass.

## Test results
- `flutter analyze`: **clean** (0 issues)
- `flutter test`: **249/249 PASS** (was 204 before #8; +45 new tests)
  - `test/records/session_model_test.dart`: 10 tests
  - `test/records/storage_repository_test.dart`: 13 tests
  - `test/state/recording_providers_test.dart`: 12 tests
  - `test/ui/record_page_test.dart`: 10 tests
- Coverage (new files):
  - `lib/records/session_model.dart`: **100%** (41/41 lines)
  - `lib/records/storage_repository.dart`: **100%** (35/35 testable lines)
  - `lib/state/recording_providers.dart`: **94.6%** (106/112 lines)
  - `lib/ui/record_page.dart`: **76.8%** (159/207 lines)

## Bugs caught by TDD
- **Widget test async hang**: `await storage.saveSession()` inside
  `stopRecording()` hangs in widget tests because the test framework's zone
  doesn't pump microtasks from `async` methods without real async work.
  Fixed by wrapping the stop call in `tester.runAsync()`.
- **FutureBuilder infinite rebuild**: `_TopicDropdown` created a new Future on
  every build via `ref.read(...).listTopics()`, causing `pumpAndSettle` to
  hang. Fixed by caching the Future in `initState`.
- **Duplicate saveSession call**: debug prints left a duplicate
  `await storage.saveSession()` call. Removed.
- **BuildContext across async gaps**: `ScaffoldMessenger.of(context)` after
  `await` triggered `use_build_context_synchronously` lint. Fixed by using
  `if (!context.mounted) return;` guard.
- **Unused imports**: `imu_packet.dart`, `sync_engine.dart`, `sync_providers.dart`
  in test files. Removed.
- **prefer_const_constructors**: `MarkerEvent` and `BufferedSample` in tests
  could be `const`. Fixed.

## Skills used
dart-flutter-patterns, tdd-workflow, gateguard, verification-loop
