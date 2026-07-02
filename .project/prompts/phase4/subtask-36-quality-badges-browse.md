---
PROMPT FOR SUBTASK #36: Quality badges in Browse session list
---
ใช้ dart-flutter-patterns + tdd-workflow skill เพื่อแสดง sync quality badge ใน Browse session list

Context:
- Project: WheelAthlete (Flutter app for wheelchair IMU data collection)
- Subtask: #36 of 7 (Phase 4)
- Branch: feat/phase4-preview (ต่อจาก #32 — independent จาก #33-#35)
- Stack: Flutter / Dart, flutter_riverpod
- DEPENDS ON: #32 (QualityBadge must exist)
- Files to modify:
  - app/lib/widgets/session_list_item.dart — add syncQuality param + badge display
  - app/lib/ui/browse_page.dart — compute QualityBadge.fromMeta + pass to SessionListItem
  - app/test/widgets/session_list_item_test.dart — add quality badge tests
  - app/test/ui/browse_page_test.dart — add quality badge rendering test

ก่อนเขียนโค้ด:
1. อ่าน .project/plan-phase4.md สำหรับ context เต็ม
2. อ่าน .project/architecture-phase4.md section §7 (Quality badges in Browse)
3. อ่าน app/lib/records/quality_badge.dart (from #32) — SyncQuality + QualityBadge
4. อ่าน app/lib/widgets/session_list_item.dart — current structure
5. อ่าน app/lib/ui/browse_page.dart — _SessionListView where SessionListItem is built
6. เขียน test ก่อน (TDD)
7. ทำเสร็จ commit ด้วยข้อความ: "feat(app): quality badges in Browse session list (#36)"

Acceptance criteria:
1. SessionListItem: add syncQuality: SyncQuality? parameter (default null)
2. Show small colored dot (12px circle) next to session ID when syncQuality is not null/unknown
3. Colors: green (good), amber (fair), red (poor), grey (unknown)
4. BrowsePage _SessionListView: compute QualityBadge.fromMeta(meta) for each session
5. Pass syncQuality to SessionListItem
6. Tests: good/fair/poor/unknown badge colors render, no badge when null, badge position correct
7. flutter analyze clean

หลังเขียน:
1. รัน flutter test + flutter analyze
2. อัปเดต .project/progress-phase4.md ว่า subtask #36 เสร็จแล้ว
