# Scheduled engineering run log

This is the canonical chronological record for user-authorized engineering runs. Update STATUS and HANDOFF for current state. Recurring verification logs stay local and do not create source commits. A scheduled verification script is not an autonomous AI agent.

## 2026-09-08 - Publication snapshot hardening and hourly verification

Timestamp: 2026-09-08T03:31:10+07:00 (Asia/Bangkok).
Branch: `feature/dual-imu-coaching-analysis`.
Commit: based on `0961e7f5765f068abfdcb1ca86301555bd1a57a5`; the final committing SHA and push readback are recorded in the local publication receipt after publication.
PR: use the current branch's review PR; the publication receipt records the observed PR number/status.

### Objective and recovered state

Continue from actual repository state without replacing the prior model work. AGENTS, canonical project documents, P0/P1 and P3 conclusions, Git status, branch history and remote refs were inspected. The independent-reference acceptance gate remains blocked. The existing release-workflow edit was preserved; the separate research repository is not part of this change.

### Hypothesis, reproduction and changes

A clean checkout has no changed-file diff. Therefore the previous changed-files-only publication check could incorrectly pass an already committed credential-pattern fixture or prohibited research artifact. Synthetic temporary Git repositories reproduced this failure. An unstaged local repair could also hide an unsafe indexed snapshot, and uppercase text suffixes bypassed the text-pattern check.

The checker now audits every candidate file in the selected working-tree or index snapshot, retains the changed-file count as diagnostic metadata and reports the full publication-file count. Text suffix matching is case-insensitive. Eight new regression methods exercise committed content, empty prohibited artifacts, staged versus unstaged state, untracked artifacts and staged deletion. No real credentials or athlete recordings were introduced.

### Measured before and after

The existing source baseline passed 148 Windows tests, 705 Flutter tests, six tooling tests and one manifest test; Flutter analysis was clean. With the same new 14-test tooling suite, the old checker produced six assertion failures; the fixed checker passes all 14. The post-change all-suite run also passed 148 Windows tests, 705 Flutter tests and the manifest test, with no Flutter analyzer issues. Full source auditing passed on 430 candidate files before adding these documentation records. The sanitized report retains exact exit codes, durations and log hashes.

Decision: **keep** the bounded correctness fix. No model configuration changed and no trajectory accuracy improvement is claimed. The previous separate-research test result is historical, not a new run.

### Scheduling result

`WheelAthlete-Hourly-Verification` is registered hourly from 04:00 Asia/Bangkok on 2026-09-08. Its exact executable, arguments, working directory and PT1H trigger were read back from Windows. Incorrect quoting from the initial task-registration helper was caught before any execution and repaired through typed Windows Task Scheduler actions. It runs at limited privilege, ignores overlapping scheduled instances, has a 40-minute limit, does not wake the PC and requires the task owner logged in and AC power. A missed run can start when conditions allow.

The scheduled task runs source checks and records local evidence only. A manual run through Windows Task Scheduler completed with LastTaskResult 0; its corresponding full-suite summary has all six checks passing. The task returned to Ready with the next trigger at 04:00 Asia/Bangkok. The maintenance report retains that execution summary and log hashes. **The GPT-6 Astra Pro-only autonomous engineering schedule is not configured.** No other model was substituted and no future AI edits are promised.

### Known issues and next action

No new synchronized moving wheel-marker optical reference, grouped untouched final capture, physical device acceptance or coach sign-off exists. Keep the estimator defaults and original data unchanged. Resolve an eligible scheduler/model route before describing the hourly job as autonomous engineering. During the next authorized engineering run, inspect actual results and work on the highest-priority verifiable issue; continue to preserve unrelated changes and historical branches.

### Evidence locations

Sanitized measurements: `../reports/scheduled-agent-validation.json`.
Private raw logs and final publication receipt: `.project/local/scheduled-agent/2026-09-08T0322/`.
Post-change full-suite run: `.project/local/verification/20260907T202701_607464Z_all/`.

## 2026-09-08 - Hosted CI portability repair and scheduled engineering continuation

Timestamp: 2026-09-08T05:08:00+07:00 (Asia/Bangkok).
Branch: `feature/dual-imu-coaching-analysis`.
Starting tip: `0b09b7c8e7c7995d0000232656008ecbb8d9b47d`.
PR: #4, base `release/main-v1.8.0`.

### Recovered failure

The latest hosted verification was inspected before editing. Windows had two failures: a temporary directory string could differ only because GitHub's Windows runner exposed the same directory through an 8.3 alias, and a cross-platform feature test referenced `applications/wheelathlete_mobile/test/fixtures/biwheel3d_features.json`, which was not present in the published tree. Flutter analysis/tests failed because `pubspec.yaml` referenced `assets/models/BIWHEEL3D_LICENSE.txt`, which was likewise absent from the published tree.

