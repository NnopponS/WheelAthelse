# WheelAthlete current status

## Active session: v1.8.2 repairs (2026-09-10)

Branch: `main`. Implementation and local acceptance are complete. The maintained execution plan is
`.project/plans/v1.8.2-repair-release.md`.
Pre-existing tracked changes and untracked source were copied to ignored
`.project/local/v1.8.2/preexisting/`, with staged/unstaged binary patches.

Software source publication is complete. Results, graceful daemon shutdown, signing support,
portable model bundles, center firmware/clock repair, release documentation,
Windows packaging, and the installed lifecycle are complete. The Python-app C
record/QC/reopen/export check and full L/R/C hardware acceptance are deferred
until the boards are available. Public binary publication remains gated by a
trusted Windows signing identity.
Signing account is unavailable. On 2026-09-09 the user explicitly authorized a
source fix, build, and flash of the currently connected green XIAO C after
identity re-enumeration and host-test/build gates. L/R flashing is not authorized.

Current hardware evidence: COM20 enumerated as Seeed USB VID:PID `2886:8045`,
serial `B303B939495B5F33`; BLE advertised `WheelAthlete-XIAO-C`. An unflashed
C-only run completed for 1,823.342 s with 184,410 host samples, zero sequence
gaps/replays/malformed packets/host queue faults, and firmware counters reporting
zero queue drops, transport failures, FIFO faults, or FIFO-dropped samples. STOP
was acknowledged. The firmware identified itself as 1.8.0, not 1.8.1. Streaming
did not stop and the red/check symptom was not reproduced. The saved five-point
clock fit reports an implausible 107,943.7 ppm drift and zero RTT, so clock-sync
diagnostics are the next root-cause target. Raw evidence is ignored under
`.project/local/v1.8.2/xiao_c_live_30m.json`. The full L/R/C gate remains open.

On 2026-09-10 the same center identity was flashed successfully with the 1.8.2
center build. USB returned on COM20 with the same serial and BLE read-back reports
firmware 1.8.2, role C, 100 Hz, ±4g and ±2000 deg/s. Build hashes are
`53ea4cd01b0741e59d6ac84bdf9225337211b623ab6a76cd862456f45e1ea230`
for `firmware.zip` and
`c0ea850d2738e37e3753e0b26e315b84724ae1e092d7c77ba1abc7ff284ddce4`
for `firmware.hex`. The post-flash run reached 1,780.865 s before the board was
removed. Its last 1,750 s snapshot contained 179,290 samples with zero gaps,
duplicates, out-of-order or malformed packets, host queue faults, firmware queue
drops, transport failures, FIFO faults, or FIFO-dropped samples. Because the
target duration, final STOP acknowledgement, Python-app journal QC/reopen/export,
and simultaneous L/R/C run were not completed, this is strong partial runtime
evidence rather than physical acceptance. The user no longer has the boards
available; all remaining hardware work is deferred without changing the software
release conclusions.

### Stage 2 - Results browser: focused implementation complete

The Results page now uses one session-ID selection set across the Day / Experiment
hierarchy and flat table. It provides `Select this day`, `Select all recordings`,
and `Clear selection`; selection survives filtering and collapse, and the UI
shows the unique count plus date scope. The underlying `topic` storage contract
is retained while operator-facing labels use `Experiment`.

Focused offscreen verification on 2026-09-09: **10/10 passed** across
`test_results_date_utc.py` and `test_gui_smoke.py`, covering day/all selection,
filter persistence, collapse, duplicate IDs, empty results, local midnight,
row highlighting, and batch export. Full Windows verification remains pending.

### Stage 3 - installed daemon shutdown: source and installed acceptance complete

