---
PROMPT FOR SUBTASK #26: Search/filter on Browse
---
ใช้ dart-flutter-patterns skill เพื่อเพิ่ม Search + Tag filter ใน Browse page

Context:
- Project: WheelAthlete
- Subtask: #26 of #27 (Phase 3, Issue #6)
- Branch: feat/phase3-organization
- Stack: Flutter / Dart, flutter_riverpod
- Depends on: #25 (session tags must exist for tag filtering)
- Files to create:
  - app/lib/state/browse_providers.dart (browseSearchProvider, browseTagFilterProvider)
- Files to modify:
  - app/lib/ui/browse_page.dart (add search bar at Topic + Session level, add tag filter chips at Session level)
- Acceptance criteria:
  1. browseSearchProvider (StateProvider<String>) and browseTagFilterProvider (StateProvider<String?>) exist
  2. Topic list: search bar in AppBar filters topics by name (case-insensitive substring match)
  3. Session list: search bar filters by session ID, notes, date (ISO string), and tags
  4. Session list: horizontal chip row showing all unique tags across the current session list
  5. Tapping a tag chip filters sessions to those containing that tag (toggle — tap again to clear)
  6. Search + tag filter work together (AND logic — both must match)
  7. Empty search shows all items (no filter)
  8. "No results" state when search yields nothing
  9. Tests: search filters topics, search filters sessions, tag filter works, combined search + tag
  10. flutter analyze clean

Notes:
- Search filtering is in-memory on the already-loaded list (no storage query change)
- Use a TextField in the AppBar (or a fixed search bar below AppBar) — follow Material 3 search patterns
- Tag chips: use FilterChip widget from Material
- The search bar at Topic level and Session level are separate (each list has its own search)
- Debounce not needed — lists are small (in-memory filter is instant)

ก่อนเขียนโค้ด:
1. อ่าน .project/plan-phase3.md สำหรับ context เต็ม
2. อ่าน .project/architecture-phase3.md สำหรับ system design (§7 Search/filter on Browse)
3. อ่าน .project/context.md D21 สำหรับเหตุผล
4. อ่าน app/lib/ui/browse_page.dart ก่อน — ดู _TopicListView + _SessionListView structure
5. เขียน test ก่อน (TDD)
6. ทำเสร็จ commit ด้วยข้อความ: "feat(app): search + tag filter on Browse (#26)"

หลังเขียน:
1. รัน verification-loop (flutter analyze + flutter test)
2. อัปเดต .project/progress.md ว่า subtask #26 เสร็จแล้ว
