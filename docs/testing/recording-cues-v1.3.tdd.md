# Recording Handoff and Countdown Cues v1.3 TDD Evidence

## RED

- Flutter cue tests failed because `CountdownCueEvent`, the phone cue player,
  and deduplication did not exist.
- The Record UI test found `Stop Recording` inside `SingleChildScrollView`.
- The Live-to-Record regression reproduced a fresh sequence-0 sample being
  rejected after Live had already seeded the recovery buffer.
- XIAO firmware contract tests found six LED cues instead of M5's four and no
  `COUNTDOWN_CUE` protocol event.

## GREEN

- `dart analyze lib`: no issues.
- `flutter test --coverage`: 604 tests passed, followed by the targeted
  repeated-STOP guard test passing after it was added.
- Line coverage: 4138/5088, 81.33%.
- M5 host tests: 117 passed.
- XIAO countdown contract tests: 2 passed.
- M5 PlatformIO `left` and `right`: succeeded.
- XIAO PlatformIO `left` and `right`: succeeded.
- `flutter build apk --release`: succeeded; 53.6 MB APK.

## Hardware acceptance still required

- Confirm sequence-0 samples accumulate through 20 Live-to-Record cycles.
- Confirm each M5 beep produces one phone tone with two boards connected.
- Confirm XIAO flashes at T-3, T-2, T-1, and T-0.
- Confirm Stop remains immediately tappable on the target phone and only one
  STOP command is issued.
