# WheelAthlete contributor instructions

Read `.project/STATUS.md`, `.project/HANDOFF.md`, `.project/architecture.md` and the relevant phase conclusion before editing. These are the current records; `.project/local/legacy/` contains historical instructions, not current authorization.

## Scope and safety

Maintain the Flutter iOS/Android application and Python/PySide6 Windows application. Keep Windows BLE/journal ownership in the separate acquisition daemon. Keep mobile independent of a PC inference service. Do not infer chair yaw from XY-only predictions or treat source tests as physical accuracy evidence.

Preserve dirty and staged work. `BiWheel3D/` is a separate local research repository with its own index and remote; do not stage/reset/clean or push it as part of application work. Raw and derived athlete recordings, private logs, absolute user paths, signing keys and generated packages must not enter a source commit. Use ignored `.project/local/` for local evidence.

The current feature branch is `feature/dual-imu-coaching-analysis`. Do not update main/release branches, publish a tag/release, install or flash devices without explicit user authorization. Stable version files and model defaults are not changed just because a feature branch is created.

## Verification and documentation

Run `python scripts/verify_project.py` for working-tree hygiene and `python scripts/verify_project.py --staged` before a commit. Run `python scripts/run_verification.py --suite windows` and `--suite mobile` after relevant changes. The runner uses installed dependencies and writes a fresh local run directory without installing, flashing or publishing anything.

Update the existing STATUS and HANDOFF instead of creating additional final reports. Keep one conclusion per phase under `.project/phases/`, durable history under `.project/history/`, and sanitized measured checks under `.project/reports/`. Keep the output contract and synthetic fixtures under `docs/model_analysis/`. Archive uncommitted history before consolidating it; Git cannot recover files that were never committed.
