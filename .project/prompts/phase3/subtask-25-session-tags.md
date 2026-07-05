---
PROMPT FOR SUBTASK #25: Session tags (model + storage + edit UI)
---
ใช้ dart-flutter-patterns skill เพื่อเพิ่ม Session Tags system (model + storage + edit UI)

Context:
- Project: WheelAthlete
- Subtask: #25 of #27 (Phase 3, Issue #6)
- Branch: feat/phase3-organization
- Stack: Flutter / Dart, flutter_riverpod
- Files to modify:
  - app/lib/records/session_model.dart (add tags: List<String> + protocolTemplateId: String? to SessionMeta, update toJson/fromJson)
  - app/lib/records/storage_repository.dart (add updateSessionTags method to abstract + both impls, add listAllSessions method)
- Files to create:
  - app/lib/ui/tag_editor_dialog.dart (dialog for adding/removing tags on a session)
- Files to modify:
  - app/lib/ui/browse_page.dart (add tag editor to session edit flow, show tags in session list)
  - app/lib/widgets/session_list_item.dart (add tags display as chips below subtitle)
- Acceptance criteria:
  1. SessionMeta has tags: List<String> (default []) + protocolTemplateId: String? (default null)
  2. toJson/fromJson handle tags + protocolTemplateId (old sessions without these fields default correctly)
  3. updateSessionTags(topic, trialNumber, sessionId, List<String> tags) exists in StorageRepository + both impls
  4. listAllSessions() returns a flat List<SessionSummary> across all topics/trials (for search + dashboard)
  5. SessionSummary = SessionMeta + topic + trialNumber (or reuse SessionMeta which already has these)
  6. TagEditorDialog: shows current tags as chips with remove button, text field + add button to add new tag
  7. Browse session edit flow includes "Edit tags" option that opens TagEditorDialog
  8. SessionListItem shows tags as small chips below the subtitle
  9. Tests: model serialization with/without tags, updateSessionTags, listAllSessions, tag editor dialog
  10. flutter analyze clean

Notes:
- Tags are free-form strings — no preset list (user types whatever they want)
- listAllSessions should walk all topic dirs → all trial dirs → read all session metas
- SessionSummary can be a simple class or just reuse SessionMeta (it already has topic + trialNumber)
- Tag chips should use small, subtle styling (not loud) — use theme colorScheme.secondaryContainer

ก่อนเขียนโค้ด:
1. อ่าน .project/phases/phase3/plan.md สำหรับ context เต็ม
2. อ่าน .project/phases/phase3/architecture.md สำหรับ system design (§2 Session tags)
3. อ่าน .project/context.md D20 สำหรับเหตุผล
4. อ่าน app/lib/records/session_model.dart ก่อน — ดู toJson/fromJson pattern
5. อ่าน app/lib/records/storage_repository.dart — ดู updateSessionMeta pattern
6. เขียน test ก่อน (TDD)
7. ทำเสร็จ commit ด้วยข้อความ: "feat(app): session tags model + storage + edit UI (#25)"

หลังเขียน:
1. รัน verification-loop (flutter analyze + flutter test)
2. อัปเดต .project/progress.md ว่า subtask #25 เสร็จแล้ว
