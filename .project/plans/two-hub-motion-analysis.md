# Two-hub motion analysis roadmap

Maintained plan, updated 2026-09-08. Current progress is in `../STATUS.md`, not in historical planning prompts. The user has now authorized source completion, project-state organization and a new feature-branch push. This does not authorize raw-data publication, a stable release, device flashing or unverified model promotion.

Goal: relative planar wheelchair-center trajectory with original-time speed, acceleration, yaw and window review. Preserve the inherited 0.30 m radius / 0.52 m hub spacing / zero-camber assumptions and calibration. Full body-marker motion and unvalidated vertical/ramp reconstruction are outside demonstrated scope. Two independent hub clocks must not be made 'synchronized' by independently zeroing their epochs.

## 4. Phase order and decision gates

Execute in order. P4's output contract may be designed while waiting for new data, but do not promote a model to the apps until P3's evidence is available. If data blocks model acceptance, ship honest diagnostics and offline exploration without claiming validated accuracy.

### P0 — Re-establish the exact starting point

**Own:** `.project/STATUS.md` and `.project/HANDOFF.md`; no production edits required.

1. Read workspace instructions and current model documents. Inspect both Git states; preserve unrelated modifications and the nested staged/untracked files.
2. Recheck the two source edits above. Rerun the nine focused tests, then the full BiWheel3D suite to identify baseline failures.
3. Record versions of Python, NumPy, SciPy, pytest and relevant app runtimes. Available at handoff: Python 3.12, NumPy/SciPy/pytest/PySide6/ezc3d/Ruff installed; Flutter/Dart on PATH. Do not assume version equality on another host.
4. Record hashes of touched runtime files, relevant configs, pairing file, input data and outputs in local experiment metadata. Do not commit raw data or secrets.

**Gate:** actual branch/dirty state documented; no silent loss; focused repair verified; baseline failures distinguished from new failures.

### P1 — Repair evaluation trust before optimizing the estimator

**Own:** `BiWheel3D/biwheel3d/sync.py`, relevant existing sync/pipeline tests and a small reproducible evaluation entry point under `scripts/` if needed. Reuse `Trial`, `classical_metrics`, heading helpers and QA; avoid another framework.

1. Audit every `align_streams`/`find_best_lag` caller. Check lag sign, common overlap, timestamps after slicing, window centers and 100→20 Hz binning. Add focused yaw-event/crop checks where they exercise a different failure mode. Check finite samples, monotonic clocks, interior gaps and correlation quality; do not let interpolation manufacture validated evidence.
2. Use `data/processed_sync_corrected_2026-09-07` as the corrected dataset. If regeneration is needed, retain provenance and use a new directory if outputs/configuration differ. Never mix old and corrected `.npz` caches in one evaluation.
3. Inspect wheel-marker labels, units, residual validity, marker spacing, dropout runs, pairing fingerprints and retained motion for each GT trial. Audit raw left/right clock handling as well as IMU↔C3D sync. Two independent board epochs cannot be assumed synchronized merely by zeroing both starts.
4. Build a before/after timing report over matched valid motion intervals. Do not interpret changes due to different crops or exclusions as accuracy gains. Explain new exclusions and count all intended trials in coverage.
5. Freeze calibration/train/validation IDs before experimenting. Keep participant/session/trial groups intact; overlapping windows stay in the same partition. July trial `_05` data is historical regression, not a pristine holdout. Reserve an additional independently captured day/athlete/session for a final locked test. September without usable GT can support input QA, not C3D error claims.
6. Evaluate the unchanged current recipe on corrected data. Report XY ATE RMSE, endpoint error, short-horizon relative pose error, path-length error, heading error and turn timing. Compare the archived result only with its processing version clearly labeled.
7. Correct evaluation bookkeeping if it silently excludes failed/missing predictions, uses test data to select a winner, rotates each short window independently, fits scale from test paths, or uses a single net-yaw/path-length score as proof of trajectory quality.

**Artifacts:** dataset/QA manifest with accepted and rejected IDs; split manifest; reproducible per-trial and aggregate metrics; timing overlay plots; explicit coverage and limitations.

**Gate:** known offsets pass; no hidden test selection; every score has a valid reference and common timestamp convention. If trustworthy GT is insufficient, record the capture request and continue only work independent of accuracy claims.

### P2 — Diagnose and improve the two-hub estimator

**Own:** primarily `BiWheel3D/biwheel3d/yaw_ab.py`, `imu_frame.py`, focused existing tests, calibration/evaluation scripts. Default recipe remains unchanged during candidate experiments.

