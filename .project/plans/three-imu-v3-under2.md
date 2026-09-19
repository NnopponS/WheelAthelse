# Three-IMU odometry v3 — retrospective <2% milestone

Updated: 2026-09-15.

## Status

Experimental/offline only. Production WheelAthlete remains on the frozen L/R trajectory model. C3D is used for development labels and retrospective evaluation only; `estimate_trajectory_v3()` consumes L/R/C IMU plus optional declared protocol metadata, never C3D.

## V3 method

V3 keeps the v2 synchronized L/R/C backbone, center-heavy yaw fusion, stationarity anchors and declared same-heading course closure. For short low-yaw propulsion it adds a development-trained speed residual using five IMU-only features: wheel speed, speed×|speed|, wheel acceleration, center forward acceleration and wheel jerk.

The residual coefficients are fit on September-9 `OSPT` + `7.5-MSPT` development recordings. The low-disagreement yaw mode uses the maximum center-vs-wheel disagreement observed in that September-9 development set (`10.312842863 deg/s`) multiplied by a fixed 15% hardware/remount margin, giving `11.859769293 deg/s`. This derivation is explicit in `biwheel3d/three_imu_odometry_v3.py` and regression-tested.

Short low-yaw selection is IMU-only: estimated path 4–12 m and integrated absolute yaw <1 rad. Runtime behavior is nevertheless **protocol-aware** because declared maneuver metadata can activate same-heading closure. C3D correlation lag remains evaluation-only and is not a runtime input; the retrospective headline below therefore must not be described as generic runtime inference.

## Reproduced retrospective evaluation

Command: `uv run python -m scripts.evaluate_three_imu_v3`

Development/calibration date: 2026-09-09. Retrospective evaluation date: 2026-09-11. The September-11 data has been inspected during development, so this is engineering evidence, not untouched final validation.

| Metric | Reproduced result |
|---|---:|
| Evaluation trials | 28 |
| Strict ATE/path <2% AND endpoint/path <2% | **28 / 28** |
| Macro ATE/path | **0.658%** |
| Macro endpoint/path | **0.813%** |
| Worst ATE/path | **1.697%** |
| Worst endpoint/path | **1.814%** |
| Macro heading RMSE | **1.936 deg** |

Critical short trials:
- `20260911_os_01`: ATE **0.643%**, endpoint **0.267%**, heading RMSE **1.114 deg**.
- `20260911_sp_01`: ATE **1.377%**, endpoint **1.523%**, heading RMSE **1.112 deg**.

The strict worst endpoint is `20260911_slup_14` at **1.814%**; the strict worst ATE is `20260911_pvcr_01` at **1.697%**.

Regression verification after making the threshold derivation explicit: `13 passed` across `tests/test_three_imu_odometry_v3.py` and `tests/test_three_imu_odometry_v2.py`.

## Promotion boundary

Do not call v3 production-ready. The <2% milestone is retrospective and some design choices were made after examining September-11 behavior. Before promotion, freeze v3 and its calibration rules, collect a future untouched participant/day/remount group, perform any calibration without looking at that group's C3D, then evaluate once with the same strict per-trial metrics. Production defaults remain unchanged until that gate passes.
