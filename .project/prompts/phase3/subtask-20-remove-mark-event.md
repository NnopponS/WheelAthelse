---
PROMPT FOR SUBTASK #20: Remove Mark Event from recording UI
---
ใช้ dart-flutter-patterns skill เพื่อลบ Mark Event function ออกจาก recording UI

Context:
- Project: WheelAthlete
- Subtask: #20 of #27 (Phase 3, Issue #4)
- Branch: feat/phase3-browse-cleanup
- Stack: Flutter / Dart, flutter_riverpod
- Files to touch:
  - app/lib/ui/record_page.dart (remove MarkEventButton from recording view, remove markerCount badge from recording + stopped views)
  - app/lib/state/recording_providers.dart (remove markEvent() method, _markNextBatch flag, markers list from RecordingState)
  - app/lib/widgets/mark_event_button.dart (KEEP file — may still be referenced by tests; just stop importing it in record_page)
- Acceptance criteria:
  1. No MARK button visible during recording
  2. No marker count badge in recording or stopped view
  3. markEvent() method removed from RecordingNotifier
  4. _markNextBatch flag removed from RecordingNotifier
  5. markers list removed from RecordingState (but MarkerEvent model + markers field in SessionMeta stay for reading old sessions)
  6. CSV marker column stays (always 0/false for new recordings — BufferedSample.marker defaults to false)
  7. All existing tests pass (update tests that referenced markEvent/markerCount)
  8. flutter analyze clean

ก่อนเขียนโค้ด:
1. อ่าน .project/phases/phase3/plan.md สำหรับ context เต็ม
2. อ่าน .project/phases/phase3/architecture.md สำหรับ system design (§4 Mark Event removal)
3. อ่าน .project/context.md D16 สำหรับเหตุผลในการลบ
4. เขียน test ก่อน (TDD) — update existing record_page tests to remove marker assertions, add test that markEvent() no longer exists
5. ทำเสร็จ commit ด้วยข้อความ: "feat(app): remove Mark Event from recording UI (#20)"

หลังเขียน:
1. รัน verification-loop (flutter analyze + flutter test)
2. อัปเดต .project/progress.md ว่า subtask #20 เสร็จแล้ว (เปลี่ยน status → completed, ใส่ commit hash)
