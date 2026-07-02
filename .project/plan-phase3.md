# WheelAthlete — Phase 3: Browse & Record Workflow Hardening

> Phase 1 (data collection) complete — see `.project/plan-phase1.md`.
> Phase 2 (field-ready enhancements) complete — see `.project/plan.md`.
> This plan covers the 8 subtasks the user requested after field testing
> Phase 2, grouped into 3 GitHub issues by concern.

## Objective

Harden the Browse and Record workflow for mixed-research field use.

**Remove:** The Mark Event function is removed from the recording UI — the
user will sync IMU data with camera video in post-processing instead. The
MARK button, marker count display, and `markEvent` UI calls are removed.
The `marker` column in CSV is kept for backward compatibility with existing
sessions (always `0`/`false` for new recordings). The `MarkerEvent` model
and `markers` field in `SessionMeta` stay for reading old sessions but are
no longer populated.

**Add delete:** Wire up delete (with confirmation dialogs) at all three
hierarchy levels — session, trial, and topic — using existing
`deleteTopic`/`deleteSession` storage methods plus a new `deleteTrial`
method.

**Add five workflow accelerators:**
- (a) **Protocol templates** — save a reusable named protocol (name +
  description + target trial count) so the user doesn't re-type topic info
  each session;
- (b) **Quick re-record** — after stopping, show a summary card with a
  one-tap "Re-record" button that starts the same protocol at the next
  trial number;
- (c) **Session tags/labels** — add custom tags to a session (e.g. "good",
  "bad-take", "athlete-A") and filter Browse by tag;
- (d) **Search/filter on Browse** — a search bar to filter topics and
  sessions by name, notes, or date;
- (e) **Experiment tracker dashboard** — a dedicated view that groups
  sessions by protocol template and shows progress (e.g. "3/5 trials
  done").

**Goal:** fewer taps to start a recording, a Browse page that scales to
hundreds of sessions, a dashboard that turns raw sessions into trackable
experiments, and a simpler recording screen focused on capturing motion
data.

## Issues (grouped by concern)

- **Issue #4** — `feat(app): Phase 3 browse cleanup` → branch `feat/phase3-browse-cleanup`
  - Remove Mark Event from recording UI, delete at all 3 hierarchy levels
- **Issue #5** — `feat(app): Phase 3 protocol templates` → branch `feat/phase3-protocols`
  - Protocol template model + storage, template picker in Record, quick re-record
- **Issue #6** — `feat(app): Phase 3 session organization` → branch `feat/phase3-organization`
  - Session tags, search/filter on Browse, experiment tracker dashboard

## Architecture changes (delta on Phase 2)

See `.project/architecture-phase3.md` for the full delta.

Key changes:
- **Storage:** new `deleteTrial` method; `SessionMeta` gains `tags` +
  `protocolTemplateId` fields; new `ProtocolTemplate` model +
  `ProtocolRepository` (stored as `protocols.json` in app docs dir);
  new `listAllSessions()` for search + dashboard.
- **State:** new `protocol_providers.dart`, `browse_providers.dart`,
  `experiment_tracker_providers.dart`; `recording_providers.dart` loses
  `markEvent`, gains re-record config carry-over.
- **UI:** `browse_page.dart` gains delete menus + search bar + tag filter;
  `record_page.dart` loses MARK button, gains template picker + re-record;
  new `experiment_tracker_page.dart` as 4th tab; new
  `tag_editor_dialog.dart`; `session_list_item.dart` gains delete + tags.

## Tech stack

- App: Flutter / Dart, flutter_blue_plus, flutter_riverpod, fl_chart,
  share_plus, path_provider, file_picker
- No new dependencies required.
- Repo: Monorepo (firmware/ + app/) — firmware untouched in Phase 3.

## Subtasks (each = 1 session = 1 commit)

### Issue #4 — Browse cleanup (branch `feat/phase3-browse-cleanup`)
- [ ] **#20** Remove Mark Event from recording UI
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `verification-loop`
- [ ] **#21** Delete at all 3 levels (topic/trial/session) in Browse
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `verification-loop`

### Issue #5 — Protocol templates (branch `feat/phase3-protocols`)
- [ ] **#22** Protocol template model + repository + Riverpod providers
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `verification-loop`
- [ ] **#23** Template picker in Record page idle view
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `verification-loop`
- [ ] **#24** Quick re-record in stopped view
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `verification-loop`

### Issue #6 — Session organization (branch `feat/phase3-organization`)
- [ ] **#25** Session tags (model + storage + edit UI)
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `verification-loop`
- [ ] **#26** Search/filter on Browse
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `verification-loop`
- [ ] **#27** Experiment tracker dashboard
      — skill: `dart-flutter-patterns` + `tdd-workflow` + `verification-loop`

## Dependency graph

```
Issue #4 (browse cleanup)
  #20 (remove MARK) ──┐
  #21 (delete 3 levels)─┘
        │
        ▼
Issue #5 (protocol templates)
  #22 (template model+repo) ──┐
  #23 (template picker) ◄── #22
  #24 (quick re-record) ◄── #20 + #22
        │
        ▼
Issue #6 (session organization)
  #25 (session tags) ──┐
  #26 (search/filter) ◄── #25
  #27 (tracker dashboard) ◄── #22 + #25
```

- #20 and #21 are independent of each other (different files) — can run
  in parallel.
- #22 is independent — can start immediately.
- #23 depends on #22 (needs template providers).
- #24 depends on #20 (record page cleaned up) + #22 (template carry-over).
- #25 is independent — can start immediately.
- #26 depends on #25 (search includes tags).
- #27 depends on #22 (group by template) + #25 (filter by tag).

## Stack-specific skills to use

| Layer | Build skill | Test skill | Verify skill |
|---|---|---|---|
| Flutter app | `dart-flutter-patterns` | `tdd-workflow` + `flutter-dart-code-review` | `verification-loop` (flutter analyze + test) |
| Cross-cutting | `gateguard` (investigate before edit) | — | — |

## Progress

See `.project/progress.md` (Phase 3 subtasks #20–#27 appended below Phase 2).

## How to continue (cross-session)

1. New session → run the **build** skill, or paste a subtask prompt from
   `.project/prompts/phase3/`.
2. build skill reads this `plan-phase3.md` + `architecture-phase3.md` +
   `progress.md` first.
3. One subtask per session: write tests first (TDD), implement, verify,
   commit, update `progress.md`.