The missing license was checked read-only against both `BiWheel3D/LICENSE` and the existing vendored Windows runtime attribution; all three texts match the same MIT license and 2026 BiWheel3D contributor notice. No separate-research file was modified or staged.

### Repair and verification

The repair switches the Windows folder assertion to filesystem identity, moves the shared feature reference to tracked `docs/model_analysis/fixtures/features_v1.json` with explicit synthetic provenance, keeps a deterministic generator in `scripts/generate_feature_fixture.py`, tracks the required mobile model attribution without opening the broad private-research ignore rule, and extends publication regression coverage. Production model weights/defaults are unchanged.

A fresh local all-suite run at `.project/local/verification/20260907T210452_181140Z_all/` passed: 148 Windows tests, 705 Flutter tests, 16 tooling tests, one update-manifest test, and Flutter analyzer with no issues. Working-tree and staged publication audits also passed across 435 candidate files before this documentation update. Hosted CI remains a separate gate until the repaired commit is pushed and its checks finish.

### Scheduling state

The existing Windows hourly task remains verification-only. A separate ChatGPT engineering continuation is now scheduled to re-enter the project, use `@lnwjud` when available/authorized, continue only implementable feature-branch work, and stop at evidence or authorization gates. The repository does not establish a guaranteed hosted model or connector availability for future runs, so no GPT-6 Astra Pro-only claim is made.

### Remaining gates

Independent synchronized moving wheel-marker optical reference, grouped untouched final capture, physical Android/iOS acceptance and athlete/coach sign-off are still absent. P3 model selection and any mobile classical-model promotion remain blocked by those evidence gates.

## 2026-09-08 - Slalom-v3 and optional center-IMU source continuation

Timestamp: 2026-09-08 evening (Asia/Bangkok).
Branch: `feature/dual-imu-coaching-analysis`.
Starting/published tip during the run: `be2e4725576775249796d376ef0e64cceb7aa04e`. The current working-tree changes described below were **not committed or pushed** in this continuation.

### Slalom research conclusion

Full-course GT-vs-model review showed that the long Slalom failure is driven by cumulative local yaw-rate waveform/timing error, not only final net yaw. Course-v1 confirmed that known return-to-start constraints can make the path much more useful for this fixed protocol, but its near-zero endpoint is constrained rather than independent odometry evidence.

A per-turn v2 optimizer produced attractive exploratory metrics but failed application-runtime reproducibility because float32 finite-difference perturbations fell into numerical noise. V2 is therefore rejected for accuracy claims and retained as negative evidence.

A deterministic calibrated-course v3 was then frozen with residual-v1 weights unchanged, small train-derived linear yaw/speed residual calibration, sign-aware turn detection and guarded fixed-course closure. Formal `SL_04` validation improved from raw residual-v1 `0.790368 m / 21.6689 deg` ATE/heading RMSE and course-v1 `0.218728 m / 4.53390 deg` to **v3 `0.179216 m / 3.57882 deg`**. Historical test remained unevaluated; non-SL formal validation was exact no-op; C3D was never an inference input.

### Optional center instrumentation

The user authorized source support for a third chair-center IMU C (`0x43`) with +Z pointing down toward the floor. X/Y remain physical board axes pending physical mapping.

The implementation extended both firmware targets, Windows and Flutter through role parsing, synchronization, recording, preview and export. L/R-only Windows journals remain v1; C sessions use journal v2 with explicit C side code. Mobile storage/export is additive and emits `center_raw.csv` only when C exists. Existing model preprocessing explicitly remains L/R-only and regression tests prove C does not alter the legacy 12-channel input.

XIAO center uses yellow RGB identity/heartbeat. M5 center uses a yellow identity bar plus blinking yellow `C` glyph without violating the display anti-flicker rule.

### Measured software/build verification

- project audit: 444 candidate files, 0 errors,
- mobile: 715/715 tests, analyzer clean,
- Windows bounded three-IMU suite: 167/167,
- focused center/journal/sequence/stress: 13/13,
- normal Windows suite: 171 passed / 1 failed from an unrelated Slalom-v3 test using the wrong `applications/BiWheel3D` path,
- M5 host firmware: 147/147,
- XIAO host firmware: 18/18,
- M5 center compile: success, 15.4% RAM / 62.3% flash,
- XIAO center compile: success, 10.8% RAM / 18.2% flash.

No board was flashed, no app was installed, no current model was promoted and the nested `BiWheel3D` Git status matched its pre-center snapshot exactly.

### Next action

Fix the Slalom-v3 test root path and rerun the complete Windows suite. After explicit physical-flash authorization, bench-verify C role/ranges/+Z-down gravity and three-stream clock/loss behavior, then collect new synchronized L/R/C + valid moving optical reference before training a center-aware estimator.

Local raw evidence: `.project/local/three-imu-2026-09-08/`. Current canonical conclusions: `../STATUS.md`, `../HANDOFF.md`, `../phases/P3.md` through `P7.md`.
