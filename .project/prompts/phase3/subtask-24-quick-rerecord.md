---
PROMPT FOR SUBTASK #24: Quick re-record in stopped view
---
ใช้ dart-flutter-patterns skill เพื่อเพิ่ม Quick Re-record button ใน Record page stopped view

Context:
- Project: WheelAthlete
- Subtask: #24 of #27 (Phase 3, Issue #5)
- Branch: feat/phase3-protocols
- Stack: Flutter / Dart, flutter_riverpod
- Depends on: #20 (MARK removed from record page) + #22 (template providers exist)
- Files to touch:
  - app/lib/ui/record_page.dart (add Re-record button to _buildStoppedView)
  - app/lib/state/recording_providers.dart (carry over SessionConfig for re-record, add reRecordConfig getter or store last config)
- Acceptance criteria:
  1. Stopped view shows a summary card: topic, trial number, duration, sample count, sync quality (already exists)
  2. New "Re-record" button appears below the summary card (before or next to "New Recording")
  3. Tapping "Re-record" starts a new recording with the same topic + same sampleRateHz + next trial number (nextTrialNumber for that topic)
  4. If the original session used a protocolTemplateId, the re-recorded session carries the same templateId
  5. Re-record goes through the same countdown flow (recordCountdownProvider.start)
  6. "New Recording" button stays (resets to idle view for picking a different template/topic)
  7. Re-record button is disabled if no wheels are connected
  8. Tests: re-record button visible in stopped view, tapping it starts countdown with next trial number, config carries over
  9. flutter analyze clean

Notes:
- RecordingNotifier should store the last SessionConfig (or just read it from state.config in stopped status)
- nextTrialNumber is already available via storageRepositoryProvider.nextTrialNumber(topic)
- The Re-record button should use ActionIntent.start (same as Start Recording) — use PrimaryActionButton
- Layout: Re-record (primary) + New Recording (tonal) side by side or stacked

ก่อนเขียนโค้ด:
1. อ่าน .project/phases/phase3/plan.md สำหรับ context เต็ม
2. อ่าน .project/phases/phase3/architecture.md สำหรับ system design (§5 Quick re-record)
3. อ่าน .project/context.md D19 สำหรับเหตุผล
4. อ่าน app/lib/ui/record_page.dart ก่อน — ดู _buildStoppedView + _startRecording
5. เขียน test ก่อน (TDD)
6. ทำเสร็จ commit ด้วยข้อความ: "feat(app): quick re-record in stopped view (#24)"

หลังเขียน:
1. รัน verification-loop (flutter analyze + flutter test)
2. อัปเดต .project/progress.md ว่า subtask #24 เสร็จแล้ว
