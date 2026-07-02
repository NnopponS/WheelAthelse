---
PROMPT FOR SUBTASK #23: Template picker in Record page idle view
---
ใช้ dart-flutter-patterns skill เพื่อเพิ่ม Protocol Template picker ใน Record page idle view

Context:
- Project: WheelAthlete
- Subtask: #23 of #27 (Phase 3, Issue #5)
- Branch: feat/phase3-protocols
- Stack: Flutter / Dart, flutter_riverpod
- Depends on: #22 (protocol template providers must exist)
- Files to touch:
  - app/lib/ui/record_page.dart (add template picker to idle view, auto-fill topic + trial + rate when template selected)
- Acceptance criteria:
  1. Idle view shows a horizontal scrollable row of protocol template chips at the top
  2. First chip is "Custom" (current behavior — manual topic dropdown)
  3. Tapping a template chip auto-fills: _selectedTopic (creates topic if it doesn't exist), _trialNumber (nextTrialNumber for that topic), sampleRateHz
  4. Selected chip is visually highlighted
  5. When "Custom" is selected, the existing topic dropdown + trial info shows as before
  6. When a template is selected, the topic dropdown is hidden or disabled (template drives the topic)
  7. The Start Recording button uses the template's sampleRateHz if a template is selected
  8. SessionConfig carries protocolTemplateId when a template is used (add optional field to SessionConfig)
  9. Tests: template picker renders, tapping template fills fields, custom mode works
  10. flutter analyze clean

Notes:
- SessionConfig needs a new optional field: protocolTemplateId (String?) — add to session_model.dart
- When a template is selected and its topic doesn't exist yet, call storage.createTopic(template.topicName)
- Use a horizontal ListView or Wrap for the chips
- Follow existing design system (AppSpacing, AppTypography, WheelAthleteColors)

ก่อนเขียนโค้ด:
1. อ่าน .project/plan-phase3.md สำหรับ context เต็ม
2. อ่าน .project/architecture-phase3.md สำหรับ system design (§6 Template picker in Record page)
3. อ่าน .project/context.md D18 สำหรับเหตุผล
4. อ่าน app/lib/ui/record_page.dart ก่อน — ดู _buildIdleView, _TopicDropdown, _TrialInfo
5. อ่าน app/lib/records/session_model.dart — เพิ่ม protocolTemplateId ใน SessionConfig
6. เขียน test ก่อน (TDD)
7. ทำเสร็จ commit ด้วยข้อความ: "feat(app): protocol template picker in Record page (#23)"

หลังเขียน:
1. รัน verification-loop (flutter analyze + flutter test)
2. อัปเดต .project/progress.md ว่า subtask #23 เสร็จแล้ว
