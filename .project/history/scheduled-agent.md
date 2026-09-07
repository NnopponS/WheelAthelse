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
