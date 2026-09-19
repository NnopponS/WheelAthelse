# Current engineering handoff

Updated: 2026-09-15
Updated: 2026-09-18
Updated: 2026-09-19

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
- Acquisition synchronized recording countdown audio and visual cue streamlining: removed calibration hold message (`"Hold still for calibration… X s"`) in favor of direct countdown timing `5`, `4`, `3`, `2`, `1` on `recordCountdown`, pre-warmed in-memory PCM WAV audio queue worker ensuring reliable non-blocking playback of 1 s interval beeps at 700 Hz (120 ms) across every second without Windows audio DAC power-saving sleep drops, and a 500 ms long start tone at 1200 Hz with persistent "START!" visual display before recording clock transition.

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
## 3-IMU lifecycle correction (2026-09-16)

- Generic v4 remains a useful research comparator, but its frozen one-way Sep-11 audit did not pass the production promotion gate; mean ATE/endpoint regressed against protocol-aware v3.
- A real Windows Model-page 10x5UP trajectory later reproduced the practical v4 failure mode with large repeated path excursions, confirming that the app must not present v4 as the active 3-IMU runtime.
- Windows auto-detection now maps 3-IMU sessions to `IMU v3 (Active)` and keeps v2 as rollback. V4 is labelled `Research - Rejected` and remains available only for explicit comparison/diagnosis.
- Multi-model and C3D comparison/export UI remains available; no C3D/reference data is used as runtime inference input.
- Do not tune a replacement candidate on the Sep-11 audit set. Further v4/v5 research requires development-only groups plus a new untouched participant/day/remount group before any promotion claim.
- V5 is now frozen as a **development-only** candidate selected from Sep-9 grouped CV only. It uses three bounded IMU-motion residual experts (straight, sustained-turn, alternating-turn); the earlier direct dynamic-attitude substitution was rejected after grouped regression.
- The Windows Model page bundles V5 as `IMU v5 (Research - Development Candidate)` and supports V5 trajectory overlays, but 3-IMU auto-selection remains `IMU v3 (Active)` and V2 remains rollback. V5 runtime inference accepts L/R/C IMU only and does not consume C3D, protocol, condition, athlete, or trial identity.
- Current verification after V5 integration: focused Windows model/UI tests **41 passed, 4 skipped**; BiWheel3D v2-v5 odometry tests **25 passed** plus V5 leakage/CV contract tests **2 passed**; official Windows suite **210 passed, 4 skipped**; `verify_project.py` passes with zero errors. These are software/development checks, not a V5 promotion result.
- **WA-CAIF v6** was frozen from Sep-9-only grouped development evidence and exposed research-only; its post-freeze Trial 7 audit retained **41.55 deg** final heading drift, so it was not promoted.
- **SOF-3IMU v7** changes the generic yaw observation rather than adding another residual: raw hub Z remains wheel spin, fixed spin leakage is estimated/removed from hub X/Y, wheel-plane accelerometer orientation recovers independent L/R frame yaw, and only a bounded causal slow hub-minus-center correction reaches the generic physics yaw. The radial-acceleration regression probe was rejected because it worsened Sep-9 yaw proxy error.
- V7 was selected only on Sep-9 grouped LOAO+LOCO (108 loadable trials) with weight 1.0 / 5 s: LOAO **2.3374% ATE, 3.4813% endpoint, 3.0465 deg heading**; LOCO **2.3342%, 3.4690%, 2.9361 deg**. Runtime/model hashes were frozen before the stress audit.
- Post-freeze Trial 7 improved versus V6 to **1.6347% ATE, 2.6496% endpoint, 36.59 deg final heading error** but still did not approach protocol-aware V3 (**1.1189%, 0.1362%, 1.63 deg**). Do not tune V7 from Trial 7 or Sep-11. V7 remains a frozen research development candidate, not a promotion result.
- Windows now bundles V7 and can overlay `SOF-3IMU v7 (Research - Development Candidate)` for explicit research comparison. 3-IMU auto-selection remains `IMU v3 (Active)`; lifecycle-only discovery remains V3 then V2.
- V7 verification: BiWheel3D focused V7 tests **6/6 passed**; focused Windows model/runtime/UI tests **43 passed, 4 skipped**; `verify_project.py` passed with zero errors. The official Windows suite reached **211 passed, 4 skipped** and reproduced one unrelated pre-existing packaging-layout failure requiring the literal `Release workflow must be dispatched on exact tag` in `.github/workflows/release.yml`; no V7/model test failed.
- **DBF-3IMU v8** is the next frozen generic development candidate. It reuses SOF hub-frame yaw as an independent observation but estimates a persistent causal center-yaw bias state that is held across non-stationary straight motion instead of applying only turn-gated correction. Sep-9-only grouped selection retained gain 0.75 / 10 s: LOAO **2.3389% ATE, 3.4715% endpoint, 3.2914 deg heading** and LOCO **2.3326%, 3.4560%, 3.1675 deg**. The numerically stronger gain 1.0 / 10 s mean was rejected by the declared tail/fold guardrails.
- V8 runtime/model/evaluator hashes were frozen before retrospective stress inspection. Post-freeze Trial 7 improved over V7 to **1.4640% ATE, 2.2472% endpoint, 30.23 deg final heading error**, but remains far behind protocol-aware V3 (**1.1189%, 0.1362%, 1.63 deg**). Do not retune V8 from Trial 7 or Sep-11. V8 is research-only and still requires a new untouched participant/day/remount promotion capture.
- Windows bundles V8 as `DBF-3IMU v8 (Research - Development Candidate)` for explicit comparison only. 3-IMU auto-selection remains `IMU v3 (Active)` and lifecycle-only discovery remains V3 then V2.
- V8 verification: BiWheel3D focused V8 tests **5/5 passed**; focused Windows model/runtime/UI tests **44 passed, 4 skipped**; bundled V8 runtime/model SHA-256 values exactly match the frozen research source/model; `verify_project.py` passes with zero errors. The official Windows suite reaches **212 passed, 4 skipped** and reproduces only the same unrelated pre-existing packaging-layout assertion requiring the literal `Release workflow must be dispatched on exact tag`; no V8/model test fails.

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
