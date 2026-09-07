# WheelAthlete current status

Updated: 2026-09-08. Branch: `feature/dual-imu-coaching-analysis`.

**Stage: experimental offline coaching analysis.** This feature branch does not change stable version, model calibration, firmware or BLE protocol metadata. It is not a new release.

| Phase | Status | Delivered scope / remaining gate |
|---|---|---|
| P0 | Complete | Repository ownership, original-state preservation and baseline checks |
| P1 | Local evaluation complete | Corrected timing/QA; independent physical-reference acceptance blocked |
| P2 | Local analytical diagnostics complete | Frozen comparisons and optional physics correction; no selected model |
| P3 | Blocked by reference data | No winner, final-test consumption or third-sensor decision |
| P4 | Source complete | Shared original-time, finite/null kinematics, quality and statistics contract |
| P5 | Source complete | Windows exact cursor/window review, supported speed/yaw and full-resolution export |
| P6 | Existing-model source workflow complete | Mobile M4 review/export; accepted-classical port and device acceptance pending |
| P7 | Protocol/readiness prepared | New paired optical/IMU capture and coach sign-off pending |

## Application capabilities

Windows retains the frozen classical XY+yaw recipe. It exposes its signed speed and unwrapped yaw/rate, with supported derivatives and explicit warnings. Mobile retains the original XY-only M4 ONNX model, running locally without a PC server. Mobile chair yaw/rate, signed forward speed and signed longitudinal acceleration remain unavailable; XY-derived speed magnitude is labeled separately.

Both source interfaces support original-index time/window selection and create-only full-session CSV plus JSON metadata exports. Short gaps are flagged, large unsupported gaps fail, and selecting a window never restarts the pose or estimator.

## Verification

Fresh source verification after organization and hardening passed **148 Windows GUI/acquisition tests**, **705 Flutter tests**, and **198 tests in the unchanged separate research repository**. Flutter analyzer reports **No issues found**. The six new repository-hygiene tests and the shared update-manifest test also pass. Exact exit codes, timings and log hashes are in `reports/branch-validation.json`; detailed logs stay local-only.

This branch additionally rejects mixed mobile timestamp domains and hidden sequence gaps, aligns Python metadata validation with Dart, and moves long mobile export serialization/hashing off the UI isolate. The 8,000-point export regression retains the complete CSV and correct selected-window metadata.

The branch is ready for the explicitly requested normal push. The final remote SHA/ref checks and any GitHub Actions state are recorded in the local publication receipt; source tests alone do not imply hosted CI completion.

Eleven shared analytical cases are public fixtures, not athlete ground truth. The previous read-only smoke prepared 56 journals; one journal received full inference/export. This is not 56 accuracy trials.

## Open acceptance gates

No independent moving wheel-marker reference mapped to both IMU clocks, accepted improved estimator, physical Android/iOS run, or athlete/coach sign-off has been added. P1 coverage remains 21/30, and difficult full-trajectory P2 failures remain unresolved. See `phases/P3.md` and `phases/P7.md` before claiming accuracy or changing defaults.
