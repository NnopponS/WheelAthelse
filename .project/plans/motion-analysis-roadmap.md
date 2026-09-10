# WheelAthlete motion-analysis roadmap

Maintained plan, updated 2026-09-08.

## Goal

Estimate relative planar wheelchair-center motion with original-time review of trajectory, signed speed, acceleration, yaw/yaw-rate and quality. Preserve an honest separation between:

1. software behavior,
2. constrained protocol-specific analysis,
3. physical synchronization/reference quality,
4. general model accuracy,
5. coach usefulness.

The current stable estimator baseline uses L/R wheel-hub IMUs. Optional chair-center sensor C source support is now complete, but no center-aware estimator has been trained/accepted.

## Non-negotiable baselines

- Current Windows default classical recipe remains unchanged until accepted replacement evidence exists.
- Current mobile M4 XY-only ONNX remains unchanged until a separately accepted port/model exists.
- Preserve inherited geometry/calibration unless measured provenance authorizes a change.
- Never treat independently zeroed clocks as synchronized.
- Never use pseudo markers/model-derived points as ground truth.
- Keep participant/session/remount windows in the same data split.
- A fixed-course closure must be disclosed as a constraint.
- C samples cannot silently enter the legacy 12-channel feature tensor.

## Phase map

### P0 - Re-establish exact starting state: complete

Repository ownership, dirty/staged preservation, environment and baseline commands were recorded. Historical conclusion: `phases/P0-P1.md`.

### P1 - Repair evaluation trust: locally complete, physical gate open

Timing/crop/reference bookkeeping and corrected dataset evaluation were established. Coverage and exclusions remain visible. Independent synchronized moving reference is still required before general accuracy acceptance.

### P2 - Diagnose L/R estimator: complete diagnostics, no production selection

Physics/zero-delay/one-wheel behavior and raw-unit provenance were audited. Supported-subinterval gains and full-cache counterexamples coexist. The correct conclusion remains diagnostic, not model promotion.

### P3 - Select once: currently blocked

P3 remains `blocked_by_reference_data` because there is no independent locked final/reference dataset mapped to sensor clocks.

Current research branches within P3:

- PyTorch Residual v1: useful research estimator; not promoted.
- Slalom Course v1: protocol-constrained fixed-course improvement; not general odometry.
- Slalom Course v2: rejected due numerical/runtime non-reproducibility.
- Slalom Calibrated Course v3: current deterministic Slalom research candidate. Formal `SL_04` validation ATE/heading is `0.179216 m / 3.57882 deg`; historical test remains unopened; non-SL validation is exact no-op.

Before any general selection:
1. obtain valid moving C3D/optical reference,
2. verify clock transform/reference quality,
3. freeze group membership,
4. agree coach thresholds,
5. select once on validation,
6. run locked final once.

### P4 - Shared coaching-analysis contract: source complete

Keep original recording-relative timing, strict gaps/rollover/missingness, finite/null output, correct estimator yaw/speed semantics and one full-session result. Center may be retained as a session stream, but current analysis explicitly takes L/R only.

### P5 - Windows review/export: source complete, research ongoing

Windows must keep the default classical model first and label every experimental alternative. Continue to expose raw-vs-constrained Slalom metadata, C3D overlay only as read-only diagnostics and create-only export. Fix the current Slalom-v3 test root-path defect before calling the full Windows suite green.

### P6 - Mobile review/export: existing-model workflow complete

Mobile now supports L/R/C capture/storage/export but continues to infer with M4 XY-only. A future accepted L/R residual or L/R/C estimator needs a separately versioned Dart/ONNX contract and device-runtime acceptance. Do not infer chair yaw from XY tangent.

### P7 - Physical capture and acceptance: next major evidence phase

The user has authorized optional center instrumentation at source level. Physical flashing remains a separate explicit action.

#### P7A: center bench acceptance

When authorized:
- flash the intended C firmware artifact and record exact SHA/build/target,
- confirm role `C`/name in both apps,
- mount +Z down and verify static gravity sign/magnitude after declared conversion,
- document physical X/Y forward/lateral orientation,
- read/record actual accel/gyro ranges and conversion scale,
- run L/R/C together and capture clock/start/sequence/drop/replay evidence,
- confirm session v2/schema-v5 storage and center export.

A successful bench test does not prove trajectory benefit.

#### P7B: paired L/R/C + optical capture

Capture repeated complete maneuvers with fixed mounting:
- static before/after,
- forward acceleration/coast/braking,
- reverse,
- one-wheel arcs both directions,
- pivots both directions,
- Slalom full course,
- 10x5/shuttle with exact performed protocol,
- pause/restart and hard-turn/braking cases where wheel slip may matter.

Use complete moving reference markers, not empty `POINT.USED=0` exports. Log chair/load/surface/tire/radius/track/camber/remount and all sensor identities/ranges/firmware.

#### P7C: 2-IMU vs 3-IMU model study

Only after P7A/B data passes QA:
- freeze L/R baseline first,
- define center-aware model input/feature schema explicitly,
- train only on development groups,
- select on grouped validation,
- compare L/R vs L/R/C on the same trials,
- inspect whether C helps hard turns/slip/braking without degrading straight/other maneuvers,
- keep an untouched final group.

Do not assume 18 raw channels are automatically better. Center may be most useful as chassis-yaw/slip evidence, calibration context or QC rather than direct concatenation.

## Immediate work queue

1. Fix `test_slalom_course_v3.py` repository-root calculation and rerun the normal full Windows suite.
2. Keep v3 formal result/rejected v2 documentation consistent across app/model records.
3. Keep 3-IMU source regression green and old L/R sessions compatible.
4. With explicit user authorization, flash/bench C and record physical evidence.
5. Collect new valid synchronized L/R/C + C3D.
6. Design/evaluate the center-aware estimator only after data split/reference rules are frozen.
7. Complete Android/iOS installed-device and athlete/coach workflow acceptance separately.

## Acceptance principles

Suggested numerical thresholds from earlier planning remain discussion targets, not achieved standards. Freeze final requirements with the coach before opening the final set. Report every intended trial, exclusion and regression. A bad final result stays in the report and cannot trigger retuning on that same final group.

## Research hypotheses still worth testing

- center/chassis yaw may expose wheel slip or projected wheel-gyro failure during vigorous turns;
- left/right wheel-vs-center yaw disagreement may be a useful QC/slip feature;
- center acceleration may improve braking/acceleration timing if mounting/gravity are calibrated;
- affine clock/reference drift can masquerade as model phase error and must be audited before learning waveform correction;
- Slalom long-horizon error is sensitive to local yaw-rate waveform timing, not merely final net yaw.

These are hypotheses, not measured 3-IMU performance claims.
