# Current engineering handoff

Updated: 2026-09-24

## Current priority: WheelAthlete v1.8.4 recording reliability

The user's supplied 100 Hz, 17.7-minute diagnostic supports XIAO-side BLE-notification backpressure: device queue drops and transport failures dominated while Windows notification/journal queues did not overflow. The exact controller failure reason was not logged. XIAO firmware 1.8.3 fills BLE packets to 12 samples only when its queue backs up, preserves valid stored L/R/C identity across a shared flash, and prints the resolved role after configuration loads. M5 firmware stays 1.8.2.

Windows recording now waits for the daemon's confirmed start event and delays the PC cue by one second. Model/Results includes an optional local XYZ view, QC reason visibility, input-quality warnings, comparison-aware 2D/3D selection, and a tooltip explaining the loss counter's limits. Checks passed: 231 Windows tests, 5 skipped; project verification; 21 XIAO host tests; all three role builds. The three connected boards were flashed and reported the correct L/R/C identities and 1.8.3 firmware. An 18-minute stationary L/R/C record ran 1080.326 s and finalized GOOD with 331,815 journal samples, zero gaps/device drops/transport failures/host overflows, no QC reasons and no journal overflow. This validates this acquisition run, not trajectory accuracy.

The source is release-ready after final staged verification. Push the tested commit to `main` and `release/main-v1.8.4`, create exact tag `v1.8.4` without force-pushing, and monitor the Windows workflow for a signed setup.exe, portable ZIP, checksums, signing report and stable update manifest. Signing secret readiness is unknown; if CI signing fails, leave the release unpublished rather than use unsigned assets.


## v1.8.3 repository state

WheelAthlete **v1.8.3** is consolidated as a Windows-first release line. The final public repository surface is intentionally small:

- `main`
- `release/main-v1.8.3`
- source-only GitHub Release/tag `v1.8.3`

The obsolete remote development/archive/release branches were checked as ancestors of the integrated `main` before deletion. Old visible GitHub Release entries were removed while historical version tags remain for traceability.

## Integrated work

- `feature/dual-imu-coaching-analysis` is contained in `main` history.
- `codex/v1.8.2-repairs` is contained in `main` history.
- `codex/windows-trust-hardening` was merged normally into `main` without conflicts or force-pushing.
- The trust hardening recursively signs/verifies packaged executable components, validates RSA + Code Signing EKU + exact publisher subject, requires timestamps, signs the generated Inno uninstaller/installer and produces a fail-closed `public_release_ready` report.
- The release workflow supports `ALLOW_UNSIGNED_RELEASE=true` community build mode (`is_signed=false`) while embedding available baseline/experimental models, requires dispatch from the exact `v1.8.3` tag, gives write permission only to the publish job, and re-checks `public_release_ready=true` for signed release channels.
- GUI polished: minimal navigation sidebar ("WheelAthlete"), uncluttered headers across pages, window icon integration, polished Analysis timeline typography, Wheel C in Diagnostics and Results with C sample counts, compact Athlete input (240px), and Kinematic Trajectory (XY + Yaw) baseline bound to `Documents/WheelAthlete`.
- Acquisition synchronized recording countdown audio and visual cue streamlining: removed calibration hold message (`"Hold still for calibration… X s"`) in favor of direct countdown timing `5`, `4`, `3`, `2`, `1` on `recordCountdown`, pre-warmed in-memory PCM WAV audio queue worker ensuring reliable non-blocking playback of 1 s interval beeps at 700 Hz (120 ms) across every second without Windows audio DAC power-saving sleep drops, and a 500 ms long start tone at 1200 Hz with persistent "START!" visual display before recording clock transition.
- Acquisition QC metadata display: Final QC summary card now explicitly displays the recorded Experiment topic, Trial number, and athlete name (`Experiment: <topic> • Trial <trial> • Athlete: <name>`), with metadata preserved and forwarded across daemon IPC, LiveController, and DemoController.
- **Windows Direct In-App Auto-Updater Overhaul**:
  - Replaced browser redirection to GitHub Releases with in-app background download of verified installer `.exe`.
  - In `applications/wheelathlete_windows/tools/pc_gui/update_service.py`, `installer_command(installer, *, silent=False)` supports interactive GUI setup mode (`silent=False` omits `/VERYSILENT` and `/SUPPRESSMSGBOXES`).
  - In `applications/wheelathlete_windows/tools/pc_gui/main_window.py`, `_apply_downloaded_update()` guards active recording states, invokes `self.update_controller.install(silent=False)`, and quits the application (`QApplication.quit()`). The installer wizard dialog launches directly on the Windows desktop for the user to proceed.
