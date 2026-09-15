# Three-IMU Pause-Anchored Residual Odometry (3IMU-PARO v1)

Updated: 2026-09-12.

## Purpose

Develop an experimental L/R/C wheelchair trajectory estimator that consumes synchronized raw IMU streams and predicts signed forward speed and chassis yaw rate, then integrates those rates into planar XY + yaw. C3D is training/evaluation reference only and is never an inference input.

Production defaults remain unchanged: the installed WheelAthlete trajectory model remains the frozen L/R classical estimator. This work is retrospective research only.

## Data used in the first prototype

The reorganized canonical three-IMU source is under `BiWheel3D/data/raw/imu3/<date>/{imu,c3d}/<condition>/trial_XX.*`.

The first prototype used trial-level `retrospective_development` records from the September 9/11 catalog for AR, CW, SL, SLUP, PVAR and PVCR. September 9 was used as development/training and September 11 as held-out retrospective evaluation. The final run loaded 35 development trials and 13 held-out retrospective trials.

UP remains especially important. The catalog contains 7 `10X5UP` and 20 `SLUP` recordings. All current 10X5UP optical pairs fail the >=90% trial visibility gate, while 14 SLUP pairs are retrospective-development eligible. Older September-5 segmentation shows pause-before-U-turn medians near 2.45 s for 10x5up and 2.0 s for slup, so pauses are useful stationarity/bias anchors but must not be hard-coded as exactly 1-3 seconds.

## Prototype method

1. Reconstruct L/R/C shared time from device clocks and saved host monotonic timestamps.
2. Resample all 18 raw IMU channels to 20 Hz for the prototype sequence model.
3. Build C3D wheelchair-center position from the midpoint of the explicit left/right wheel markers and heading from the optical axle.
4. Estimate one constant IMU/C3D lag per trial by cross-correlation of center raw `gx` against optical yaw rate.
5. Fit a train-only linear three-sensor physics baseline from `[L gz, R gz, C gx, bias]` to `[signed speed, yaw rate]`.
6. Feed normalized 18-channel L/R/C IMU sequences to a causal 1-layer GRU (hidden size 32) that predicts a bounded residual over the physics rates.
7. Apply a conservative pause anchor when both baseline speed and yaw rate remain near zero for roughly 0.5 s; anchored samples set predicted speed/yaw rate to zero.
8. Integrate predicted rates with midpoint SE(2) integration to obtain XY and unwrapped yaw.

This prototype is intentionally smaller than the full proposed architecture. It does not yet include learned pause/turn heads, uncertainty, turn-integral loss, explicit bias-state filtering, or grouped validation selection.

## Evaluation bug found and corrected

An initial experimental run allowed invalid optical marker frames to enter `np.unwrap`, which contaminated heading/yaw metrics. That run is not accepted evidence. The final preprocessing computes heading only from valid marker frames, unwraps that valid sequence, interpolates the continuous reference for target construction, and keeps the original marker-validity mask for scoring support.

## Final held-out retrospective result

Across 13 September-11 held-out retrospective trials:

| Metric | 3-IMU linear baseline | 3IMU-PARO prototype | Change |
|---|---:|---:|---:|
| Macro ATE RMSE | 1.778 m | 1.223 m | -31.2% |
| Macro endpoint error | 2.923 m | 2.222 m | -24.0% |
| Macro heading RMSE | 50.42 deg | 31.43 deg | -37.7% |
| Macro yaw-rate MAE | 7.64 deg/s | 7.33 deg/s | -3.9% |

The held-out set is dominated by SLUP. For 11 held-out SLUP trials specifically, mean ATE improved about 2.089 -> 1.431 m, endpoint about 3.438 -> 2.605 m, and heading RMSE about 57.46 -> 35.45 deg. Not every trial improved: several SLUP trials regressed, so this is not yet a promotion-ready estimator.

The result artifact is `BiWheel3D/results/three_imu_paro_v1/best_heldout_comparison.png`; raw metrics are in `BiWheel3D/results/three_imu_paro_v1/metrics.json`, and the experimental checkpoint is `prototype.pt`.

## Interpretation

The experiment supports the user's hypothesis that pause-rich U-turn trials can help stabilize long-horizon trajectory estimation. The largest gains are on SLUP, suggesting the center gyro plus pause anchoring carries useful heading information that the wheel-only/differential estimate misses. However, the evidence is retrospective and condition-skewed, and several held-out trials still regress.

This prototype must remain `experimental_not_promoted`. It does not satisfy the existing center-yaw production gate or the requirement for a future untouched participant/day/remount group.

## Next iteration

- Convert the self-contained prototype into versioned reusable source modules and tests only after preserving the current BiWheel3D dirty tree.
- Replace threshold-only pause anchoring with a learned stationarity probability plus explicit gyro-bias ZARU update.
- Add turn/U-turn event supervision and turn-integral/waveform losses.
- Use grouped development/validation by participant/day/remount rather than selecting on the same retrospective groups.
- Add uncertainty and center-vs-wheel yaw disagreement as QC/slip features.
- Report condition-balanced macro metrics so SLUP cannot dominate selection.
- Keep excluded 10X5UP C3D out of supervised trajectory loss unless local optical support is independently proven valid.
- After freezing one candidate, evaluate once on a future untouched L/R/C + C3D participant/day/remount group before any production promotion.
