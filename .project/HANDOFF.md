# Current engineering handoff

Updated: 2026-09-25

## v1.8.4 rebuild state

WheelAthlete **v1.8.4** is a release candidate rebuilt from the exact v1.8.3 application tag in an isolated worktree. Firmware source matches the provided M5/XIAO snapshot and remains firmware v1.8.2. The intended public surface after verification is:

- `main`
- `release/main-v1.8.4`
- source-only GitHub Release/tag `v1.8.4`

Keep existing `main` history; never force-push. The previous v1.8.4 remote tag/release branch may be replaced only after the exact tested commit is ready. Historical version tags remain for traceability.

## Integrated work

- v1.8.4 restores only the 3D orbitable trajectory view and dynamic equal-distance scaling from the later candidate; the frozen default model remains unchanged.
- Results supports app-managed WheelAthlete CSV imports, a manual date for undated imports, and export through the existing flow. Results and Model trajectory CSV writes run off the GUI thread with progress and visible completion/error state.
- Active-recording BLE counters are deltas from the start of each run; Diagnostics retains lifetime totals and exports sanitized Windows/Bluetooth driver details.
- Window close is blocked with a wait message during trajectory export; recording close finalizes the journal and waits for daemon shutdown acknowledgement. Cleanup options are opt-in, confirmed, and limited to managed WheelAthlete locations.
- The candidate's v1.8.4 tag-push workflow rejects manual dispatch, skips Windows/Android artifact builds, and publishes release notes only. The former remote `v1.8.4` tag resolved to `eab67ca23edfa078cd866008e2e1f1c81648b08c` and does not contain this guard; replace that old tag and release branch from the final tested commit before the tag push triggers publishing.
- No mobile source/assets, `BiWheel3D/`, firmware queue-backlog fix, or locked paper-test cohort change is included.

Candidate software acceptance: Windows suite **241 passed, 6 skipped**; M5 host tests **147 passed**; XIAO host tests **19 passed**; PlatformIO builds succeeded for M5/XIAO left, right, and center; Python compile check and working-tree/staged project hygiene passed. The GitHub API reports no existing v1.8.4 Release object. Commit/ref publication remains pending. Inno Setup is not installed here, so packaging-layout tests passed but the installer script was not compiled. These checks do not prove physical or cross-computer BLE acceptance.

## Historical v1.8.3 verification

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

WheelAthlete product/Windows candidate version is 1.8.4; firmware is 1.8.2; BLE protocol remains 1.8.0. The XIAO center role is `C` / `0x43`, with green XIAO identity and Wheel C monitoring. Current production trajectory inference remains L/R-only. No cross-computer BLE acceptance was available; do not claim a transport fix.

The v1.8.4 GitHub Release must remain source-only until trusted signing is configured. Do not attach an unsigned installer, portable ZIP or `latest.json`. Installed-client update offers begin only after a trusted signed release passes the publication gate.

## Publication scope

This v1.8.4 candidate includes no new Flutter/mobile source change and no mobile binary. Existing mobile source/history remains maintenance-only. Do not stage, reset, clean, merge or push the separate local `BiWheel3D/` repository.

Generated Windows packages, firmware build output, recordings, private logs, local evidence, signing credentials and absolute user paths must not enter source commits. Keep local evidence in ignored `.project/local/`.

## Next engineering work

After v1.8.4 source publication, continue from `main` and use short-lived focused branches only when needed. Keep the two external gates visible:

Two external acceptance gates remain:

- obtain/configure a trusted private-key Windows Code Signing certificate with the required EKU, publisher subject and timestamp service before publishing Windows binaries/update manifest;
- when hardware returns, finish center Python-app STOP/QC/reopen/export and simultaneous L/R/C physical acceptance.

These are external/deferred acceptance gates. They do not invalidate the completed source/repository consolidation, but they must not be represented as already accepted.
