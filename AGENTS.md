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