1. Establish physics baseline: for calibrated forward wheel speeds, `v=(R_L*w_L+R_R*w_R)/2`, `yaw_rate=(R_R*w_R-R_L*w_L)/track`. Reuse existing differential odometry. Verify straight, reverse, one-wheel arc, pivot, stop/start and tight-turn behavior against analytical cases. Distinguish chair center from a driven wheel's trajectory.
2. Validate raw SI conversion against recorded firmware sensor ranges. Existing files contain both LSM6DS3-specific conversion and generic full-scale conversions; verify provenance before changing any constants. Check sign conventions, rotated mounting axes, gyro bias, clipping, dropped samples, wheel radius and effective geometry.
3. On calibration/training only, examine heading without the legacy delay after corrected sync. Keep a small preregistered candidate set: existing recipe; zero-delay same scales; physically justified calibrated scales/mean-speed model if evidence warrants. Do not search arbitrary maneuver-specific knobs or retune on every trial.
4. Plot left projected yaw, right projected yaw, wheel-difference yaw, accelerations, speed and C3D yaw rate together. Examine errors by wheel phase, straight/turn/braking/pivot, and time since start. Distinguish initial mounting error, accumulated drift and latency.
5. Estimate bias only in genuinely stationary windows using both gyro and accelerometer stability, with insufficient-stillness reported. For sports camber, first quantify sensitivity and mark assumptions. Do not silently override the user's inherited zero-camber configuration. If camber must be modeled later, derive and test the wheel-spin/yaw coupling with explicit axis conventions.
6. Only implement a further estimator if a measured residual supports it. Candidate directions: per-wheel mounting calibration; gravity direction propagated with wheel rotation and corrected cautiously; bias-aware constrained filtering; robust use of redundant left/right yaw. A simple unconditional chassis/differential blend already regressed historical results. Reuse functions; avoid speculative EKF/ML architecture.
7. If considering ML residual correction, first show that a calibrated physics baseline has a consistent learnable error and sufficient independent labels. Require train-only normalization, grouped validation, uncertainty/QC behavior, and a fair baseline. No restoration of the removed TCN/BiLSTM stack by default.

**Gate:** candidate is physically coherent, input-validated, reproducible, and beats baseline on validation without unacceptable regressions in individual maneuvers. Synthetic success alone cannot select a real-world model.

### P3 — Select once and make the hardware decision

**Own:** evaluation outputs, recipe metadata, `BiWheel3D/docs/XY_YAW.md`, `docs/ROADMAP.md`, `CHANGELOG.md` only when results justify updates.

1. Select the candidate using validation only, freeze parameters and source hashes, then run the final test once. If the only available evaluation set is repeatedly used July data, label the outcome **provisional regression improvement**, not generalization or final promotion.
2. Report every trial, maneuver and session. Include paired differences and uncertainty at independent trial/session level, not thousands of correlated windows. With very few groups, disclose limited inference rather than presenting a confident bootstrap percentage.
3. Use initial-reference alignment only for the primary result. Any full-trajectory rigid alignment must be a separately named diagnostic. Never fit scale, time warp or per-window rotation to the scored reference.
4. Inspect full trajectories and time-local traces; include unwrapped heading error (preserves missed full turns) and wrapped angle error if useful. Preserve signed forward speed separately from nonnegative speed magnitude. Compare acceleration only with a stated derivative/filter bandwidth shared by reference and estimate.
5. Suggested engineering targets below are provisional discussion values, **not achieved results, clinical standards, or user-approved requirements**. Freeze final thresholds with the coach before a new locked test.

| Quantity | Proposed initial acceptance discussion |
|---|---|
| Speed MAE | ≤0.10 m/s |
| Yaw-rate MAE | ≤5 deg/s |
| Longitudinal acceleration MAE | ≤0.30 m/s² using a declared 0.25–0.50 s analysis window |
| Heading RMSE | ≤10 deg; inspect drift and missed complete turns separately |
| Turn-event timing | ≤0.15 s with explicit event definition |
| Path-length relative error | ≤5% for moving tests; no unstable relative score for pivots |
| XY ATE RMSE | Initially ≤0.50 m; show each maneuver separately and discuss tighter requirements for small gate spacing |
| 1 s relative position error | Initially ≤0.15 m; handle insufficient-duration windows explicitly |
| Coverage | ≥90% of intended valid protocol trials; show all exclusions and failures |

6. Keep two hubs if timing/calibration fixes satisfy the agreed coaching requirements across the intended tests. Add a third chassis IMU for a controlled A/B study if remaining errors correlate with slip, braking, hard turns or unstable projected yaw, after clock/mounting checks. Do not conclude that hardware is inadequate from invalid C3D or failed synchronization.
7. If adding a third sensor becomes justified, first obtain user authorization for the expanded hardware work; preserve the two-hub baseline. Compare two vs three sensors on the same synchronized C3D trials. A chassis sensor is not an absolute position reference.

