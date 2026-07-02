# PROMPT FOR SUBTASK #29: Convert `timestamp_synced_ms` to absolute UTC

ใช้ `dart-flutter-patterns` skill และ `tdd-workflow` skill

## Goal

Make the CSV `timestamp_synced_ms` column absolute UTC epoch milliseconds by adding a `utcOffsetMs` to every buffered sample.

## Context

- `.project/plan-timestamp-sync.md` §Architecture changes
- `.project/context-timestamp-sync.md` §Key design decisions
- Files to touch:
  - `app/lib/state/record_countdown_providers.dart`
  - `app/lib/state/recording_providers.dart`
  - `app/lib/records/session_model.dart`
  - `app/test/state/recording_providers_test.dart`
  - `app/test/state/record_countdown_test.dart`

## Background math

The sync engine uses a relative timeline anchored at `_tAppRefMs` (the epoch ms of the first sync ping). The drift fit produces `relativeSyncedMs` on that timeline.

In the countdown flow we know:

- `utcStartMs` — UTC epoch ms of the scheduled start.
- `tStartRelMs = tStartPhoneMs - tAppRefMs` — the scheduled start on the relative timeline.

Therefore:

```
utcOffsetMs = utcStartMs - tStartRelMs
absoluteUtcSyncedMs = relativeSyncedMs + utcOffsetMs
```

This offset is the same for the whole session.

## Required changes

1. `SessionConfig` gains an optional `utcOffsetMs` field.
2. `RecordCountdownNotifier` computes `utcOffsetMs` after `tStartPhoneMs` is known:
   - Read `syncEngineProvider.notifier.tAppRefMs` (default to `nowPhoneMs` if null).
   - `tStartRelMs = tStartPhoneMs - tAppRefMs`.
   - `utcOffsetMs = utcStartMs - tStartRelMs`.
   - Pass `utcOffsetMs` into the `SessionConfig` built in `_beginRecording`.
3. `RecordingNotifier` reads `config.utcOffsetMs` and adds it to every sample's `timestampSyncedMs`:
   - In `_subscribeImu`, replace the `syncedMs` assignment with `syncedMs = relativeSyncedMs + utcOffsetMs` when `config.utcOffsetMs` is not null.
   - If `config.utcOffsetMs` is null (legacy/immediate start), keep the current relative value.
4. `RecordingNotifier.stopRecording()` should use `DateTime.fromMillisecondsSinceEpoch(utcStartMs, isUtc: true)` for `SessionMeta.startTime` when `config.utcStartMs` is present.

## Acceptance criteria

- `recording_providers_test.dart` has a test that creates a `SessionConfig` with `utcOffsetMs`, emits a fake IMU sample, and asserts `bufferedSample.timestampSyncedMs` is a large UTC epoch value (≈ `utcStartMs`).
- `record_countdown_test.dart` asserts that after a full countdown + START_FIRED, the recording config has `utcOffsetMs` and the first sample is near `utcStartMs`.
- Existing tests still pass.
- `flutter analyze` clean.

## Before coding

1. Read `.project/plan-timestamp-sync.md` and `.project/context-timestamp-sync.md`.
2. Read the current `recording_providers.dart`, `session_model.dart`, and their tests.
3. Write the failing test first.

## After coding

1. Run `flutter test test/state/record_countdown_test.dart test/state/recording_providers_test.dart`.
2. Run `flutter analyze`.
3. Commit with: `feat(app): absolute UTC timestamp_synced_ms in CSV`
4. Update `.project/progress.md`: mark subtask #29 completed.
