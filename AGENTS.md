# WheelAthlete contributor instructions

Read `.project/STATUS.md`, `.project/HANDOFF.md`, `.project/architecture.md` and the relevant phase conclusion before editing. These are the current records; `.project/local/` contains ignored local evidence and historical snapshots, not publication material.

## Scope and safety

The v1.8.2 public release is Windows-first. Maintain the Python/PySide6 Windows application and the M5/XIAO firmware as the active release surface. Existing Flutter Android/iOS source is maintenance-only and **new mobile source changes or mobile release assets must not be included in the current v1.8.2 publication unless the user explicitly requests them**.

Keep Windows BLE/journal ownership in the separate acquisition daemon. Do not infer chair yaw from XY-only predictions or treat software tests as physical accuracy evidence.

`BiWheel3D/` is a separate local research repository with its own index and remote. Do not stage, reset, clean, merge or push it as part of WheelAthlete root-repository work. Raw/derived athlete recordings, private logs, absolute user paths, signing keys and generated packages must not enter a source commit. Use ignored `.project/local/` for local evidence.

## Branch and release policy

The normal public branch surface after the v1.8.2 consolidation is `main` plus `release/main-v1.8.2`. Do not force-push `main`. Release tags should identify exact tested commits. Historical release tags may be retained even when old GitHub Release entries/branches are removed from the visible project surface.

Public Windows installer/portable/update assets require the trusted signing gate. Never publish a local unsigned package as a trusted release or as a fix for SmartScreen/Application Control trust.

## Verification and documentation

Run `python scripts/verify_project.py` for working-tree hygiene and `python scripts/verify_project.py --staged` before a commit. Run `python scripts/run_verification.py --suite windows` after relevant Windows changes. Run maintained firmware tests/builds when firmware or release identity changes. Flutter verification is not a v1.8.2 publication gate while mobile remains excluded from this release.

Update the existing STATUS and HANDOFF rather than creating additional final reports. Keep one conclusion per phase under `.project/phases/`, durable history under `.project/history/`, sanitized measured checks under `.project/reports/`, model contracts under `docs/model_analysis/` and BLE semantics under `docs/ble-protocol.md`.

<!-- graft:start -->
## Graft — repo context graph

This repo is indexed in `graft/`: small linked markdown nodes that explain each
system and carry exact file:line spans, kept in sync with the code through git.

For ANY task here — understanding how something works, finding where code lives,
or scoping a change — get context from the graph before grepping or opening
source files. Re-ask freely (it's cheap) and reuse literal identifiers you
already have (symbol, error string, file name) as the query. New to this repo?
Run `graft map` first — a token-budgeted orientation (dir clusters, hubs,
hotspots), no LLM, no key.

- Run `graft ask "<your question>" --source` → ranked nodes with the relevant
  code spans inlined (each hit's ≤8-line crux by default; `--full` for whole
  definitions when the crux isn't enough). Match the tool to the task shape:
  for understanding or editing, the top node IS the answer — cite its
  `covers:` file:line spans and edit straight from `--source`. For
  exhaustive tasks ("every occurrence / every caller of this pattern"), ranked
  results are top-N, not complete — run `graft grep "<literal>"` instead
  (exhaustive over indexed files, grouped by enclosing symbol), falling back
  to raw `grep -rn` only for unindexed files.
- `graft skeleton <file>` → every definition's signature + span, ~10× cheaper
  than reading the file; use it to skim an API surface.
- `graft callers <symbol>` gives precomputed, exact edges — who calls this.
  Add `--direction out` for what it calls, or `--depth N` to walk
  transitively for the full blast radius. For structural questions, skip
  ranking and use this directly.
- Or browse: `graft/INDEX.md` lists every node; follow the links.
- Monorepos and folders of multiple repos rank fairly across sub-projects —
  hits carry `[scope/]` labels naming which one they're from. Narrow with
  `graft ask "<task>" --in <scope>/` once you know where you're working.

If a returned span is truncated ("+N more lines"), open the file at that exact
range before finalizing. Only open source files when a node genuinely lacks a
needed detail, and then at the exact file:line the node points to — never
re-read whole files.

After big code changes, refresh the graph with `graft build` (deterministic,
no API key, $0).
<!-- graft:end -->
