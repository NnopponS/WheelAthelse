# Loop Engineer — Phase 2 Autonomous Build

> Paste this prompt at the start of a session to run the full Phase 2 build
> autonomously: parallel subagents, TDD workflow, verify loop, progress tracking,
> firmware flash, integration test, release APK — all 6 features working with
> the board. Do NOT ask the user anything except for auth/permission blockers.

## Mission
Build and ship a release APK of the WheelAthlete app with all 6 Phase 2
features working 100% with the M5StickCPlus2 board (connected via USB):
1. Battery % + RSSI display after connect
2. Board config (name / wheel / Hz) in-app
3. Edit folder/topic/session metadata
4. Working share/export (save to device + share CSV to other apps)
5. Realtime per-axis IMU line charts
6. Record countdown 5-4-3-2-1 + board beep 3-2-1 + UTC session stamp

## Rules
1. NEVER ask the user for decisions — all decisions are pre-made in `.project/plan.md`.
2. ONLY stop for: auth failures, permission errors, destructive-op confirmation, or a hard blocker you cannot resolve after 3 attempts.
3. ALWAYS follow TDD: write failing test → implement → verify test passes → commit.
4. ALWAYS update `.project/progress.md` after every subtask commit.
5. ALWAYS run the verify loop after each subtask: `flutter analyze` + `flutter test` (app) / `pio run` + `pytest` (firmware).
6. NEVER work on the same file from two parallel agents — use git worktrees.
7. ALWAYS use the skill recommended for each subtask (see `.project/plan.md`).
8. ALWAYS commit with conventional commit messages referencing the subtask #.
9. When all subtasks are done: merge branches → flash firmware → integration test → build release APK.
10. If a subagent fails, read its output, fix the issue, and retry or take over that track.

## Parallelization (3 tracks, git worktrees, no overlap)
```
Track FW    (worktree ../WheelAthelse-fw)    branch feat/phase2-firmware-issue-1
  #11 → #12 → #13  (sequential — same files in firmware/src/)

Track AppConn (worktree ../WheelAthelse-app-conn) branch feat/phase2-app-conn-issue-2
  #14 → #15 → #16  (sequential — same files in app/lib/)
  Can stub firmware chars via FakeBleRepository if firmware not landed yet.

Track AppData (worktree ../WheelAthelse-app-data) branch feat/phase2-app-data-issue-3
  #17 → #18 → #19  (sequential — same files in app/lib/)
  Fully independent — no firmware dependency.
```

## Per-subtask workflow (EVERY subtask, no exceptions)
```
1. READ   — .project/plan.md + .project/architecture.md + .project/progress.md
            + the subtask prompt from .project/prompts/phase2/subtask-N-*.md
2. SKILL  — invoke the skill(s) recommended for that subtask
3. TEST   — write failing tests first (TDD red phase)
4. CODE   — implement the minimum to pass tests (TDD green phase)
5. CHECK  — run linter / static analysis
6. VERIFY — run full test suite + build
             App:    flutter analyze && flutter test
             Firmware: pio run -e left && pio run -e right && pytest firmware/test
7. COMMIT — conventional commit: feat(scope): description (#N)
8. TRACK  — update .project/progress.md row #N (status=completed, commit hash)
9. NEXT   — move to next subtask in the track
```

## Post-merge integration phase (after all 9 subtasks done)
```
1. MERGE  — merge 3 feature branches into main (resolve progress.md conflicts)
2. FLASH  — pio run -e left -t upload  &&  pio run -e right -t upload
             (board is connected via USB — user confirmed)
3. TEST   — integration test: app connects to board, battery/RSSI show,
             board settings work, record countdown + beep, charts render,
             export/share saves CSV, folder rename works
4. APK    — cd app && flutter build apk --release
5. VERIFY — APK exists at app/build/app/outputs/flutter-apk/app-release.apk
6. REPORT — final summary to user with APK path + feature checklist
```

## Failure recovery
- Build fails → read error → fix → rebuild (max 3 retries before escalating)
- Test fails → read failure → fix code or fix test → rerun (max 3 retries)
- Flash fails → check port / board connection → retry (max 3 retries)
- Subagent stuck → kill it, read output, take over that track manually
- Merge conflict → resolve manually, prefer the feature branch's changes

## Progress visibility
After every subtask commit, update `.project/progress.md`:
- Set Status = completed, Completed = today's date, Commit = hash
- Add a Notes entry with what was done + bugs caught by TDD
