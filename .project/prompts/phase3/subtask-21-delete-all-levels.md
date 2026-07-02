---
PROMPT FOR SUBTASK #21: Delete at all 3 levels (topic/trial/session) in Browse
---
ใช้ dart-flutter-patterns skill เพื่อเพิ่มฟังก์ชันลบ (delete) ที่ทุกระดับใน Browse page

Context:
- Project: WheelAthlete
- Subtask: #21 of #27 (Phase 3, Issue #4)
- Branch: feat/phase3-browse-cleanup
- Stack: Flutter / Dart, flutter_riverpod
- Files to touch:
  - app/lib/records/storage_repository.dart (add deleteTrial method to abstract + PathProvider + InMemory impls)
  - app/lib/ui/browse_page.dart (add Delete to popup menus at Topic + Trial level, add delete to Session level)
  - app/lib/widgets/session_list_item.dart (add onDelete callback + delete button)
- Acceptance criteria:
  1. deleteTrial(topic, trialNumber) method exists in StorageRepository + both impls (deletes trial folder + all sessions)
  2. Topic list: popup menu gains "Delete" → confirmation dialog showing trial + session count → calls deleteTopic()
  3. Trial list: new popup menu with "Delete" → confirmation showing session count → calls deleteTrial()
  4. Session list: SessionListItem gains a delete icon button → confirmation dialog → calls deleteSession()
  5. All confirmation dialogs show what will be deleted (e.g. "Delete topic 'sprint_test'? This will remove 3 trials and 12 sessions.")
  6. After delete, the list refreshes automatically
  7. All existing tests pass + new tests for deleteTrial + delete UI
  8. flutter analyze clean

Notes:
- StorageRepository already has deleteTopic() and deleteSession() — read the existing implementations
- deleteTrial should delete the trial directory recursively (same pattern as deleteTopic)
- Use showDialog with AlertDialog for confirmations (red error icon + warning text)

ก่อนเขียนโค้ด:
1. อ่าน .project/plan-phase3.md สำหรับ context เต็ม
2. อ่าน .project/architecture-phase3.md สำหรับ system design (§3 Delete at all 3 levels)
3. อ่าน .project/context.md D17 สำหรับเหตุผล
4. อ่าน app/lib/records/storage_repository.dart ก่อน — ดู deleteTopic + deleteSession pattern ที่มีอยู่
5. เขียน test ก่อน (TDD) — test deleteTrial in InMemoryStorageRepository, test delete confirmation dialogs
6. ทำเสร็จ commit ด้วยข้อความ: "feat(app): delete at all 3 hierarchy levels in Browse (#21)"

หลังเขียน:
1. รัน verification-loop (flutter analyze + flutter test)
2. อัปเดต .project/progress.md ว่า subtask #21 เสร็จแล้ว
