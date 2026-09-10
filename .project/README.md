# WheelAthlete engineering workspace

Updated: 2026-09-08.

Start with **STATUS.md**, then **HANDOFF.md**. Those two files are the current source of truth for project state and continuation. Read **decisions.md** before changing architecture, model defaults, firmware roles, release behavior, or publication scope.

## Canonical layout

```text
.project/
  README.md                         navigation and housekeeping policy
  STATUS.md                         current measured state and open gates
  HANDOFF.md                        exact continuation instructions
  architecture.md                   runtime/data/model boundaries
  decisions.md                      active durable decisions
  plans/motion-analysis-roadmap.md  maintained roadmap
  phases/P0-P1.md ... P7.md         one detailed conclusion per phase
  history/                          chronological milestones and durable lessons
  reports/                          small sanitized verification snapshots
  local/                            ignored raw logs, snapshots, scripts and private evidence
```

The active root branch is `feature/dual-imu-coaching-analysis`. At this update the root HEAD and remote feature ref are both `be2e4725576775249796d376ef0e64cceb7aa04e`, but the current Slalom-v3 and optional-center-IMU work is still **uncommitted working-tree work**. Do not describe it as published until a later explicit commit/push is verified.

`BiWheel3D/` is a separate local research repository, not a root submodule and not an application dependency. Preserve its index/worktree exactly unless a task explicitly owns research changes. Raw athlete data, generated models, private paths and research evidence stay local.

## Current technical direction

The validated product baseline remains the two wheel-hub sensors `L` and `R`. Source firmware and both apps now additionally support optional chair-center role `C` (`0x43`) for future experiments. The center mounting contract is `+Z` down toward the floor; X/Y remain physical board axes until forward/lateral orientation is measured. Existing trajectory models deliberately ignore C.

Windows keeps the frozen classical recipe first/default and exposes experimental PyTorch/Slalom choices only for research review. Mobile keeps the existing M4 XY-only ONNX default. P3 model promotion remains blocked by independent synchronized moving optical reference and a locked final group.

## Documentation rules

- Keep one current STATUS, one current HANDOFF and one maintained roadmap. Do not create `FINAL`, `FINAL_v2`, duplicate trackers or alternate current-state documents.
- Phase files are conclusions. Historical measured values remain historical even when later work supersedes the old next-step wording.
- `reports/branch-validation.json` is the latest sanitized working-tree verification snapshot. `reports/scheduled-agent-validation.json` is a historical scheduler-maintenance snapshot and is intentionally not rewritten to imitate current results.
- Put raw command logs, screenshots, hashes, build outputs, participant-sensitive evidence, machine-specific receipts and ad-hoc patch scripts under `local/`.
- Do not execute archived scripts in `local/legacy/` blindly.
- Public model semantics/fixtures live under `docs/model_analysis/`; BLE semantics live in `docs/ble-protocol.md`.

The pre-organization state remains preserved under `local/legacy/` and prior verified archives. Current 3-IMU evidence is under `local/three-imu-2026-09-08/`; current document-refresh evidence is under `local/project-docs-refresh-2026-09-08/`.