Daemon IPC now has an explicit shutdown request that finishes an active journal,
stops live streaming, acknowledges the caller, then exits. Inno Setup invokes an
installation-specific PowerShell helper before upgrade and uninstall. The helper
targets only daemon executables inside the selected install root, supports the
new shutdown request, drains older daemon live/recording state, and blocks removal
with an actionable failure message if a verified process cannot stop. User data
roots are not removal targets. Focused IPC/packaging checks pass. A real 1.8.2
install/launch/daemon/upgrade/uninstall/reinstall cycle completed on 2026-09-10:
the daemon exited gracefully with code 0 during upgrade and through the installed
helper, the GUI stayed alive through its launch smoke, and final reinstall left
1.8.2 registered under `Documents\WheelAthlete`.

### Stage 4 - Windows signing: source complete, external gate open

The build signs and verifies the GUI, daemon, and installer when a certificate
thumbprint and RFC3161 timestamp URL are supplied, then emits Authenticode status
and SHA-256 checksums. The Windows-only release workflow imports a configured PFX,
requires valid signatures, excludes mobile artifacts and generates a Windows-only
update manifest. No signing identity is currently available, so a public trusted
v1.8.2 release remains blocked; unsigned packages do not solve download reputation
or Application Control error 4551.

### Stage 5 - model menu and portable bundles: focused implementation complete

Model menus use concise names such as `Classical v1`, `Residual v1`, `Slalom v1`,
`Hybrid v1`, and `Mobile M4`. Technical descriptions, runtime, version, input,
output, and experimental status are shown below the selector. New models may use
a self-contained `wheelathlete-model.json` schema v1 bundle in the existing user
model library. Validation confines artifact/config paths to the bundle, verifies
the existing adapter, runtime packages, preprocessing identity, 100 Hz feature
contract, L/R roles, output units, and schema before inference. Legacy imports and
defaults remain. Focused model checks passed **31/31**, including clean discovery
without `BiWheel3D` and rejection of missing/escaping/incompatible bundles.

### Stage 6 - center timing and fault diagnosis: repair flashed, hardware gate deferred

The host clock root cause was confirmed on this Windows/Python build:
`time.monotonic_ns()` uses 15.625 ms `GetTickCount64`, producing zero-RTT sync
observations and unstable drift, while `time.perf_counter_ns()` uses 100 ns
`QueryPerformanceCounter`. The acquisition, journal, lifecycle, transport, GUI
countdown, and demo clock domain now consistently use the high-resolution clock.
A physical 36-observation post-fix probe recorded 4.48-21.19 ms RTT and ended at
43.19 ppm rather than the earlier invalid 107,943.7 ppm five-point fit.

Firmware now marks `Retry`/red-blue only while consecutive BLE notification
failures remain active; the cumulative transport-failure counter is preserved.
Cumulative queue/FIFO loss remains an error and is not cleared. The Windows sensor
card now names the exact fatal, sequence, host-queue, firmware-queue, FIFO,
malformed-packet, or active-retry reason instead of displaying an unexplained
`CHECK`. XIAO checks pass 19/19, focused host clock/status checks pass 11/11, and
the center 1.8.2 build succeeded at 10.8% RAM / 18.2% flash. The post-flash run
reached 1,780.865 s with zero observed transport/sample faults before board
removal. Final STOP/QC/export and full L/R/C acceptance remain open until hardware
is available.

### Stage 7 - coordinated version and release documentation: source complete

The coordinated product/Windows/firmware version is 1.8.2; retained mobile source
is 1.8.2+12. The root README is Windows-first and states that Flutter is under
maintenance and not currently available. The Windows-only release workflow and
manifest have no mobile artifact or update offer. Packaging documentation now
covers trusted signing, the distinction between reputation and error 4551,
installation-specific graceful shutdown, data preservation, and complete
uninstall verification. Portable model instructions, changelog, and accurate
gated 1.8.2 release notes are present. Documentation diff hygiene passes.

The 1.8.1 evidence below is historical and does not validate these new changes.

### Stage 8 - release verification: active, Flutter deferred

