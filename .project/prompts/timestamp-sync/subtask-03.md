# PROMPT FOR SUBTASK #30: Update docs and metadata for UTC timestamps

ใช้ `dart-flutter-patterns` skill และ `tdd-workflow` skill

## Goal

Update the project documentation and CSV exporter comments so that the new absolute UTC `timestamp_synced_ms` behavior is clear to users and future maintainers.

## Context

- `.project/plan-timestamp-sync.md` §Definition of done
- Files to touch:
  - `docs/ble-protocol.md` §6 CSV schema
  - `.project/architecture.md` §3 CSV format
  - `app/lib/export/csv_exporter.dart` doc comment
  - `app/lib/records/session_model.dart` doc comments on `BufferedSample.timestampSyncedMs` and `SessionMeta.utcStartMs`
  - Optional: `app/lib/export/export_actions.dart` / `export_providers.dart` if they expose a timestamp summary

## Required changes

1. `docs/ble-protocol.md` §6: change the description of `timestamp_synced_ms` from "common timeline after offset/drift correction" to "absolute UTC epoch milliseconds after offset/drift correction".
2. `.project/architecture.md` §3: same wording update.
3. `csv_exporter.dart`: update the class-level doc comment and the `header` comment to state absolute UTC.
4. `session_model.dart`: update the doc comment for `BufferedSample.timestampSyncedMs` to say absolute UTC epoch ms when `utcOffsetMs` is set; relative when no offset. Update `SessionMeta.utcStartMs` to mention the scheduled whole-second start.
5. Ensure `SessionMeta.toJson()` still writes `utc_start_ms` as an integer in milliseconds.

## Acceptance criteria

- No code behavior change (this is docs + comments).
- `flutter analyze` clean.
- A quick grep confirms all descriptions of `timestamp_synced_ms` mention "absolute UTC" or "UTC epoch".
- All existing tests still pass.

## Before coding

1. Read `.project/plan-timestamp-sync.md` and `.project/context-timestamp-sync.md`.
2. Search the repo for all occurrences of `timestamp_synced_ms` to ensure consistency.

## After coding

1. Run `flutter analyze` and `flutter test`.
2. Commit with: `docs: absolute UTC timestamp_synced_ms documentation`
3. Update `.project/progress.md`: mark subtask #30 completed.