**Gate:** explicit `accepted`, `provisional`, `rejected`, or `blocked_by_reference_data`, with numeric reasons. Only an accepted/provisionally labeled recipe may become an explicitly identified application choice. Do not overwrite `current_best` solely because a historical net turn target looks correct.

### P4 — Define one coaching analysis contract

**Own:** extend existing model result structures; avoid a new service. Windows `tools/pc_gui/model_inference.py`; mobile `lib/model/trajectory_model.dart`; small shared fixtures and documentation.

Represent each model sample with:

| Field | Meaning |
|---|---|
| `time_s` | Window-center time relative to recording start, preserving cropped-overlap offset |
| `x_m`, `y_m` | Chair center in the declared initial frame |
| `signed_speed_mps`, `speed_mps` | Forward/reverse velocity and its magnitude, separately |
| `longitudinal_accel_mps2` | Derivative of signed speed, with declared smoothing/window support |
| `yaw_rad`, `yaw_rate_radps` | Chair orientation and angular velocity; unwrapped yaw preserves spins |
| `lateral_accel_mps2` | Optional model-derived `signed_speed*yaw_rate`, explicitly labeled and invalid during unsupported slip |
| `quality_flags` | Observed gaps, interpolation, clock uncertainty, saturation, model scope, etc.; no invented confidence probabilities |

Include result-level schema/algorithm version, recipe/config hash, chair geometry, time basis, sample rate, calibration identity, filter support/latency, valid coverage and warnings. Avoid redundant per-point metadata.

1. Verify what timestamps the acquisition journals/exports actually contain. Prefer acquisition time mapped through the saved clock model over BLE arrival time or nominal sequence cadence. Preserve old-session loading, but label uncertain legacy timing. Missing trustworthy sync cannot be repaired by relabeling arrival time.
2. Reject malformed/nonfinite data. Explicitly account for duplicate/out-of-order sequences, rollover, clock resets, gaps and mismatched sample rates. Do not interpolate a long outage and show a continuous trusted path. Define small-gap policy and mark affected windows; segment large gaps or fail analysis clearly.
3. Use estimator speed/yaw outputs for the classical recipe; do not reconstruct yaw from XY at a pivot or reverse. For the current XY-only ONNX model, chair yaw is unavailable: return null with a reason. Trajectory tangent is not chair orientation. A zero-length moving path is not proof of zero yaw.
4. Define whether a sample is an interval estimate or a point-center estimate and how integration aligns with it. Do not lose the first/last valid window or restart position/yaw at every display window.
5. Keep a single full-session state/output array; slider and window statistics select from it. Specify derivative edge handling and minimum data support. Avoid presenting a noisy 20 Hz finite difference as a validated acceleration peak.

**Gate:** deterministic analytical fixtures for forward/reverse/pivot/one-wheel arc, onset/offset, gaps and irregular clocks; serialization preserves length, timestamps, units and unavailable fields. Round-trip outputs contain no NaN/Infinity masquerading as values.

### P5 — Windows coaching view and export

**Own:** `applications/wheelathlete_windows/tools/pc_gui/model_inference.py`, `main_window.py::ModelPage`, relevant tests, bundled runtime/recipe only as needed.

1. Preserve all per-window outputs from the estimator. Fix metadata that uses truthy fallback for an applied zero yaw delay: zero must remain zero.
2. Add a native Qt timeline slider and selectable time/window boundaries. Highlight the exact corresponding XY point while retaining the full trajectory. Show speed, longitudinal acceleration, yaw and yaw rate with units; synchronize time-series cursors and window statistics.
3. Preserve equal X/Y scales. Large recordings may decimate display points, but cursor lookup/statistics/export must use all source points. Keyboard access, readable text and non-color-only quality status are required.
4. Export per-sample CSV and a metadata JSON sidecar; include time, units, model/calibration identity, warnings and validity. Never modify the original `.waj` or raw CSV. Select folder/file with existing native dialogs and handle IO errors without data loss.
5. Keep analysis off the UI/acquisition path. Disable conflicting analysis actions, discard stale results if their recording/model selection no longer applies, and verify that chart interaction does not interfere with recording/recovery.
6. Bundled `biwheel3d_runtime` is a copied snapshot with relative imports. Update its provenance and check source/runtime numerical parity, not just matching filenames. The recorded `SOURCE.json` commit is historical; it does not identify the current uncommitted nested files.

