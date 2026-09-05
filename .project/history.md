# WheelAthlete — Development History

This is a compact index of important milestones. Detailed implementation history remains in Git.

## Stable mobile data-collection line

- `v0.1.0` (2026-07-06): first usable dual-wheel data-collection MVP
- `v1.7.0` (2026-07-25): stable dual-wheel reliability release
  - app `1.7.0+8`
  - firmware `1.7.0`
  - BLE contract `1.7.0`

Key mobile work before v1.7.0 included dual BLE connection, clock sync, recording, protocol templates, experiment tracking, session tags/search, session preview, quality badges, UTC alignment, and export hardening.

## Windows acquisition evolution on `codex/pc-version`

Important commits:

- `b970b69` — parity / architecture baseline
- `8d0d0a9` — XIAO BLE/timing hardening and diagnostics
- `857a164` — headless Python/Bleak dual-board ingestion engine
- `da6249a` — clock sync, scheduled start, lifecycle acknowledgements
- `118e1bc` — append-only `.waj`, recovery, QC, derived CSV
- `a8927ae` — historical Flutter Windows IPC experiment (retired)
- `4b4aef9` — Android regression checkpoint
- `083d7c8` — historical Flutter Windows UI experiment (retired)
- `f23d1c1` — simulated long-run/fault hardening
- `78b4fba` — physical two-XIAO acceptance harness preparation
- `9a96601` — Python Research Edition desktop UI
- `d81638a` — Python desktop UI polish / workflow hardening
- `0c40859` — production Windows installer packaging

## 2026-09-05 product consolidation

The repository was simplified to match the actual supported product direction:

- keep Flutter mobile (iOS/Android)
- keep Python Windows app (PySide6 + acquisition daemon)
- remove legacy Tkinter desktop GUI
- remove Flutter Windows implementation
- remove Flutter Web scaffold
- consolidate Windows packaging under `packaging/windows/`
- replace duplicated `.project` phase documents/prompts with current canonical state
- advance coordinated product metadata to v1.8.0; mobile build `1.8.0+9`

The retired source remains available in Git history if future comparison is needed.
