# Current engineering handoff

## Active v1.8.2 session handoff (2026-09-10)

- Working branch: `codex/v1.8.2-repairs`; preserve the existing dirty work.
- User authorizes implementing the repair plan, updating main without force,
  and publishing v1.8.2 only after release gates. This supersedes historical
  main/publication restrictions below for this scoped task.
- User requires detailed STATUS/HANDOFF updates after each stage and session.
- Maintained plan: `.project/plans/v1.8.2-repair-release.md`; follow its stage
  gates and session handoff contract.
- Backup: `.project/local/v1.8.2/preexisting/` contains original changed source
  and binary patches. Do not publish this private backup.
- Results: separate day-only/all-system selection; portable model bundles;
  Flutter source retained but unavailable for download in this release.
- Hardware: the user no longer has a XIAO board available. Do not attempt another
  flash or claim final physical acceptance. Resume C Python-app QC and L/R/C only
  after hardware is reconnected and re-enumerated.
- Trust: no signing account; do not disable Application Control or purchase keys.
- Current hardware: COM20, Seeed VID:PID `2886:8045`, serial
  `B303B939495B5F33`, BLE `WheelAthlete-XIAO-C`, reported firmware 1.8.0. The
  unflashed 1,823 s C-only run completed with 184,410 host samples and zero host
  sequence/queue/malformed faults; firmware counters ended at zero queue drops,
  transport failures, FIFO faults, and FIFO loss. STOP acknowledged. The prior
  red/check symptom did not reproduce. The five-point clock fit is invalid-looking
  (107,943.7 ppm, zero RTT) and must be diagnosed before a justified center flash.
  Evidence: ignored `.project/local/v1.8.2/xiao_c_live_30m.json`.
- Completed focused source work: Stage 2 Results checks 10/10; Stage 3 explicit
  daemon shutdown plus installer helper source; Stage 4 Authenticode signing and
  Windows-only release gating source; Stage 5 concise names and portable bundle
  validation checks 31/31. Installed lifecycle, full suites, and release build are
  not yet accepted.
- Completed repair path: traced the host clock and LED/check state, reproduced
  both causes in focused tests, built and flashed only center C, and re-enumerated
  the same USB/BLE identity.
- Center repair completed: the same serial was flashed with the tested 1.8.2
  center artifact and returned on COM20. BLE read-back confirms firmware 1.8.2,
  role C and the expected ranges/rate. `firmware.zip` SHA-256 is
  `53ea4cd01b0741e59d6ac84bdf9225337211b623ab6a76cd862456f45e1ea230`.
- Confirmed timing root cause: Python `monotonic_ns` is backed by 15.625 ms
  GetTickCount64 on this host; the acquisition and GUI clock domain now uses
  QueryPerformanceCounter through `perf_counter_ns`. The post-fix physical probe
  has nonzero RTTs and a 36-observation 43.19 ppm fit. Firmware active-retry LED
  state now uses consecutive failures while keeping cumulative counters, and GUI
  `CHECK` reports the specific fault.
- Post-flash runtime evidence: the C-only run reached 1,780.865 s before the board
  was removed. The final 1,750 s snapshot has 179,290 samples and zero observed
  sequence, malformed, host-queue, firmware-queue, notification, or FIFO faults.
  The missing final STOP and Python-app record/QC/reopen/export keep hardware
  acceptance open. Evidence: ignored
  `.project/local/v1.8.2/xiao_c_post_flash_30m.json`.
- Version/docs stage complete: root `VERSION`, Windows package, M5/XIAO firmware
  are 1.8.2; retained Flutter source is 1.8.2+12 and clearly unavailable. Main and
  Thai READMEs are Windows-first, release/packaging/model-bundle instructions and
  changelog are updated, and prepared release notes keep signing, installed
  lifecycle, and hardware gates explicit.
- Current verification: project hygiene passes with 454 publication candidates
  and zero errors; Python dependency audit has no known vulnerabilities; XIAO
  tests are 19/19 and left/right builds succeed; M5 tests are 147/147 and all
  three role builds succeed. The first Windows run passed 193 checks but found two
  demo-date failures at local midnight; explicit local-day demo anchors fix them,
  the 4 focused checks pass, and the full Windows rerun passes 195/195.
- User steering for v1.8.2: skip Flutter now. The stopped mobile run had a clean
  analyzer and 714 passing tests plus one stale version assertion; release
  constants/tests are aligned to 1.8.2+12 and the 2 focused checks pass. Do not
  make mobile a release gate or offer a mobile download/update.
- Windows artifact/lifecycle gate passed. Final installer SHA-256 is
  `eb3b7da422c25c02a4758ade8881e33728d3132c13e1b9f092005e9c3dbaf9a4`;
  portable ZIP SHA-256 is
  `5b0263c21a47fe8bf477a5c0417c94c1ab4acc8633199b809f2c0174712634ca`.
  Real install, GUI launch, daemon shutdown, live-daemon upgrade, uninstall,
  delayed cleanup audit, and reinstall passed. Uninstall removed binaries,
  registration, shortcuts, and processes while preserving 330 session files and
  12 model files byte-identically.