- **Mobile App (Flutter) Feature Parity**:
  - Re-aligned `applications/wheelathlete_mobile` with the Windows desktop application per explicit user request.
  - In `lib/ui/acquisition_page.dart`: Added optional Athlete Name input (`_athleteController`), editable Trial stepper with `-` / `+` buttons and numeric field (`_trialController`), and auto-increment on "New Recording".
  - Post-recording Final QC card matches Windows layout: color-coded `Final QC: <GOOD|FAIR|POOR> • <duration> s`, subtitle `Experiment: <topic> • Trial <trial> • Athlete: <athlete>`, and detailed diagnostics for sequence gaps, dropped samples, FIFO faults, and degradation reasons.
  - In `lib/ui/results_page.dart`: Displays Athlete Name on session cards, includes Athlete Name in search filtering, and provides "Export CSV (Windows)" invoking `exportSessionsWindowsFormat` to generate `{TargetDirectory}/{Topic}/{Topic}_Trial{trialNumber}_{athlete}.csv`.
  - In `lib/export/export_actions.dart`: Implemented `exportSessionsWindowsFormat` and added unit test coverage in `test/export/export_actions_test.dart` (using `final athleteMeta = SessionMeta(...)` to respect Dart `DateTime` non-const constructor semantics).
- **GitHub Release Publication (v1.8.3)**:
  - Changes pushed to `main` and tag `v1.8.3`.
  - Automated GitHub Actions Release workflow (Run [#35434186521](https://github.com/NnopponS/WheelAthelse/actions/runs/35434186521)) successfully built and published:
    - Windows: `WheelAthleteSetup-1.8.3.exe` (58.9 MB) & `WheelAthlete-1.8.3-portable.zip` (83.5 MB)
    - Android: `WheelAthlete-1.8.3-android.apk` (120.1 MB) & `WheelAthlete-1.8.3-android.aab` (79.6 MB)
    - Manifest & Checksums: `latest.json`, `SHA256SUMS.txt`, signing reports.

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

WheelAthlete product/Windows version is 1.8.3; firmware is 1.8.2; BLE protocol remains 1.8.0. The XIAO center role is `C` / `0x43`, with green XIAO identity and Wheel C monitoring. Current production trajectory inference remains L/R-only.

The public v1.8.3 GitHub Release contains published release assets: Windows installer (`WheelAthleteSetup-1.8.3.exe`), Windows portable archive (`WheelAthlete-1.8.3-portable.zip`), Android APK (`WheelAthlete-1.8.3-android.apk`), and Android app bundle (`WheelAthlete-1.8.3-android.aab`), built from exact tag `v1.8.3` by CI Run #35434186521.

## Publication scope

Source commits are tracked on `main` and tag `v1.8.3`. Do not stage, reset, clean, merge or push the separate local `BiWheel3D/` repository.

Generated Windows packages, firmware build output, recordings, private logs, local evidence, signing credentials and absolute user paths must not enter source commits. Keep local evidence in ignored `.project/local/`.

## Next engineering work

Repository organization/release consolidation does not require another repair branch. Future source work should start from `main` and use a short-lived focused branch only when necessary; completed branches should be merged/reviewed and removed from the remote surface.

Two external acceptance gates remain:

- obtain/configure a trusted private-key Windows Code Signing certificate with the required EKU, publisher subject and timestamp service before publishing Windows binaries/update manifest;
- when hardware returns, finish center Python-app STOP/QC/reopen/export and simultaneous L/R/C physical acceptance.

These are external/deferred acceptance gates. They do not invalidate the completed source/repository consolidation, but they must not be represented as already accepted.
