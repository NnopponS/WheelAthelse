---
PROMPT FOR SUBTASK #27: Experiment tracker dashboard
---
ใช้ dart-flutter-patterns skill เพื่อสร้าง Experiment Tracker Dashboard (4th tab)

Context:
- Project: WheelAthlete
- Subtask: #27 of #27 (Phase 3, Issue #6)
- Branch: feat/phase3-organization
- Stack: Flutter / Dart, flutter_riverpod
- Depends on: #22 (protocol templates) + #25 (session tags for filtering)
- Files to create:
  - app/lib/ui/experiment_tracker_page.dart (dashboard page)
  - app/lib/state/experiment_tracker_providers.dart (progress computation)
  - app/lib/widgets/protocol_template_card.dart (card showing template + progress)
- Files to modify:
  - app/lib/ui/home_page.dart (add 4th NavigationDestination "Experiments" + _ExperimentsTab)
- Acceptance criteria:
  1. experimentProgressProvider (FutureProvider) loads all templates + counts sessions per template
  2. Sessions are matched to templates by protocolTemplateId (fallback: by topicName if templateId is null)
  3. ExperimentTrackerPage shows a list of ProtocolTemplateCard widgets
  4. Each card shows: template name, description, progress bar (sessions / targetTrialCount), last session date
  5. Progress bar uses LinearProgressIndicator from Material 3
  6. "X / Y trials" text below the progress bar
  7. Tapping a card navigates to Browse at that template's topic (pushes BrowsePage with topic pre-selected, or switches to Browse tab + navigates)
  8. "New Template" FAB → opens create template dialog (name, description, topicName, targetTrialCount, sampleRateHz)
  9. Empty state when no templates: "Create a protocol template to start tracking experiments"
  10. home_page.dart: 4th tab "Experiments" with Icons.science_rounded
  11. Tests: progress computation, card renders, empty state, navigation on tap
  12. flutter analyze clean

Notes:
- For navigation from Experiments tab to Browse: use a callback or shared state provider to switch tabs + set selected topic
- Simplest approach: ExperimentTrackerPage takes an onOpenTopic callback that switches to Browse tab + navigates to that topic
- ProtocolTemplateCard should show a colored accent based on progress (green when complete, amber when in progress)
- Create template dialog can reuse the showTextEditDialog pattern from browse_page.dart
- The FAB on the dashboard creates templates via protocolTemplateNotifierProvider

ก่อนเขียนโค้ด:
1. อ่าน .project/plan-phase3.md สำหรับ context เต็ม
2. อ่าน .project/architecture-phase3.md สำหรับ system design (§8 Experiment tracker dashboard)
3. อ่าน .project/context.md D22 สำหรับเหตุผล
4. อ่าน app/lib/ui/home_page.dart ก่อน — ดู IndexedStack + NavigationBar pattern
5. อ่าน app/lib/state/protocol_providers.dart (from #22) — ดู template providers
6. เขียน test ก่อน (TDD)
7. ทำเสร็จ commit ด้วยข้อความ: "feat(app): experiment tracker dashboard (#27)"

หลังเขียน:
1. รัน verification-loop (flutter analyze + flutter test)
2. อัปเดต .project/progress.md ว่า subtask #27 เสร็จแล้ว
