# Current engineering handoff

Updated: 2026-09-08. Current task owner: the user-authorized project continuation.

## Read order

Read `.project/STATUS.md`, `.project/architecture.md`, `.project/decisions.md`, and the relevant file in `.project/phases/`. The active roadmap is `.project/plans/two-hub-motion-analysis.md`. Public API behavior is in `docs/model_analysis/CONTRACT.md`.

## Branch and publication scope

Use `feature/dual-imu-coaching-analysis` in the application's existing GitHub repository. Preserve `main` and `release/main-v1.8.0`; do not merge, retag, force-push, rename the repository or publish update artifacts. Branch naming is independent of the unchanged stable application/firmware version files.

`BiWheel3D/` is a separate local repository with a different owner's origin, an unborn main and pre-existing staged/untracked work. Do not stage, reset or publish it as a side effect of committing this application. Its current working sources and data remain on this PC. The app's minimal attributed runtime and synthetic fixtures are already self-contained.

The pre-existing `.github/workflows/release.yml` dependency edit is retained locally but excluded from this feature commit. The new non-publishing verification workflow is separate. Verified source checks are recorded in `reports/branch-validation.json`. The exact final commit, push result, protected-ref comparison and hosted CI state are recorded locally in `.project/local/branch-handoff-2026-09-08/publication.json` after the push. Do not call a queued CI run passed.

## Reproduce software verification

From the repository root, run:

```text
python scripts/verify_project.py
python scripts/run_verification.py --suite windows
python scripts/run_verification.py --suite mobile
```

The runner never installs packages, flashes devices or publishes artifacts. It fails on missing tools/checks. Use the existing application requirements and Flutter lockfile to prepare another machine. The optional research suite requires the separate working repository and is not a prerequisite for using either application.

## Next substantive work

Obtain synchronized raw IMU plus valid moving wheel-marker optical references, retaining sample ranges/mounting and clock evidence. Freeze intact participant/day/session/remount groups and an untouched final group. Reopen P3 only when those inputs satisfy the predeclared gates. Port the selected classical estimator to mobile only after acceptance, using declared Python/Dart prediction fixtures. Run installed-device and coach acceptance separately from source tests/builds.

The current mobile model cannot acquire chair yaw merely through a display or schema change. Do not infer yaw from path tangent, retune on historical final data, silently rescale old recordings, or weaken QA to improve coverage. Do not mistake a successful build or saved affine map for physical accuracy.

## Housekeeping and recovery

Use one STATUS and one HANDOFF, and one conclusion per phase. Keep temporary work under `.project/local/`. The old trackers, duplicated final reports, prior evidence and scripts were moved to `.project/local/legacy/`; their byte hashes and a verified ZIP are retained. They are historical evidence, not active instructions. Nothing in the original staged research tree was discarded.

## Published implementation

The published feature tip before the current repair is `0b09b7c8e7c7995d0000232656008ecbb8d9b47d`. Its hosted source verification failed on a Windows path-alias assertion plus files excluded from the published tree, while the same source passed locally. The current staged repair makes those tests self-contained and platform-safe without changing model defaults. Local verification passes 148 Windows tests, 705 Flutter tests, 16 tooling tests, the update-manifest test and Flutter analysis. Do not claim hosted CI success until the post-push checks complete. Main/release references and the separate research index remain unchanged.

## Hourly verification and future engineering runs

Use `history/scheduled-agent.md` as the single chronological agent-run log and `reports/scheduled-agent-validation.json` for the latest sanitized maintenance evidence. Append meaningful engineering runs; do not manufacture an hourly code commit or new report document. Machine-specific scheduler receipts, regression logs and publication receipts for this run stay in `.project/local/scheduled-agent/2026-09-08T0322/`.

The Windows task `WheelAthlete-Hourly-Verification` runs all source verification checks once per hour from 04:00 Asia/Bangkok, starting 2026-09-08. The registered action uses an absolute Python interpreter, absolute runner path and explicit project working directory. It needs an awake PC, a logged-in task owner and AC power. No overlapping scheduled instance, wake timer, elevated run level, signing, release, model promotion, automatic commit or automatic push is configured. Logs and summary JSON are written under `.project/local/verification/`. Use Task Scheduler to inspect, pause or change this specific job; do not create a duplicate.

A separate ChatGPT engineering continuation is now scheduled and is distinct from the deterministic Windows verification task. Each run must re-read the canonical project records, use `@lnwjud` only when available and authorized, preserve dirty/staged work and protected branches, verify before publication, and stop rather than fabricate evidence at physical/data/device/coach gates. The repository cannot guarantee a specific hosted model or future connector availability; do not describe the schedule as guaranteed GPT-6 Astra Pro routing.

For a future authorized engineering run, re-read AGENTS and the current canonical documents, inspect actual Git/source state and the latest complete verification summary, check for concurrent work, then choose the highest-value implementable issue. Independent reference and grouped-capture evidence remain the gate for model selection; continue other useful regression-protected work rather than weakening accuracy gates.