Final project publication hygiene passed with 455 candidate files and zero errors.
Python dependency audit reports no known vulnerabilities. XIAO host checks pass
19/19 and the left/right 1.8.2 builds both succeed at 10.8% RAM / 18.2% flash.
M5 host checks pass 147/147 and all three role builds succeed at 15.4% RAM /
62.3% flash. The first Windows suite run passed 193 checks and exposed two
date-group failures caused by demo timestamps crossing local midnight; demo dates
now use explicit local-day anchors, the focused date suite passes 4/4, and the
full Windows rerun passes **195/195**.

After the final installer preservation change, project hygiene passed again and
the complete Windows suite passed **195/195** in 59.02 s. Regenerable Flutter
build metadata, PyInstaller intermediates, both firmware `.pio` trees, and 14
Python/test cache directories were removed with resolved workspace-bounded paths.
Release packages and ignored lifecycle/hardware evidence were retained.
The reviewed 111-path consolidation is staged; staged publication hygiene passes
with the same 455 candidates and zero errors. No absolute user path, signing key,
generated release package, or `BiWheel3D` file is present in the index.

The reviewed source was committed on `codex/v1.8.2-repairs` as `667a7e0`
(`release: prepare WheelAthlete 1.8.2 repairs`). The tracked worktree was clean
after commit. The repair branch is published at `origin/codex/v1.8.2-repairs`.
It was merged without force or conflicts into local `main` at `c66c6ba`. That
exact merge tree passes project hygiene with 455 candidates and zero errors and
passes the full Windows suite **195/195** in 57.527 s. The final documentation
tip `29c007c` also passes project hygiene and Windows **195/195**, then `main`
was pushed normally from `5fbf9ee` through `29c007c`. Binary release publication
remains blocked.

The user directed this release to skip Flutter verification and instead complete
the XIAO C record/QC workflow in the Python app. The mobile suite was stopped and
is not a v1.8.2 release gate. Before it was stopped, `flutter analyze` passed; a
full test run reached 714 passes with one stale coordinated-version assertion.
Mobile release identity constants and that assertion were aligned to 1.8.2+12;
the focused version/update checks pass 2/2. Mobile remains under maintenance and
has no v1.8.2 download or update offer.

### Stage 9 - Windows artifact and lifecycle evidence: complete, signing gate open

The Windows application and daemon were packaged with the release source. The
final installer is `WheelAthleteSetup-1.8.2.exe`, 65,036,035 bytes, SHA-256
`eb3b7da422c25c02a4758ade8881e33728d3132c13e1b9f092005e9c3dbaf9a4`.
The portable ZIP SHA-256 is
`5b0263c21a47fe8bf477a5c0417c94c1ab4acc8633199b809f2c0174712634ca`.
Authenticode reports `NotSigned` for the GUI, daemon, and installer, so
`public_release_ready` is false and these artifacts must not be published as a
trusted release.

### Stage 10 - GitHub release-page replacement: authorized and active

On 2026-09-10 the user explicitly authorized deleting the GitHub Release entries
for v1.8.0 and v1.8.1 and adding v1.8.2 as the latest release. Their release
metadata and asset digests are preserved under ignored
`.project/local/v1.8.2/github-releases-before-replacement/`. Historical Git tags
will be retained. Because trusted signing is still unavailable, v1.8.2 will be a
source-only GitHub Release with no installer, portable ZIP, update manifest, or
mobile binary. Release notes state these limits directly.

The final installed lifecycle used the real default Documents layout and covered
install, GUI launch, daemon listen/shutdown, same-version upgrade while the daemon
was running, uninstall, an eight-second delayed leftover audit, and reinstall.
Uninstall removed application binaries, registration, desktop/Start Menu
shortcuts, and all installed processes. Hash comparison preserved all 330 session
files and all 12 model files. The installed default model seed now uses both
`onlyifdoesntexist` and `uninsneveruninstall`, so upgrades do not overwrite models
and uninstall does not remove seeded or custom files.

An earlier test installer exposed that Inno had previously tracked and removed
seeded model files even though the directory itself was preserved. Two removed
defaults were restored immediately. The ONNX restored byte-identically; the
pre-test 639-byte recipe could not be recovered from Git, local copies, or an
available shadow copy, so it was restored from the current source. Across the
original 350-file user-data manifest, no file is missing and that recipe is the
only changed hash. This limitation is retained in local evidence and must not be
reported as byte-identical preservation of the initial recipe.

