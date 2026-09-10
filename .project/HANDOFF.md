# Current engineering handoff

Updated: 2026-09-10

## Current objective

Finish the professional WheelAthlete **v1.8.2** consolidation. The intended public branch surface is:

- `main`
- `release/main-v1.8.2`

The current GitHub Release should be only `v1.8.2`; older Release entries may be removed while historical tags remain available for traceability.

## Work already integrated

- `feature/dual-imu-coaching-analysis` is already an ancestor of the 1.8.2 repair line and therefore already exists in `main` history.
- `codex/v1.8.2-repairs` is already merged into `main`.
- `codex/windows-trust-hardening` has now been merged normally into `main` without conflicts or force-pushing.
- The trust hardening recursively signs/verifies packaged executable components, validates RSA + Code Signing EKU + exact publisher subject, requires timestamps, signs the generated Inno uninstaller/installer and generates a fail-closed `public_release_ready` report.

## Publication scope

Do not include new Flutter/mobile source changes in this consolidation and do not publish any mobile binary/update asset. Existing mobile source/history remains maintenance-only. Do not stage, reset, clean, merge or push the separate local `BiWheel3D/` repository.

Generated Windows packages, firmware build output, recordings, private logs, local evidence, signing credentials and absolute user paths must not enter source commits. Keep local evidence in ignored `.project/local/`.

## Current release truth

WheelAthlete product/Windows/firmware version is 1.8.2; BLE protocol remains 1.8.0. The XIAO center role is `C` / `0x43`, with +Z down and green XIAO identity. Current production trajectory inference remains L/R-only.

The source-only v1.8.2 GitHub Release must not advertise Windows binaries or an updater manifest until trusted Authenticode signing is available. Fresh 2026-09-10 consolidation verification passed 195/195 Windows tests, 4/4 packaging-layout tests, 19/19 XIAO host tests, 147/147 M5 host tests, release-manifest tests, compile checks, project hygiene and diff checks. Fresh XIAO and M5 L/R/C firmware build artifacts were produced, and the complete unsigned local Windows package build passed. The unsigned signing report remains correctly blocked with `public_release_ready=false`.

## Required finish sequence

1. Refresh current README/project/release/protocol documentation and remove stale 1.8.0/1.8.1 branch or yellow-XIAO statements from current documents.
2. Keep repository layout stable where paths are part of packaging/runtime contracts; improve organization through canonical docs/indexes and ignore policy rather than risky late release-directory moves.
3. Run project hygiene, diff/private-material review, full Windows verification, release-generator checks and maintained firmware host/build checks.
4. Commit only reviewed root-repository changes; verify no mobile application source diff and no `BiWheel3D` entry.
5. Push `main` normally.
6. Create/push `release/main-v1.8.2` at the exact tested commit.
7. Replace the current source-only `v1.8.2` tag/Release target with that final tested commit. Keep binary assets absent while signing is unavailable.
8. Remove obsolete remote branches so GitHub shows only `main` and `release/main-v1.8.2`.
9. Remove old visible GitHub Release entries while retaining historical tags unless the user later explicitly asks to rewrite version history.

## Deferred gates

- No trusted private-key Code Signing certificate with the required EKU is currently available, so `public_release_ready` remains false for public Windows binaries.
- Final center Python-app QC/reopen/export and simultaneous L/R/C physical acceptance remain deferred until hardware returns.

These are external/deferred acceptance gates, not reasons to leave the source repository disorganized.
