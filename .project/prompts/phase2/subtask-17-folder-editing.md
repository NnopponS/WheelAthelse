---
PROMPT FOR SUBTASK #17: Edit folder/topic/session metadata
---
Use `dart-flutter-patterns` + `tdd-workflow` + `verification-loop` for this subtask.

Context:
- Feature: Phase 2 app data (Issue #3)
- Branch: `feat/phase2-app-data-issue-3`
- Subtask: #17
- Goal: Make Browse editable — rename a topic (moves the folder), edit topic description, edit session meta notes + video filename.
- Files: `app/lib/records/storage_repository.dart`, `app/lib/records/session_model.dart`, `app/lib/ui/browse_page.dart`, `app/test/...` (new tests)
- Stack: Flutter / Dart, flutter_riverpod, path_provider

Steps:
1. Read `.project/plan.md` (Phase 2) + `.project/architecture.md` + `.project/progress.md`.
2. Read `app/lib/records/storage_repository.dart` — note it has list methods but no rename/update. `TopicEntry` has a `description` field but no UI sets it.
3. TDD: write tests first against `InMemoryStorageRepository` for `renameTopic(old, new)`, `updateTopicDescription(name, desc)`, `updateSessionMeta(topic, trial, sessionId, {notes, videoFile})`.
4. Implement those methods in the `StorageRepository` interface + `PathProviderStorageRepository` (rename = move dir; update meta = read JSON, mutate, write back) + `InMemoryStorageRepository`.
5. Add UI: long-press / overflow menu on topic row → rename dialog + description dialog; on session row → edit notes/video dialog. Reuse the design system dialogs.
6. Verify: `flutter analyze` clean; `flutter test` green; widget tests for rename + edit dialogs.
7. Commit: `feat(app): edit folder/topic/session metadata (#17)`
8. Update `.project/progress.md` row #17.

Definition of done: user can rename topics, edit topic descriptions, edit session notes + video filename; unit + widget tested; flutter analyze + test green.