Updated: 2026-09-08. Root branch: `release/main-v1.8.1`.

**Current stage: WheelAthlete Windows + firmware 1.8.1 release branch published, with optional three-IMU acquisition/review support. Model promotion remains unchanged.**

Root release commit: `30e99d83ae9d0da072721306f65501a35024813a` (`release: WheelAthlete Windows and firmware 1.8.1`). GitHub confirms `origin/release/main-v1.8.1` points to that SHA. The local annotated tag `v1.8.1` exists, but its tag push could not complete after the branch publication because the local Git client temporarily could not resolve `github.com`.

## Phase state

| Phase | Current state | Deep conclusion |
|---|---|---|
| P0 | Complete | Repository ownership, dirty-state preservation and reproducible baseline established. |
| P1 | Local evaluation repair complete | Timing/crop/reference bookkeeping improved; independent physical-reference acceptance still missing. |
| P2 | Local diagnostics complete | Zero-delay/physics diagnostics exposed real improvements and counterexamples; no production winner selected. |
| P3 | **Blocked for promotion** | PyTorch residual v1 and Slalom-specific adapters are research candidates only; no independent locked final/reference evidence exists. |
| P4 | Source complete | Shared original-time/kinematics/QC contract implemented; C may be retained in a session but legacy analysis explicitly consumes L/R only. |
| P5 | Source complete + active research review | Windows can inspect finalized sessions/research NPZ, PyTorch residual v1, Slalom course v1 and calibrated v3; defaults unchanged. |
| P6 | Existing-model workflow complete | Mobile review/export works and L/R/C acquisition is supported; M4 remains XY-only and center-aware inference is not implemented. |
| P7 | Capture/readiness updated | Next physical work is center bench acceptance plus new synchronized L/R/C + valid C3D capture; coach/final acceptance still pending. |

## Model state

### Production/default behavior

- **Windows default:** frozen classical XY+yaw recipe; unchanged.
- **Mobile default:** original M4 XY-only ONNX; unchanged.
- No current model uses the center IMU.
- No model has been promoted to `current_best` from this research continuation.

### Experimental PyTorch residual v1

A C3D-supervised residual BiGRU is available for explicit Windows research review. It keeps a zero-delay/center-mean physics baseline and predicts residual signed-speed/yaw-rate corrections. The checkpoint SHA-256 is `d838e98e94d5db2e490bf64816e78a35b367ab2d079a54c9d192848973138a45`.

Historical grouped validation diagnostics showed useful local improvement, but long Slalom drift remains a major counterexample. Historical `_05` trials are regression evidence, not a pristine final holdout. This model is not independently accepted.

### Slalom fixed-course work

The user identified the key long-horizon failure: small heading/waveform errors around repeated U-turns rotate later straight segments and accumulate large XY drift.

- **Course v1:** keeps residual-v1 weights frozen and uses the declared complete-Slalom return-to-start protocol. On `SL_04`, full-cache ATE changed from about `0.7904 m` raw to `0.2187 m`, heading RMSE from `21.67 deg` to `4.53 deg`. Near-zero endpoint is partly imposed by course closure and is **not independent odometry evidence**.
- **Course v2:** rejected for accuracy claims. Exploratory gains depended on numerically unstable float32 finite-difference optimization and did not reproduce through the Windows runtime. Its files/results are retained as negative evidence.
- **Calibrated Course v3:** current deterministic research candidate. Residual-v1 weights stay frozen; train-derived linear yaw/speed residual calibration is followed by sign-aware turn detection and guarded course closure. Formal `SL_04` validation gives **ATE `0.179216 m`, heading RMSE `3.57882 deg`**, versus course-v1 `0.218728 m / 4.53390 deg`. The formal v3 config SHA-256 is `30d75e3afad8328e2433c563823a70640586ad98447f8d675f76cdf42de06478`. Historical test data was not evaluated; C3D is never used at inference; non-SL validation conditions are exact no-ops.