**Gate:** real finalized recording can load, analyze, scrub, select a window and export; exports agree with displayed values. Tests cover backend semantics and cursor/export mapping. Check offscreen UI layout and an actual screenshot at normal laptop resolution. No claim of installed-app acceptance from source-only tests.

### P6 — Mobile parity without unsupported yaw

**Own:** `applications/wheelathlete_mobile/lib/model/trajectory_model.dart`, `on_device_trajectory_model.dart`, `state/model_trajectory_providers.dart`, `ui/session_preview_page.dart`, `widgets/trajectory_chart.dart` and focused tests.

1. Make the difference between the current M4 XY model and the selected classical recipe explicit. Do not label the old network as the newly validated estimator or assume its embedded normalization/physics were retrained.
2. Prefer porting the accepted small NumPy classical operations to Dart if practical, using identical Python-generated fixtures. Keep ONNX as a separately labeled optional model if retained. Do not introduce a PC/server dependency into mobile.
3. Carry common times, kinematics and QC through the result. If only XY is available, keep yaw unavailable and label derived speed/acceleration honestly. Never manufacture chair yaw from path direction.
4. Add native Flutter slider/window selection, corresponding path point and readable selected metrics, with the same window/statistic definitions as Windows. Extend existing export paths rather than adding another storage system.
5. Confirm platform inference does not freeze UI, preserves session data, and handles disposed/cancelled analysis. Test performance with long recordings and golden numeric parity fixtures. Realtime BLE ownership remains separate from optional offline inference.

**Gate:** Dart/Python parity for a selected recipe; widget tests for cursor/quality; relevant analyzer/tests pass; Android/iOS runtime acceptance explicitly separated from builds and mocked tests.

### P7 — Capture and end-to-end athlete/coach acceptance

**Own:** documented capture/checklist and evidence reports first; firmware/hardware only for a specifically justified change.

1. Obtain correct optical exports: moving left/right wheel markers with valid residuals, known units/sample rates and a documented map of markers to hubs. Exporting a gait overlay or POINT.USED=0 file does not satisfy this.
2. Capture synchronized raw IMU plus C3D for static start/end, straight acceleration/braking, reverse, both one-wheel arcs, both in-place turns, slalom, 10×5 shuttle and pause/restart. Record protocol definitions; names such as AR/CR/OWC and number of shuttle turns must match what the athlete actually performed. Do not force a presumed 1800° target into calibration.
3. Include multiple trials, days, athletes and remounts as feasible. Log chair/load/radii/track/camber, sensor mounting and firmware ranges, floor/surface, clock diagnostics and all failures. Keep a final day/athlete group untouched.
4. Athlete/coach review: choose a time, locate the corresponding movement, inspect speed/braking/turn metrics, compare repeats, and export the same values. Record whether uncertainty is clear enough for training decisions.
5. Verify separately: software checks, packaged app launch, hardware identity/firmware, dual-board synchronization and loss, GUI/daemon isolation, data recovery/reopen, and actual coaching accuracy. No box is checked by inference from another box.

**Gate:** signed-off scope of measured capability, known failures and two-vs-three-IMU decision with evidence. Without the necessary physical capture, report the software delivery and the remaining experiment separately.

## 5. Research basis

These sources guide hypotheses; their errors are not this project's measured performance.

- [SciPy correlate documentation](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.correlate.html): correlation convention supports the repaired positive/negative-lag slices.
- [Pansiot et al., WISDOM (2011), author manuscript](https://julien.pansiot.org/papers/2011_Pansiot_IOPMST_WISDOM.pdf): wheel-mounted inertial reconstruction under rolling assumptions; camber couples chassis yaw into axle gyro. Use its coordinate conventions carefully.
- [Rupf et al. (2023)](https://pmc.ncbi.nlm.nih.gov/articles/PMC10490421/): wheel-IMU yaw estimation supports investigating projected gyro and mounting alignment; comparison is against a frame IMU, not proof of C3D trajectory accuracy.
- [van der Slikke et al. (2015)](https://research.vu.nl/en/publications/wheel-skid-correction-is-a-prerequisite-to-reliably-measure-wheel): wheel/frame redundancy addresses skid-related error, especially in vigorous motion; an extra sensor is not a universal correction.
- [van Dijk et al. (2022)](https://repository.tudelft.nl/record/uuid:79ebe221-3a00-4b4f-a57c-596f35c022d7): its “2IMU” configuration is one wheel plus frame, not this project's two hubs. Do not transfer its validation figures to this setup.
- [WheelPoser (2024)](https://arxiv.org/abs/2409.08494): body-pose reconstruction is a separate sensing/training task from planar wheelchair odometry.
