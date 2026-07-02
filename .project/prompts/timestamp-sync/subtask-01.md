# PROMPT FOR SUBTASK #28: Align countdown to next whole second

ใช้ `dart-flutter-patterns` skill และ `tdd-workflow` skill

## Goal

Modify the record countdown so that the scheduled recording start always lands on a whole-second boundary. The app waits for the next `.000` UTC boundary, then runs the existing 5-second countdown.

## Context

- `.project/plan-timestamp-sync.md` §Architecture changes
- `.project/context-timestamp-sync.md` §User questions and answers
- Files to touch:
  - `app/lib/state/record_countdown_providers.dart`
  - `app/test/state/record_countdown_test.dart`

## Current behavior

`RecordCountdownNotifier.start()` computes:

```dart
final tStartPhoneMs = nowPhoneMs + countdownMs;
```

This makes the start depend on the sub-second part of `nowPhoneMs`.

## Required behavior

1. Compute `nextWholeSecondMs = ((nowPhoneMs / 1000).ceil()) * 1000`.
2. Set `tStartPhoneMs = nextWholeSecondMs + countdownMs`.
3. The existing `countdownDurationProvider` stays `Duration(seconds: 5)` in production.
4. The display timer already uses `ceil(remainingMs / 1000)`; it will now correctly show the remaining seconds including the fractional wait.
5. Tests should use a short `countdownDurationProvider` (e.g., 200 ms) so they run fast.

## Acceptance criteria

- `record_countdown_test.dart` has a test that picks a non-whole-second `now`, calls `notifier.start()`, and asserts `state.tStartPhoneMs % 1000 == 0`.
- Another test asserts that the elapsed delay from `now` to `tStartPhoneMs` is in `[countdownMs, countdownMs + 1000)`.
- Existing tests still pass (`flutter test test/state/record_countdown_test.dart`).
- `flutter analyze` clean.

## Before coding

1. Read `.project/plan-timestamp-sync.md` and `.project/context-timestamp-sync.md`.
2. Read `app/lib/state/record_countdown_providers.dart` and `app/test/state/record_countdown_test.dart`.
3. Write the failing test first.

## After coding

1. Run `flutter test test/state/record_countdown_test.dart`.
2. Run `flutter analyze`.
3. Commit with: `feat(app): align record countdown to next whole second`
4. Update `.project/progress.md`: mark subtask #28 completed.
