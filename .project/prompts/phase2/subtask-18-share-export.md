---
PROMPT FOR SUBTASK #18: Wire share/export (share_plus sheet + save-to-device)
---
Use `dart-flutter-patterns` + `tdd-workflow` + `verification-loop` for this subtask.

Context:
- Feature: Phase 2 app data (Issue #3)
- Branch: `feat/phase2-app-data-issue-3`
- Subtask: #18
- Goal: Replace the stub `BrowsePage._share` snackbar with real actions: "Share" opens the share_plus sheet (pick target app), "Save to device" lets the user pick a destination folder (file_picker / SAF on Android, document picker on iOS).
- Files: `app/lib/ui/browse_page.dart`, `app/lib/export/export_providers.dart`, `app/lib/widgets/session_list_item.dart`, `app/pubspec.yaml` (add `file_picker`), `app/test/...` (new tests)
- Stack: Flutter / Dart, flutter_riverpod, share_plus, file_picker (new dep)

Steps:
1. Read `.project/plan.md` (Phase 2) + `.project/architecture.md` + `.project/progress.md`.
2. Read `app/lib/export/export_providers.dart` — `ExportNotifier` already implements `shareSession/shareTrial/shareTopic` via share_plus and `exportSession` writing CSV. The UI just never calls it.
3. Add `file_picker` to `pubspec.yaml` (check version published >= 7 days ago; avoid floating ranges).
4. TDD: write tests for a new `ExportActions` helper that decides which method to call (session/trial/topic) + a `saveToDevice` path that writes the CSV to a user-picked directory via file_picker.
5. Wire `SessionListItem.onShare` → `ExportNotifier.shareSession`; add `onSave` → `saveToDevice`. Add share/save actions at trial + topic levels too (overflow menus).
6. Handle errors: show snackbar with `ExportState.error` on failure; disable actions while `isExporting`.
7. Verify: `flutter analyze` clean; `flutter test` green; widget test that tapping Share invokes the export notifier (mock share_plus).
8. Commit: `feat(app): wire share/export — share_plus sheet + save-to-device (#18)`
9. Update `.project/progress.md` row #18.

Definition of done: Share + Save-to-device work for session/trial/topic; errors surfaced; unit + widget tested; flutter analyze + test green.
