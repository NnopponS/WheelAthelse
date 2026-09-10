# WheelAthlete engineering workspace

Updated: 2026-09-10.

Start with **STATUS.md**, then **HANDOFF.md**. These two files are the current source of truth. Read **decisions.md** before changing architecture, sensor roles, model defaults, release behavior or publication scope.

## Canonical layout

```text
.project/
  README.md                         navigation and housekeeping policy
  STATUS.md                         current measured state and open gates
  HANDOFF.md                        exact continuation instructions
  architecture.md                   runtime/data/model boundaries
  decisions.md                      active durable decisions
  plans/                            maintained execution and research plans
  phases/                           one detailed conclusion per engineering phase
  history/                          chronological milestones and durable lessons
  reports/                          small sanitized verification snapshots
  local/                            ignored raw logs, snapshots and private evidence
```

## Current repository state

WheelAthlete is consolidating on `main` with a single release branch `release/main-v1.8.2`. Feature/repair/trust work that belongs to 1.8.2 is integrated into `main`; old remote development/release branches are not part of the intended public branch surface after consolidation.

The separate local `BiWheel3D/` tree is an independent research repository, not a root submodule and not an installed WheelAthlete dependency. Never stage, reset, clean or publish it as part of root-repository maintenance.

## Current technical direction

The validated sensing baseline is the two wheel-hub sensors `L` and `R`. Firmware and acquisition code additionally support optional chair-center role `C` (`0x43`) for experiments. The center contract is +Z down; X/Y remain physical board axes until measured. XIAO C uses green identity. Existing production trajectory models deliberately ignore C.

The Windows installed default remains the frozen classical L/R model. Experimental research estimators remain opt-in and must not be represented as production defaults or independently validated physical accuracy.

## Documentation rules

- Keep one current STATUS, one current HANDOFF and maintained plans; do not create duplicate `FINAL`, `FINAL_v2` or alternate current-state trackers.
- Phase files are conclusions. Historical measured values may remain historical even when later work supersedes old next-step wording.
- Keep raw command logs, screenshots, hashes, build products, machine-specific receipts and private evidence under `local/`.
- Public model semantics/fixtures belong under `docs/model_analysis/`; BLE semantics belong in `docs/ble-protocol.md`.
- Generated application/firmware output, recordings and signing material never belong in source commits.

## Release boundary

v1.8.2 is Windows-first. New mobile source changes and mobile release assets are excluded from the current publication. Public Windows binaries remain blocked until the trusted signing gate passes; a source-only release may exist while this external gate is open.