- Installer preservation root cause fixed: seeded model files now use
  `onlyifdoesntexist` plus `uninsneveruninstall`. The first test build had already
  changed one pre-existing recipe before this was found; the old bytes were not
  recoverable, so the current source recipe was restored. All original 350 paths
  exist and only that recipe differs from the initial hash. Keep this disclosed.
- The final 1.8.2 build is installed at `Documents\WheelAthlete`; no app or daemon
  process is left running. Raw evidence is under ignored
  `.project/local/v1.8.2/`.
- Final post-installer checks pass: project hygiene has 455 candidates and zero
  errors; Windows passes 195/195 in 59.02 s. Workspace-bounded Flutter/PyInstaller
  build trees, firmware `.pio` trees, and 14 cache directories were removed;
  release packages and local evidence were retained. Private path/key scans are
  clean and `BiWheel3D` remains clean on its own `main`.
- The reviewed 111-path source consolidation is staged. Staged hygiene passes
  with 455 candidates and zero errors; ignored user data, packages, and local
  evidence are absent from the index.
- Immediate next action: commit, merge to `main` without force, rerun
  release-critical checks, and push source. Do not publish binaries or tag
  `v1.8.2` because all three artifacts are unsigned.

Updated: 2026-09-08. This file is the continuation checklist after publishing the Windows/firmware 1.8.1 release branch while preserving unrelated dirty work.

## Read order

1. `.project/STATUS.md`
2. `.project/decisions.md`
3. `.project/architecture.md`
4. `.project/plans/motion-analysis-roadmap.md`
5. the phase file relevant to the task
6. `docs/model_analysis/CONTRACT.md` and/or `docs/ble-protocol.md` when changing public semantics

## Git and ownership state

Root branch: `release/main-v1.8.1`.

Release commit `30e99d83ae9d0da072721306f65501a35024813a` is published to `origin/release/main-v1.8.1`. Preserve `main` and `release/main-v1.8.0`; do not merge or force-push them as a side effect. A local annotated `v1.8.1` tag exists, but tag publication failed only because the local Git client lost DNS resolution to GitHub after the release branch had already pushed successfully.

Windows installer/portable artifacts were built locally under `applications/wheelathlete_windows/release/`. Do not confuse the local build artifacts with a GitHub Release asset upload.

The pre-existing `.github/workflows/release.yml` edit is unrelated dirty work; preserve it and exclude it from feature commits unless explicitly owned.

`BiWheel3D/` is a separate local repository. Its Git index is cleanly reconciled (`archive/legacy-scaffold` preserves the initial scaffold, and `main` contains the motion analysis and course calibration suite; raw/derived recordings are gitignored and completely preserved on disk). Do not reset, clean, stage-all or publish it as a side effect of root work.

## Current implementation truth

### Existing/default estimators

- Windows first/default: frozen classical XY+yaw recipe.
- Mobile default: existing M4 XY-only ONNX.
- Experimental Windows: PyTorch Residual v1.
- Experimental Slalom: course-v1 and calibrated-course-v3 research paths. V2 is retained only as rejected numerical-instability evidence.
- No model currently consumes center IMU C.

Formal v3 `SL_04` validation: raw v1 `0.790368 m / 21.6689 deg`, course-v1 `0.218728 m / 4.53390 deg`, calibrated-v3 `0.179216 m / 3.57882 deg` ATE/heading RMSE. Endpoint closure is protocol-constrained, not independent odometry evidence. Historical test remains unopened for v3 and C3D is never an inference input.

### Optional center IMU

Role is `C` / `0x43`, mounted with **+Z down toward the floor**. X/Y remain board axes. Source support is complete across XIAO/M5 firmware, Windows acquisition/UI/storage and Flutter acquisition/storage/export. L/R-only data remains compatible; sessions with C use Windows journal v2. Current L/R feature tensors explicitly ignore C.

XIAO center identifies itself with a **green** blink/heartbeat and remains role `C` / `0x43`; M5 center retains its `C` identity behavior. The XIAO was flashed with the green-identity build earlier and the user visually confirmed green. The final 1.8.1 XIAO artifact was rebuilt afterward but could not be re-flashed/read back because the board was disconnected.

## Verification truth

Current working-tree checks:

- project audit: **446 files, 0 errors**
- mobile: **715/715 + analyzer clean**
- M5 host firmware: **147/147**; center firmware 1.8.1 build success
- XIAO host firmware: **19/19**; center firmware 1.8.1 build success
- Windows normal GUI/acquisition suite: **182/182 passed** (including daemon offline fix: IPC message size limit increased to 16 MiB for large session directories, graceful EOF handling on reachability probe, and subprocess PYTHONPATH isolation)
- Windows 3-IMU bounded suite: **167/167 passed**
- focused Windows center/journal/sequence/stress: **13/13 passed**
- BiWheel3D research test suite: **251/251 passed** (including `test_export_bundle.py` with course v3 tests, `test_pinn_ekf.py` with 6 unit tests, and `test_hybrid_estimator.py` with 11 unit tests)
- BiWheel3D git index: cleanly reconciled (`archive/legacy-scaffold` for scaffold, `main` for research suite; raw/derived recordings ignored from commits; zero files deleted from disk)
- BiWheel3D research map: `BiWheel3D/docs/RESEARCH_PAPER_MAP.md` created
- 5 Recommended Methods: `BiWheel3D/docs/METHODS_COMPARISON.md` created
- Method 1 (PINN-EKF) implemented: `BiWheel3D/biwheel3d/pinn_ekf.py` with 3D camber kinematics, differential slip estimation, and gyro bias tracking
- Unified Hybrid Estimator implemented: `BiWheel3D/biwheel3d/hybrid_estimator.py` combining 15-deg camber kinematics, multi-scale shock/envelope extraction, biomechanical phase detection (Pause/Push/Coast/Turn/Straight) with dynamic ZUPT/ZARU InEKF, full 8D Rauch-Tung-Striebel (RTS) backward state trajectory smoother, Factor Graph pose optimizer, and frequency-decoupled skid-steer ICR scaling
- Windows Python GUI integration: Registered `biwheel3d:unified_hybrid_v1` in `BiWheel3D/registry/models.json` and wired `model_inference.py` to auto-discover, validate runtime dependencies, and run planar inference with `align_first_travel_xy(xyz, None)`.
- Professional Model Naming standardized across GUI dropdowns and registry:
  * `BiWheel3D Classical Kinematic Baseline (XY + Yaw) [v1]`
  * `Deep Residual BiGRU Estimator [C3D-Supervised v1] (Experimental PyTorch)`
  * `Slalom Constrained BiGRU [Loop Closure v1] (Experimental PyTorch)`
  * `Slalom Constrained BiGRU [Calibrated v3] (Experimental PyTorch)`
  * `Unified Physics-Informed Hybrid Estimator [PINN-InEKF + ICR + RTS]`
  * `BiWheel3D Spatial TCN-LSTM [Mobile M4 ONNX]`
- Benchmark across 21 accepted C3D + dual-IMU trials executed: `.project/reports/hybrid_methods_benchmark.md` and `scripts/evaluate_hybrid_methods.py`. Macro ATE reduced from 1.097 m (Classical) to 0.904 m (Unified Hybrid) overall, test split ATE reduced from 0.820 m to 0.486 m (-41%), and 10x5 sprint ATE reduced from 1.640 m to 0.595 m (-64%, heading error from 48.9° to 9.7°)
- Output contract & bundle export: `BiWheel3D/scripts/export_wheelathlete_bundle.py` updated with `model.onnx` export and schema v1 alignment

## Immediate next actions

1. When the XIAO center board is connected again, flash/read back the final 1.8.1 center artifact and run the static +Z-down gravity/range/sample-rate bench acceptance.
2. If a GitHub `v1.8.1` tag/Release page is desired, retry tag publication only after GitHub DNS/network is available; the release branch itself is already remote.
3. Connect L/R/C together and verify identity, sample rate/ranges, sequence/drop/replay, start acknowledgements and shared clock evidence before athlete capture.
4. Capture new synchronized L/R/C + valid moving C3D using P7. Keep participant/day/remount groups intact and reserve a locked final group.
5. In BiWheel3D, train or evaluate Method 1 (PINN-EKF) against the frozen L/R baseline on the accepted C3D pairs.

## Model rules for the next researcher

- Do not train on Sep-5 pseudo markers or score them as C3D ground truth.
- Do not use validation/test GT at inference.
- Do not infer chair yaw from XY tangent, especially during pivots/reverse.
- Do not hide course closure: report raw endpoint/yaw, constrained endpoint/yaw and correction magnitudes separately.
- Do not accept a research optimizer solely from an exploratory notebook/script result. It must reproduce through the application runtime with deterministic numerics. V2 is the explicit negative example.
- Do not use center samples in the legacy 12-channel input by concatenation or silent substitution.
- Do not change radius/track/camber/ranges for old recordings without measured provenance.

## Reproduce software checks

From the root:

```text
python scripts/verify_project.py
python scripts/run_verification.py --suite windows
python scripts/run_verification.py --suite mobile
```

Firmware host tests/builds use each target's existing PlatformIO configuration. Build is not flash. The separate `BiWheel3D` research suite is local research evidence and should be run only when the task owns that repo/state.

## Evidence locations

- Three-IMU current evidence: `.project/local/three-imu-2026-09-08/`
- Current docs refresh: `.project/local/project-docs-refresh-2026-09-08/`
- Verification logs: `.project/local/verification/`
- Slalom/model research outputs: `BiWheel3D/results/` in the separate local repository
- Historical archived project state: `.project/local/legacy/`

Keep STATUS/HANDOFF current instead of creating another final report. Update phase conclusions when a phase's substantive conclusion changes.
