---
PROMPT FOR SUBTASK #34: Preview entry points (Browse tap + stopped view button)
---
ใช้ dart-flutter-patterns + tdd-workflow skill เพื่อเพิ่ม entry points ไปยัง SessionPreviewPage

Context:
- Project: WheelAthlete (Flutter app for wheelchair IMU data collection)
- Subtask: #34 of 7 (Phase 4)
- Branch: feat/phase4-preview (ต่อจาก #33)
- Stack: Flutter / Dart, flutter_riverpod
- DEPENDS ON: #33 (SessionPreviewPage must exist)
- Files to modify:
  - app/lib/widgets/session_list_item.dart — add onTap callback
  - app/lib/ui/browse_page.dart — wire tap → push SessionPreviewPage
  - app/lib/ui/record_page.dart — add Preview button in stopped view
  - app/test/ui/browse_page_test.dart — add tap → preview test
  - app/test/ui/record_page_test.dart — add preview button test
  - app/test/widgets/session_list_item_test.dart — add onTap test

ก่อนเขียนโค้ด:
1. อ่าน .project/plan-phase4.md สำหรับ context เต็ม
2. อ่าน .project/architecture-phase4.md section §5 (Preview entry points)
3. อ่าน app/lib/ui/session_preview_page.dart (from #33)
4. อ่าน app/lib/widgets/session_list_item.dart — current structure
5. อ่าน app/lib/ui/browse_page.dart — _SessionListView
6. อ่าน app/lib/ui/record_page.dart — _buildStoppedView
7. เขียน test ก่อน (TDD)
8. ทำเสร็จ commit ด้วยข้อความ: "feat(app): preview entry points in Browse + stopped view (#34)"

Acceptance criteria:
1. SessionListItem: add onTap callback — tapping the card body (not buttons) triggers it
2. BrowsePage _SessionListView: tap session → Navigator.push to SessionPreviewPage with (topic, trialNumber, sessionId)
3. RecordPage _buildStoppedView: add "Preview" button between Re-record and New Recording
4. Preview in stopped view: uses in-memory samples from RecordingNotifier (not disk read)
5. Preview button disabled if no recording just completed
6. Tests: tap session in Browse navigates to preview, preview button in stopped view, preview button disabled when no recording
7. flutter analyze clean

หลังเขียน:
1. รัน flutter test + flutter analyze
2. อัปเดต .project/progress-phase4.md ว่า subtask #34 เสร็จแล้ว
