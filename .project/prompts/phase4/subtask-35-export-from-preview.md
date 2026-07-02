---
PROMPT FOR SUBTASK #35: Export/share from preview page
---
ใช้ dart-flutter-patterns + tdd-workflow skill เพื่อเพิ่ม Export/Share button ใน SessionPreviewPage

Context:
- Project: WheelAthlete (Flutter app for wheelchair IMU data collection)
- Subtask: #35 of 7 (Phase 4)
- Branch: feat/phase4-preview (ต่อจาก #34)
- Stack: Flutter / Dart, flutter_riverpod, share_plus, file_picker
- DEPENDS ON: #34 (entry points must work)
- Files to modify:
  - app/lib/ui/session_preview_page.dart — add Export button in AppBar + share FAB
  - app/test/ui/session_preview_page_test.dart — add export tests

ก่อนเขียนโค้ด:
1. อ่าน .project/plan-phase4.md สำหรับ context เต็ม
2. อ่าน .project/architecture-phase4.md section §6 (Export from preview)
3. อ่าน app/lib/ui/session_preview_page.dart (from #33/#34)
4. อ่าน app/lib/export/export_actions.dart — existing export logic
5. อ่าน app/lib/export/export_providers.dart — existing providers
6. อ่าน app/lib/ui/browse_page.dart — ดูวิธี export ที่มีอยู่ (share session CSV)
7. เขียน test ก่อน (TDD)
8. ทำเสร็จ commit ด้วยข้อความ: "feat(app): export/share from preview page (#35)"

Acceptance criteria:
1. AppBar has Export button (Icons.download or Icons.share) that exports session CSV
2. Uses existing exportActionsProvider / export providers — same as Browse export
3. Share button uses share_plus (same as Browse share)
4. Export works from preview page without going back to Browse
5. Loading indicator during export
6. Tests: export button present, tapping export calls export provider, share button calls share
7. flutter analyze clean

หลังเขียน:
1. รัน flutter test + flutter analyze
2. อัปเดต .project/progress-phase4.md ว่า subtask #35 เสร็จแล้ว
