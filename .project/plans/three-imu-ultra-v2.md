# Three-IMU trajectory pipeline v2

Updated: 2026-09-12.

## Objective

Estimate wheelchair planar trajectory from raw XIAO L/R/C IMU data as closely as possible to optical C3D while keeping C3D out of runtime inference. The production WheelAthlete L/R model is unchanged; this work remains offline research and is not promoted.

## Accepted pipeline

The v2 research pipeline is implemented in `BiWheel3D/biwheel3d/three_imu_odometry_v2.py`.

1. Reconstruct a shared L/R/C clock from unwrapped device time and robust host-clock fits.
2. Resample native L/R/C signals onto one 100 Hz time base.
3. Detect true stationarity only when both wheel hubs and the chair-center gyro are quiet.
4. Use pause intervals as zero-rate anchors and interpolate gyro bias between pauses.
5. Estimate the center sensor's gravity axis from its accelerometer and project the full center gyro vector onto that axis. This replaces the mount-sensitive raw-`gx`-only yaw measurement while preserving the measured September mounting evidence.
6. Fit the global wheel-speed, center-yaw and differential-wheel-yaw gains using only September-9 development C3D support.
7. Fuse yaw heavily toward the center sensor. The development-selected configuration uses center weight `0.95` in straight motion and `0.97` in turns, with a small disagreement bonus. Wheel-differential yaw remains a secondary measurement/QC signal because its development fit is much noisier than center yaw.
8. Integrate signed speed and fused yaw rate using midpoint SE(2) integration.
9. For protocols explicitly known to finish with the same heading they started with (`SL`, `SLUP`, `10X5`, `10X5UP`), apply an IMU-only same-heading closure constraint. It estimates a small constant yaw-rate bias over moving support so wrapped final heading closes to the declared protocol heading. This is not applied to arbitrary/free-driving trials.
10. Support an optional one-time per-chair speed calibration from raw IMU only. `estimate_pause_bounded_speed_gain()` uses center acceleration, gravity magnitude, wheel-speed changes and pause-bounded zero-velocity intervals. It does not use C3D. For the September-11 `P-31e06f7d` chair, 20 pause-bounded segments from `10X5UP_07` produced a scale factor of `1.023278` relative to the global speed gain; that factor is reused for the same chair's other trials.

## Why the center IMU now helps much more

The first 3IMU-PARO prototype reduced yaw-rate error but still produced large loops because a small yaw-rate bias integrated over 100+ seconds into a large heading error. V2 attacks the integration error directly:

- full 3-axis center gyro projected onto measured gravity removes mount-tilt sensitivity;
- pause bias anchors suppress gyro zero drift;
- center-heavy fusion avoids reintroducing wheel-slip error through differential wheel yaw;
- same-heading course closure removes the remaining low-frequency yaw bias only when the protocol actually guarantees that constraint;
- per-chair speed calibration handles effective wheel-radius differences instead of forcing one global meters-per-gyro-count gain onto every athlete chair.

## Retrospective evaluation protocol

Global calibration and fusion selection use 35 high-QA September-9 development trials. Evaluation uses 28 paired September-11 trials with strict per-frame optical validity masks, including recordings that fail the old whole-trial 90% visibility gate. Invalid optical frames are never treated as ground truth.

The September-11 set has already been inspected repeatedly during development. The per-chair speed-calibration strategy was also developed after diagnosing its SP failure. Therefore these numbers are retrospective engineering evidence, not an untouched final-test claim.

### Final v2 retrospective result

With gravity-axis center yaw, center-heavy fusion, protocol heading closure where declared, and the IMU-only chair calibration for `P-31e06f7d`:

| Metric | Result |
|---|---:|
| Evaluation trials | 28 |
| Macro ATE / reference path | **0.796%** |
| Macro endpoint / reference path | **1.050%** |
| Macro heading RMSE | **1.90 deg** |
| Worst ATE / path | **3.48%** |
| Worst endpoint / path | **4.89%** |
| Trials with ATE < 5% | **28 / 28** |
| Trials with endpoint < 5% | **28 / 28** |

Key repaired cases:

- `20260911_slup_06`: final ATE about `0.55%`, endpoint about `0.60%`, heading RMSE about `0.8 deg`.
- `20260911_slup_13`: endpoint reduced from about `5.88%` before course heading closure to about `1.52%`; heading RMSE about `2.0 deg`.
- `20260911_sp_01`: heading was already correct; the IMU-only chair speed calibration reduced endpoint from about `5.50%` to about `3.44%` and ATE to about `2.36%`.
- `20260911_os_01` is the current worst endpoint case at about `4.89%` and ATE about `3.48%`.

Final reproducible metrics and plots are written under `BiWheel3D/results/three_imu_v2_final/` by `python -m scripts.plot_three_imu_v2_final`.

## Rejected experiments

The following were explicitly tested and must remain disabled unless new evidence justifies them:

- **All low-visibility September-9 pairs in global calibration:** more data did not improve held-out behavior and worsened important turn cases.
- **Quadratic/nonlinear global speed curve:** slightly improved point fit on development data but worsened `SP_01` and the held-out worst endpoint.
- **Pause-bounded 180-degree U-turn snapping:** overconstrained real turns and badly degraded some `10X5UP` trajectories. `pause_turn_anchor_enabled` remains `False`.
- **Center-minus-wheel straight-motion yaw bias observer:** wheel differential yaw is not a stable low-frequency reference across the remount; this caused large held-out heading regressions. `straight_bias_observer_enabled` remains `False`.
- **Blind global +1% speed multiplier:** can make the retrospective test pass but is not development-selected and is therefore rejected in favor of chair-specific IMU calibration.

## Acceptance and next evidence

The `<5%` target is achieved on all 28 currently evaluated September-11 retrospective trials under the declared pipeline. This does **not** authorize production promotion yet.

Before promotion:

1. Freeze this v2 method and calibration procedure.
2. Collect a future untouched participant/day/remount group with L/R/C and C3D.
3. Perform any chair calibration using IMU-only data and a predefined procedure before looking at that trial's C3D.
4. Evaluate once with the same metrics and condition-balanced reporting.
5. Require no hidden C3D use, no trial-specific hand tuning, and no meaningful regression in straight, turn, pause and slip regimes.

Production WheelAthlete remains unchanged until that gate passes.