V3 recognizes the eight-major-turn complete-course sign pattern `[-,+,-,-,+,-,+,+]`. If learned calibration exceeds its training envelope, runtime must skip that learned correction rather than clip/force it. Protocol closure and all correction magnitudes must remain visible to reviewers.

### Unified Physics-Informed Hybrid Estimator v1

Combines Method 1 (3D camber kinematics + neural slip residuals), Method 2 (multi-scale shock feature extraction), Method 3 (biomechanical phase classification with dynamic ZUPT/ZARU InEKF), Method 4 (RTS backward smoother), and Method 5 (dynamic skid-steer ICR adjustment).
Registered in `BiWheel3D/registry/models.json` as `biwheel3d:unified_hybrid_v1` with professional label `Unified Physics-Informed Hybrid Estimator [PINN-InEKF + ICR + RTS]`. Fully integrated into the Windows desktop application runtime and GUI model selector. Macro ATE on held-out test split is 0.486 m (-41% vs classical baseline), heading RMSE is 13.8 deg (-52%).

## Optional chair-center IMU (`C`)

The acquisition source stack now supports `L`, `R` and optional `C` / `0x43`.

- Role: chair-frame sensor, not a wheel hub.
- Mounting contract: **+Z down toward the floor**.
- X/Y: physical board axes, intentionally not relabeled as forward/lateral yet.
- XIAO center build: yellow RGB identity using red+green; 500 ms identity blink and 150 ms heartbeat every 1 s while recording.
- M5 center build: static yellow identity bar plus large yellow `C` glyph blinking at normal cadence and heartbeat cadence during recording.
- Windows: connect, synchronize, record, v2 journal, live/saved preview and export support C.
- Flutter: connect, synchronize, record, schema-v5 metadata, preview, CSV/XLSX/ZIP support C; `center_raw.csv` is emitted only when C exists.
- Legacy L/R training/model data remains L/R-only. Regression tests require exact `(T,5,12)`/12-channel input equality with and without arbitrarily large C samples.

Windows `.waj` v1 remains L/R-compatible. A session containing C uses journal v2 and side codes `L=0`, `R=1`, `C=2`, preventing C from silently decoding as R.

## Current verification

Latest verification:

- Project publication/hygiene audit: **448 candidate files, 0 errors**.
- Flutter: **715/715 tests passed**; `flutter analyze` reports no issues.
- Windows normal GUI/acquisition suite: **182/182 passed** (0 failures; daemon offline root cause diagnosed and resolved: IPC message limit raised from 64 KB to 16 MiB allowing large session catalogs, EOF probe handling on reachability check, and subprocess PYTHONPATH isolation).
- BiWheel3D research suite: **251/251 passed** (including 11 hybrid estimator tests and 6 PINN-EKF tests).
- Ruff on changed Windows scope: passed.
- M5 firmware host tests: **147/147 passed**; center firmware 1.8.1 build succeeds (15.4% RAM / 62.3% flash), SHA-256 `5b70f6f94a0d6b02b6146e7366fb1e181f170685727c56fc270cb0914742d6f7`.
- XIAO firmware host tests: **19/19 passed**; center firmware 1.8.1 build succeeds (10.8% RAM / 18.2% flash), SHA-256 `060a57553889593d4ee1271c13a50696fc5127ce4eef3cac7566047afce0ccc0`.
- Windows 1.8.1 packaging completed successfully: `WheelAthleteSetup-1.8.1.exe` SHA-256 `e3e523feb5e9ed6f1a937ea8a797c92e7035eff362513181f81c6e01d9e52b33`; `WheelAthlete-1.8.1-portable.zip` SHA-256 `1d9d31c4984ab064b2a36e1b96d816bfb8bdbf71f242bc476218d846c4eb59f7`. Packaged `_internal/VERSION` reads `1.8.1`.
- BiWheel3D research repository test suite: **251/251 passed** (including `test_export_bundle.py` with course v3 tests, `test_pinn_ekf.py` with 6 unit tests, and `test_hybrid_estimator.py` with 11 unit tests).
- BiWheel3D Git index reconciled: initial scaffold committed on `archive/legacy-scaffold`, current research suite committed on `main`; raw/derived recordings ignored from commits; zero files deleted from disk.
- BiWheel3D Research Paper Map created: `BiWheel3D/docs/RESEARCH_PAPER_MAP.md` mapping all scripts, configs, datasets, and models to publication sections.
- 5 Recommended Methodologies documented: `BiWheel3D/docs/METHODS_COMPARISON.md` (PINN-EKF with 3D camber kinematics, Contrastive IMU MAE foundation model, Biomechanical Invariant EKF, LLM Semantic Parsing + Factor Graph Optimization, and Wavelet ICR).
- Method 1 (PINN-EKF) implemented: `BiWheel3D/biwheel3d/pinn_ekf.py` provides 3D camber kinematics, differential slip estimation, and gyro bias tracking.
- Unified Hybrid Estimator implemented: `BiWheel3D/biwheel3d/hybrid_estimator.py` combining 15-deg camber kinematics, multi-scale shock/envelope extraction, biomechanical phase detection (Pause/Push/Coast/Turn/Straight) with dynamic ZUPT/ZARU InEKF, full 8D Rauch-Tung-Striebel (RTS) backward state trajectory smoother, Factor Graph pose optimizer, and frequency-decoupled skid-steer ICR scaling.
- Benchmark across all 21 accepted C3D + dual-IMU trials executed: `.project/reports/hybrid_methods_benchmark.md` and `scripts/evaluate_hybrid_methods.py`. Macro ATE reduced from 1.097 m (Classical) to 0.904 m (Unified Hybrid) overall, test split ATE reduced from 0.820 m to 0.486 m (-41%), and 10x5 sprint ATE reduced from 1.640 m to 0.595 m (-64%, heading error from 48.9° to 9.7°).
- Model export & contract alignment verified: `BiWheel3D/scripts/export_wheelathlete_bundle.py` updated to provide `model.onnx` alongside `network.onnx` for Flutter, aligned with `docs/model_analysis/CONTRACT.md` schema v1.

The XIAO center board was previously flashed in this continuation with the green `C` identity and the user visually confirmed the green LED. After the version was bumped to 1.8.1, the board was no longer connected (only COM1 was present), so the **1.8.1 artifact has not yet been re-flashed/read back** and the +Z-down static-gravity bench acceptance is still pending. No Android/iOS installation/device acceptance has been performed.

## Dataset/reference state

`BiWheel3D/data/datasets/` is the canonical non-destructive catalog. It records 30 named 3DRoom C3D+IMU pairs (21 accepted by existing gates, nine excluded), 19 name-matched 2026-09-05 IMU/Qualisys recordings whose dynamic C3Ds have no point trajectories, 56 2026-09-01 IMU-only recordings without a declared C3D mapping, and 10 C3D-only leftovers.

All 19 audited dynamic Sep-5 C3Ds have `POINT.USED=0`; generated `L_WC_EST/R_WC_EST` pseudo C3Ds are visualization/manual-QTM aids only and are explicitly prohibited as training/scoring ground truth.

## Open gates

1. Before using C in a model, physically flash/identify the center board only with explicit authorization, verify the declared +Z-down orientation with static gravity, verify actual ranges/scales/build identity and measure L/R/C clock/loss behavior.
2. Obtain valid moving optical reference mapped to all relevant acquisition clocks.
3. Capture new grouped L/R/C + C3D sessions with fixed center mounting, days/remounts/athletes as feasible, and reserve an untouched final group.
4. Train/evaluate a center-aware model (or Method 1 PINN-EKF / Method 3 InEKF) against the frozen L/R baseline and accepted reference protocol.
5. Freeze coach acceptance criteria before opening the final group.

Until those gates are met, keep all model defaults unchanged and describe Slalom closure/calibration as experimental constrained analysis.
