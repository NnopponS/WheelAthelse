# WheelAthlete current status

Updated: 2026-09-08. Branch: `feature/dual-imu-coaching-analysis`.

**Stage: experimental offline coaching analysis.** This feature branch does not change stable version, model calibration, firmware or BLE protocol metadata. It is not a new release.

| Phase | Status | Delivered scope / remaining gate |
|---|---|---|
| P0 | Complete | Repository ownership, original-state preservation and baseline checks |
| P1 | Local evaluation complete | Corrected timing/QA; independent physical-reference acceptance blocked |
| P2 | Local analytical diagnostics complete | Frozen comparisons and optional physics correction; no selected model |
| P3 | Blocked for promotion; experimental PyTorch v1 available | Validation-selected residual BiGRU is reviewable locally, but no independent final/reference evidence exists |
| P4 | Source complete | Shared original-time, finite/null kinematics, quality and statistics contract |
| P5 | Source complete + research review | Windows can explicitly select PyTorch residual v1 and open trusted `BiWheel3D/data/*.npz` with optional C3D overlay |
| P6 | Existing-model source workflow complete | Mobile M4 review/export; accepted-classical port and device acceptance pending |
| P7 | Protocol/readiness prepared | New paired optical/IMU capture and coach sign-off pending |

## Application capabilities

Windows retains the frozen classical XY+yaw recipe as the first/default model. The source app additionally exposes **Experimental PyTorch Residual v1** as an explicit local choice when PyTorch is installed; the checkpoint is not production current_best. The MODEL page can open a trusted processed `.npz` inside `BiWheel3D/data` read-only and overlay its C3D path when true GT is present. Full-cache overlay metrics are diagnostics, not the support-masked model-selection score. Mobile retains the original XY-only M4 ONNX model, running locally without a PC server. Mobile chair yaw/rate, signed forward speed and signed longitudinal acceleration remain unavailable; XY-derived speed magnitude is labeled separately.

Both source interfaces support original-index time/window selection and create-only full-session CSV plus JSON metadata exports. Short gaps are flagged, large unsupported gaps fail, and selecting a window never restarts the pose or estimator.

## Verification

The latest PyTorch/data integration pass passed **152 Windows GUI/acquisition tests** in the full Windows runner, **16 focused model/MODEL-page tests**, and **205 tests** in the separate BiWheel3D research repository. Ruff passes on the changed Windows and research files. The prior mobile maintenance result remains **705 Flutter tests** with **No issues found** from Flutter analysis; mobile was not changed by this PyTorch integration. Exact new Windows logs are under `.project/local/verification/20260908T070138_902948Z_windows/`; research results remain local because `BiWheel3D/` is a separate repository.

This branch additionally rejects mixed mobile timestamp domains and hidden sequence gaps, aligns Python metadata validation with Dart, and moves long mobile export serialization/hashing off the UI isolate. The 8,000-point export regression retains the complete CSV and correct selected-window metadata.

The latest published feature tip is `0b09b7c8e7c7995d0000232656008ecbb8d9b47d`. Hosted CI on that tip exposed two portability defects rather than model failures: Windows temporary directories could be represented through an 8.3 alias, and verification depended on fixture/license files that were present locally but excluded from the published tree. The current repair uses same-file comparison on Windows, a tracked synthetic cross-platform feature fixture with provenance, and the exact BiWheel3D MIT attribution already present in the separate research repository and vendored Windows runtime. The full local source suite passes with these repairs. Hosted CI must be rechecked after publication before it is called green.

Eleven shared analytical cases are public fixtures, not athlete ground truth. The previous read-only smoke prepared 56 journals; one journal received full inference/export. This is not 56 accuracy trials.

## Research dataset catalog and Qualisys status

`BiWheel3D/data/datasets/` is now the non-destructive canonical catalog. Raw files stay in their original locations. It currently records 30 named 3DRoom C3D+IMU pairs (21 accepted, nine excluded by existing P1 gates), 19 name-matched 2026-09-05 IMU/Qualisys recordings whose dynamic C3Ds contain no point trajectories, 56 2026-09-01 IMU-only recordings without a declared C3D mapping, and 10 C3D-only leftovers.

For the 2026-09-05 set, all 19 dynamic archived C3Ds have `POINT.USED=0` and point arrays shaped `(4, 0, frames)`. There is therefore nothing optical to relabel. `data/derived/pseudo_markers_2026-09-05/` contains 19 clearly labeled `L_WC_EST/R_WC_EST` model-derived C3Ds only as visualization/manual-QTM aids; every sidecar sets `do_not_train=true` and `do_not_score_as_c3d_gt=true`. Legacy C3D confirms the handedness clue: AR consistently has the left hub as the short inner path with positive yaw; CR has the right hub as the short inner path with negative yaw.

## Open acceptance gates

No independent moving wheel-marker reference mapped to both IMU clocks, accepted improved estimator, physical Android/iOS run, or athlete/coach sign-off has been added. P1 coverage remains 21/30, and difficult full-trajectory P2 failures remain unresolved. See `phases/P3.md` and `phases/P7.md` before claiming accuracy or changing defaults.

## Hourly maintenance status

The publication audit now checks the full candidate tree, including unchanged committed files in a clean checkout. Uppercase text suffixes no longer bypass the credential-pattern check. Eight Git-snapshot regression methods protect committed artifacts, staged content and unstaged repairs; the expanded 14-test suite failed six assertions before the fix and passes after it. This is a bounded publication guard, not proof that every possible secret format is detected.

The local Windows task `WheelAthlete-Hourly-Verification` is configured hourly from 04:00 Asia/Bangkok on 2026-09-08. It runs `scripts/run_verification.py --suite all --timeout 300`, writes ignored evidence, skips overlapping task instances and has a 40-minute execution limit. The PC must be awake, the task owner logged in and AC power available; it does not wake the computer. A missed trigger can run when conditions allow.

A separate ChatGPT engineering continuation is now scheduled in addition to the Windows verification task. It is instructed to use `@lnwjud` when that connector is available and authorized, preserve the feature-branch/publication boundaries, run verification before publication, and stop at physical-data/device/coach authorization gates. Repository state cannot guarantee which ChatGPT model or connector availability a future scheduled run receives, so this must not be described as guaranteed GPT-6 Astra Pro routing. See `history/scheduled-agent.md` for the engineering chronology.
