---
PROMPT FOR SUBTASK #16: Record countdown + scheduled start + UTC session stamp
---
Use `dart-flutter-patterns` + `tdd-workflow` + `latency-critical-systems` + `intent-driven-development` + `verification-loop` for this subtask.

Context:
- Feature: Phase 2 app connectivity (Issue #2)
- Branch: `feat/phase2-app-conn-issue-2`
- Subtask: #16
- Goal: Rework the Record flow so tapping "Start Recording" syncs time with both boards, runs a 5-second countdown (5-4-3-2-1 in-app, beep 3-2-1 on the M5), starts both wheels + app together via scheduled start, and stamps the session meta with the UTC start instant for camera alignment.
- Files: `app/lib/ui/record_page.dart`, `app/lib/state/recording_providers.dart`, `app/lib/state/sync_providers.dart`, `app/lib/state/sync_engine.dart`, `app/lib/ble/control_command.dart`, `app/lib/records/session_model.dart`, `app/lib/records/storage_repository.dart`, `app/test/...` (new tests)
- Stack: Flutter / Dart, flutter_riverpod

Steps:
1. Read `.project/plan.md` (Phase 2) + `.project/architecture.md` (§4 Time Sync) + `.project/progress.md`.
2. intent-driven-development: write acceptance criteria for the countdown state machine (idle → syncing → counting → recording → stopped), cancel path, UTC-not-set fallback.
3. latency-critical-systems: review the scheduled-start timing path — SYNC_PING burst → MinRttTracker → ScheduledStart.compute → SET_UTC + scheduled START to both wheels; ensure offset estimate is fresh.
4. TDD: write tests first for the new `RecordCountdownNotifier` state machine (pure transitions, no Flutter) + the UTC stamp computation (`utc_start_ms = utc_epoch + (T_start - now_phone)`).
5. Implement: replace the immediate-start in `record_page.dart` with a countdown UI (large 5-4-3-2-1 number, cancellable). On tap: run SYNC_PING burst, send SET_UTC, compute T_start = now+5s, send scheduled START to both wheels, wait for START_FIRED, begin recording, write `utc_start_ms` into session meta.
6. Add `utcStartMs` to `SessionMeta` + `storage_repository.dart` write path.
7. Verify: `flutter analyze` clean; `flutter test` green (state machine + UTC stamp tests); widget test for countdown rendering with mock state.
8. Commit: `feat(app): record countdown + scheduled start + UTC session stamp (#16)`
9. Update `.project/progress.md` row #16.

Definition of done: Record flow shows 5s countdown, board beeps 3-2-1, both wheels + app start together, session meta carries UTC start instant; cancellable; unit + widget tested; flutter analyze + test green.
