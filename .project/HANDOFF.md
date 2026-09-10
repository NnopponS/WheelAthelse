# Current engineering handoff

Updated: 2026-09-10

## v1.8.2 repository state

WheelAthlete **v1.8.2** is consolidated as a Windows-first release line. The final public repository surface is intentionally small:

- `main`
- `release/main-v1.8.2`
- source-only GitHub Release/tag `v1.8.2`

The obsolete remote development/archive/release branches were checked as ancestors of the integrated `main` before deletion. Old visible GitHub Release entries were removed while historical version tags remain for traceability.

## Integrated work

- `feature/dual-imu-coaching-analysis` is contained in `main` history.
- `codex/v1.8.2-repairs` is contained in `main` history.
- `codex/windows-trust-hardening` was merged normally into `main` without conflicts or force-pushing.
- The trust hardening recursively signs/verifies packaged executable components, validates RSA + Code Signing EKU + exact publisher subject, requires timestamps, signs the generated Inno uninstaller/installer and produces a fail-closed `public_release_ready` report.
- The release workflow supports `ALLOW_UNSIGNED_RELEASE=true` community build mode (`is_signed=false`) while embedding available baseline/experimental models, requires dispatch from the exact `v1.8.2` tag, gives write permission only to the publish job, and re-checks `public_release_ready=true` for signed release channels.
- GUI polished: minimal navigation sidebar ("WheelAthlete"), uncluttered headers across pages, window icon integration, polished Analysis timeline typography, Wheel C in Diagnostics and Results with C sample counts, compact Athlete input (240px), and Kinematic Trajectory (XY + Yaw) baseline bound to `Documents/WheelAthlete`.

## Verification recorded on 2026-09-10

- Windows application/acquisition tests: passed.
- Windows packaging-layout tests: **4/4 passed**.
- XIAO host tests: **19/19 passed**.
- M5 host tests: **147/147 passed**.
- Release-manifest tests: passed.
- Python compile checks: passed.
- Working-tree project publication audit: passed.
- Staged project publication audit: passed.
- Git diff checks: passed.
- XIAO PlatformIO L/R/C: fresh build artifacts produced for all three roles.
- M5 PlatformIO L/R/C: fresh build artifacts produced for all three roles.
- Full local unsigned Windows packaging: completed through installer, portable ZIP, checksums and signing report.
- Unsigned signing report: schema 2, 163 executable components, correctly `public_release_ready=false` and `is_signed=false`.

## Current release truth

WheelAthlete product/Windows/firmware version is 1.8.2; BLE protocol remains 1.8.0. The XIAO center role is `C` / `0x43`, with green XIAO identity and Wheel C monitoring. Current production trajectory inference remains L/R-only.

The public v1.8.2 GitHub Release is deliberately source-only. Do not attach the locally generated unsigned installer, portable ZIP or `latest.json`. Installed-client update offers begin only after a future trusted signed release passes the publication gate.

## Publication scope

No new Flutter/mobile source change or mobile binary belongs to this consolidation. Existing mobile source/history remains maintenance-only. Do not stage, reset, clean, merge or push the separate local `BiWheel3D/` repository.

Generated Windows packages, firmware build output, recordings, private logs, local evidence, signing credentials and absolute user paths must not enter source commits. Keep local evidence in ignored `.project/local/`.

## Next engineering work

Repository organization/release consolidation does not require another repair branch. Future source work should start from `main` and use a short-lived focused branch only when necessary; completed branches should be merged/reviewed and removed from the remote surface.

Two external acceptance gates remain:

- obtain/configure a trusted private-key Windows Code Signing certificate with the required EKU, publisher subject and timestamp service before publishing Windows binaries/update manifest;
- when hardware returns, finish center Python-app STOP/QC/reopen/export and simultaneous L/R/C physical acceptance.

These are external/deferred acceptance gates. They do not invalidate the completed source/repository consolidation, but they must not be represented as already accepted.
