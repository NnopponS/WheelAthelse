# WheelAthlete current status

Updated: 2026-09-25

## Release line

- Product: **WheelAthlete 1.8.4**
- Primary branch: `main`
- Public release branch target: `release/main-v1.8.4`
- Windows application: `1.8.4`
- M5StickC Plus2 firmware: `1.8.2`
- XIAO nRF52840 Sense firmware: `1.8.2`
- BLE protocol: `1.8.0`
- Flutter source: `1.8.3+13`, maintenance only and excluded from the current release publication

## v1.8.4 rebuild state

- Windows source is based on the exact `v1.8.3` tag commit `9bc62677f2cf5555d00616ec8270fee8b7869368`.
- M5/XIAO source matches the supplied firmware snapshot; firmware identity remains `1.8.2` and BLE protocol remains `1.8.0`.
- Restored only the orbitable 3D trajectory view and equal-distance dynamic XYZ scaling from the later candidate. The default model and XY-only behavior remain unchanged.
- Added managed WheelAthlete CSV import/date assignment/export, asynchronous progress/error status for Results and Model trajectory exports, per-recording BLE counter deltas, sanitized Windows/Bluetooth diagnostics, graceful daemon shutdown, and opt-in scoped cleanup.
- A close request during Results or Model CSV export is blocked with a wait message; trajectory and imported-CSV destinations appear only after the full write completes.
- The candidate includes a source-only v1.8.4 tag-push workflow; it rejects manual dispatch and tag-deletion events, skips Windows and Android artifact jobs, and publishes no binary assets. The previous `v1.8.4` tag pointed to `eab67ca23edfa078cd866008e2e1f1c81648b08c`, whose workflow did not have this guard, so replace the tag and release branch from the final tested commit before release.
- No mobile source/assets, `BiWheel3D/`, or locked paper-test cohort changes are included.
- Cross-computer BLE testing is not available in this run. Firmware queue drops on the reference firmware remain an unresolved acceptance item; no transport fix is claimed.

## v1.8.4 verification

- Windows suite: **243 passed, 6 skipped**.
- M5 host tests: **147 passed**; XIAO host tests: **19 passed**.
- PlatformIO builds: M5 left/right/center and XIAO left/right/center all **succeeded** against the snapshot source.
- Python compile check, working-tree project hygiene, staged project hygiene, and Git diff checks: **passed**. Commit/ref publication remains pending.
- The Inno Setup compiler is not installed in this environment, so the `.iss` installer was covered by Windows packaging-layout tests but could not be compiled here.
- These results are software checks only; they do not establish BLE acceptance across computers or physical hardware acceptance.

## v1.8.3 release history

The v1.8.3 repairs, acquisition countdown audio timing overhaul, QC metadata visibility, earlier dual-IMU coaching-analysis work, and Windows trust-hardening work remain in `main` history. The trust-hardening merge was normal/non-force and conflict-free. No mobile application source or `BiWheel3D` file was introduced by that release.

All obsolete remote development/archive/release branches were verified as ancestors of the integrated `main` before removal. The intended final GitHub branch surface is only:

- `main`
- `release/main-v1.8.4` (target after verification)

Old visible GitHub Release entries were removed so the Releases page contains only `v1.8.3`. Historical version tags are retained for traceability. The `v1.8.3` release/tag is source-only and is finalized at the exact consolidated release commit; no unsigned Windows or mobile assets belong to it.

The separate local `BiWheel3D/` repository remains outside the root repository publication boundary.

## Windows application

The maintained Windows application uses a PySide6 GUI plus a separate acquisition daemon. The daemon owns BLE, sequence accounting, synchronization, append-only `.waj` recording, QC and recovery; the GUI owns operator workflow, preview, Results, diagnostics, export and optional offline model review.

Implemented 1.8.3 release features include:

- streamlined minimal navigation sidebar ("WheelAthlete") with clean uncluttered page headers;
- persistent Day -> Experiment -> Trial Results selection and deduplicated batch export with C sample counts;
- Diagnostics page with three-sensor telemetry monitoring for Left (L), Right (R), and Chair Center (C);
- Model page with intuitive Kinematic Trajectory (XY + Yaw) baseline and user library binding to `Documents/WheelAthlete`;
- explicit daemon shutdown and active-journal finalization before upgrade/uninstall;
- preservation of recordings and custom/seeded models through installer lifecycle operations;
- high-resolution `perf_counter_ns()` timing for Windows acquisition and scheduled-start calculations;
- concrete sensor fault reporting instead of an unexplained generic `CHECK` state;
- contained versioned portable model bundles with compatibility/path validation;
- support for `ALLOW_UNSIGNED_RELEASE=true` community build mode setting `is_signed=false` while embedding available models;
- installed-app update support through a verified GitHub Release manifest when a trusted signed release exists;
- fail-closed Windows release signing that verifies packaged EXE/DLL/PYD/PowerShell components, the generated uninstaller and the installer;
- window icon configuration using official assets and cleaned typography across Analysis timeline;
- a release workflow that can publish only from the exact version tag and re-checks `public_release_ready=true` before GitHub Release upload;
- synchronized recording countdown audio and visual cue streamlining (clear 5-4-3-2-1 timing display without calibration hold message, in-memory PCM WAV audio queue worker with pre-warming that guarantees audible 1 s interval beeps at 700 Hz on every count without Windows audio DAC sleep truncation, and a 500 ms long start tone at 1200 Hz);
- final QC result card displaying recording quality, duration, Experiment topic, and Trial number, with preserved metadata across acquisition daemon IPC, LiveController, and DemoController.

The v1.8.3 baseline verification passed **215/215** active Windows unit and GUI tests, **4/4** Windows packaging-layout tests, **19/19** XIAO host tests, **147/147** M5 host tests, release-manifest unit tests, Python compile checks, project hygiene, staged publication hygiene, and Git diff checks. The v1.8.4 verification results are recorded below after this rebuild completes.

## Firmware and optional center sensor

The supported sensor roles are `L`, `R`, and optional chair-center `C` (`0x43`). The center mounting contract is **+Z pointing down toward the floor**; center X/Y remain physical board axes until a forward/lateral mapping is measured.

XIAO center identity is **green** and must not hide retry/error indication. M5 center retains its yellow display identity. Existing trajectory models still consume L/R only; C is acquisition/storage instrumentation unless a separately validated center-aware model is introduced.

The specific XIAO center board was flashed/read back as firmware 1.8.2 and role C. A post-flash run reached 1,780.865 s before board removal; the last 1,750 s snapshot contained 179,290 samples with zero observed sequence, malformed, host-queue, firmware-queue, notification or FIFO loss/fault counters. This is strong partial runtime evidence, not final physical acceptance, because the final STOP/QC/reopen/export sequence and simultaneous L/R/C bench run were not completed.

## Model and research boundary

The installed Windows default remains the frozen classical L/R XY+yaw model. Experimental residual/Slalom/hybrid research paths do not silently replace the default. `BiWheel3D/` remains a separate local research repository and is not staged, merged or published as part of WheelAthlete 1.8.3.

## Release and trust status

The v1.8.4 GitHub Release is intended to remain **source-only**. Public Windows binaries and `latest.json` remain blocked until a trusted RSA Code Signing identity with Code Signing EKU, the exact expected publisher subject and a timestamp service are available. Local unsigned packages are development artifacts only and must not be presented as solving SmartScreen/Application Control trust.

The **historical v1.8.3** unsigned-local packaging run generated a 63,571,038-byte installer (SHA-256 `BE5C2B8769E3DC87116A7CD491F54B780984BE2D12D03418A807635EE899F5C4`) and a 92,775,101-byte portable ZIP (SHA-256 `E662D1D9A43660966FB02121F1C4763AAAA8A20050B913820F4E2649B36497A7`). Its signing report correctly recorded `public_release_ready=false`; those artifacts do not verify v1.8.4 and must not be uploaded.

When signing is configured, the release build must return `public_release_ready=true` before Windows installer/portable/update assets are published.

## Publication boundary

This v1.8.3 consolidation publishes **no new mobile source changes and no mobile binaries**. Existing Flutter history/source is retained as maintenance material, but no APK/AAB/IPA or mobile update offer belongs to v1.8.3.

Private recordings, generated packages, local evidence, signing material, absolute user paths and the separate `BiWheel3D/` repository remain outside the source commit. Local evidence belongs under ignored `.project/local/`.

## Source/repository acceptance

Repository-side v1.8.4 publication is complete only when the exact tested commit is visible through `main`, `release/main-v1.8.4`, and source-only tag/Release `v1.8.4`. Existing `main` history must be preserved without force-pushing. Until then, v1.8.4 is a candidate, not a published release.

## Deferred external acceptance

Two items remain outside what source consolidation can prove:

- trusted public Windows code signing;
- final physical L/R/C hardware acceptance after the boards return.

Do not describe either item as complete until measured evidence exists.
