# WheelAthlete — Phase 3: Whole-Second Start + Absolute UTC Timestamps

> Branch: `feat/phase3-browse-cleanup` (current)
>
> User request: timestamps are hard to align with camera. Make recording start on a whole UTC second (e.g., 18:30:26.000) and make the CSV `timestamp_synced_ms` column absolute UTC epoch milliseconds so it can be matched directly with the camera clock.

## Objective

Add a "whole-second start" mode to the existing record countdown. When the user presses Start, the app waits for the next whole-second boundary, then runs the normal 5-second countdown (5-4-3-2-1). The firmware fires at a whole-second UTC instant and the app stamps every sample with an absolute UTC epoch millisecond value in the CSV.

Decisions confirmed with user:

1. **00 ms means start on a whole-second boundary**, not resampling the CSV grid.
2. **`timestamp_synced_ms` becomes absolute UTC epoch ms** (e.g., `1782993025000.000`), not relative time.
3. **Countdown aligns to the next whole second** — app waits for the next `.000` boundary, then counts down 5 s. The scheduled start instant is always a whole second.

## Architecture changes

- **Countdown math**: `T_start = ceil(now / 1000) * 1000 + kCountdownDuration`. In the UI the remaining seconds are shown as `ceil(remainingMs / 1000)`, so the user may see 6 briefly when the fractional wait is > 0.5 s.
- **UTC offset**: the drift-fit timeline uses the same reference as the scheduled start (the sync engine's `_tAppRefMs`). We compute `utcOffsetMs = utcStartMs - tStartRelMs` once in the countdown flow and pass it to the recording provider. Every sample's `timestampSyncedMs` becomes `relativeSyncedMs + utcOffsetMs`.
- **Session meta**: `startTime` and `utcStartMs` both reflect the scheduled whole-second UTC instant.
- **Firmware**: `sendStartFired` already computes `utc_start_ms` from `utc_epoch + (target_start_us - now_us) / 1000`. We need to guard against the unsigned cast for negative `delta_us` and make sure the division matches the integer-millisecond semantics the app expects.

## Subtasks

| # | Title | Files | Stack | Skill | Status | Depends on |
|---|-------|-------|-------|-------|--------|------------|
| 1 | Align countdown to next whole second | `app/lib/state/record_countdown_providers.dart`, `app/test/state/record_countdown_test.dart` | Flutter/Dart | `dart-flutter-patterns` + `tdd-workflow` | pending | none |
| 2 | Convert `timestamp_synced_ms` to absolute UTC | `app/lib/state/record_countdown_providers.dart`, `app/lib/state/recording_providers.dart`, `app/lib/records/session_model.dart`, `app/test/state/recording_providers_test.dart`, `app/test/state/record_countdown_test.dart` | Flutter/Dart | `dart-flutter-patterns` + `tdd-workflow` | pending | #1 (same file) |
| 3 | Update docs and metadata | `docs/ble-protocol.md`, `.project/architecture.md`, `app/lib/export/csv_exporter.dart`, `app/lib/records/session_model.dart` | Flutter/Dart, docs | `dart-flutter-patterns` + `tdd-workflow` | pending | #2 |
| 4 | Verify firmware UTC start computation | `firmware/src/ble_service.cpp`, `firmware/src/ble_types.h`, firmware tests | C++ / ESP32 | `cpp-coding-standards` + `cpp-testing` + `tdd-workflow` | pending | #2 (app-side) |

## Definition of done

- `record_countdown_test.dart` proves that for a start pressed at arbitrary `now`, `tStartPhoneMs` is always a whole second and the delay is `[0..1000) + 5000` ms.
- `recording_providers_test.dart` proves that a buffered sample's `timestampSyncedMs` equals `relativeSyncedMs + utcOffsetMs` when `utcStartMs` is present.
- Exporting a session produces a CSV where `timestamp_synced_ms` is a large UTC epoch ms value (e.g., `1782993025000.42`) and the first row is at the scheduled start instant.
- `docs/ble-protocol.md` and `.project/architecture.md` describe the CSV column as absolute UTC epoch ms.
- `flutter analyze` and `flutter test` pass in the `app/` directory.
- Firmware builds (`pio run`) and firmware tests pass.

## Progress

See `.project/phases/timestamp-sync/progress.md`.

## How to continue

1. Review and approve this plan.
2. Use the `build` skill or paste a subtask prompt from `.project/prompts/timestamp-sync/`.
3. One subtask per session: tests first, implementation, verification, commit, update progress.
