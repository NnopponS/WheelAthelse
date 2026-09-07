# WheelAthlete engineering workspace

Start with **STATUS.md**, then **HANDOFF.md**. These are the only current status and continuation records.

## Directory contract

```text
.project/
  README.md          Navigation and housekeeping policy
  STATUS.md          Current phase status, capabilities and verified checks
  HANDOFF.md         Next actions, branch/publication scope and working rules
  architecture.md    Runtime/data ownership and model boundaries
  decisions.md       Durable engineering and release decisions
  plans/             The active two-hub roadmap
  phases/            One conclusion per phase, not competing final reports
  history/           Milestones and durable lessons
  reports/           Small sanitized verification reports
  local/             Ignored logs, private evidence, archives and generated files
```

The active branch is `feature/dual-imu-coaching-analysis`, not a release line. The root repository is `NnopponS/WheelAthelse`; the product name remains **WheelAthlete**. No repository rename, main merge, release tag or updater publication is part of this work.

## Rules that keep this folder readable

Keep raw evidence, ad-hoc scripts, console logs, screenshots with participant information, machine paths and generated packages under `local/`. Never add them to Git. Use date/topic subdirectories there. Store reusable verification code under `scripts/`, not in this directory. Update the same STATUS/HANDOFF files; do not create FINAL, FINAL_v2 or model-specific alternate trackers.

The complete pre-organization state was preserved byte-for-byte locally: unpacked under `local/legacy/` and in `local/branch-handoff-2026-09-08/project-state-before.zip`. The move manifest and original hashes are in that run folder. Historical scripts are archived for reference and must not be blindly rerun after relocation.

Public contract and synthetic fixtures: `docs/model_analysis/`. Detailed phase conclusions: `phases/`. Historical private journal paths and names are intentionally not published.
