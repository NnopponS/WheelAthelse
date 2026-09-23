# WheelAthlete current status

Updated: 2026-09-24

## Current user-requested reliability work: v1.8.4 candidate

The supplied 100 Hz, 17.7-minute three-wheel diagnostic was INVALID. Its largest supported loss source was XIAO R: about 4.8k sequence gaps alongside about 4.8k device sample-queue drops and about 2.0k BLE transport failures; the Windows notification queue and journal did not overflow. This supports device-side BLE-notification backpressure filling the XIAO sample queue, but the exact radio/controller failure reason was not captured. XIAO firmware 1.8.3 fills packets to 12 samples only while queued data backs up and preserves a valid saved L/R/C identity when a shared image is flashed. M5 firmware remains 1.8.2.

The Windows countdown waits for daemon-confirmed recording start, then plays its cue one second later. Model/Results adds an optional local XYZ model view, clearer invalid-session explanations and QC reasons, and keeps selected comparisons visible in 2D. The loss metric is explicitly a conservative lower-bound indicator because host notification and sample counters may overlap or count different units.

Verification passed: 231 Windows tests, 5 skipped; project hygiene; 21 XIAO host tests; left/right/center builds. All three connected boards were flashed and reported firmware 1.8.3 with L/R/C roles intact. The stationary 100 Hz stress capture ran 1080.326 seconds and finalized GOOD: 331,815 journal samples (L 110,601; R 110,608; C 110,606), zero sequence gaps, device queue/FIFO drops, transport failures, host overflows, malformed packets, or QC reasons; writer overflow was zero and queue high-water was 29. This is acquisition/RF stress evidence, not physical motion or model-accuracy evidence. Signed Windows assets remain pending the exact-tag CI signing workflow; no unsigned package will be published.


## Release line

- Product: **WheelAthlete 1.8.3**
- Primary branch: `main`
- Public release branch: `release/main-v1.8.3`
- Windows application: `1.8.3`
- M5StickC Plus2 firmware: `1.8.2`
- XIAO nRF52840 Sense firmware: `1.8.2`
- BLE protocol: `1.8.0`
- Flutter source: `1.8.3+13`, updated with Windows feature parity (Athlete Name, Trial stepper, Windows-parity Final QC card, Windows-format batch CSV export); Android APK & AAB published in v1.8.3 release.

## Consolidation state

The 1.8.3 release repairs, acquisition countdown audio timing overhaul, QC metadata visibility, dual-IMU coaching analysis, Windows trust-hardening, and user-requested feature additions are fully integrated into `main`:
- **Windows Direct In-App Auto-Updater**: Directly downloads verified update installers in-app with progress display (no browser redirect to GitHub Releases), exits the app cleanly, and automatically launches the interactive Inno Setup installer wizard.
- **Mobile App Feature Parity**: Added Athlete Name configuration, editable Trial stepper with auto-increment, Windows-matching post-recording Final QC card, Athlete display and search in Results, and Windows-format CSV export (`{Topic}/{Topic}_Trial{N}_{Athlete}.csv`).
- **Release Publication**: GitHub Actions Release workflow (Run [#35434186521](https://github.com/NnopponS/WheelAthelse/actions/runs/35434186521)) successfully built and published the complete v1.8.3 asset suite (`WheelAthleteSetup-1.8.3.exe`, `WheelAthlete-1.8.3-portable.zip`, `WheelAthlete-1.8.3-android.apk`, `WheelAthlete-1.8.3-android.aab`, and `latest.json`).

All obsolete remote development/archive/release branches were verified as ancestors of the integrated `main` before removal. The intended final GitHub branch surface is only:

- `main`
- `release/main-v1.8.3`

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
- final QC result card displaying recording quality, duration, Experiment topic, and Trial number, with preserved metadata across acquisition daemon IPC, LiveController, and DemoController;
- direct in-app auto-updater: downloads verified installer `.exe` directly in the application (omitting browser redirect to GitHub Releases), exits the app cleanly, and automatically launches the interactive Inno Setup dialog (`silent=False`) on Windows.

Fresh 1.8.3 verification passed **215/215** active Windows unit and GUI tests, **4/4** Windows packaging-layout tests, **19/19** XIAO host tests, **147/147** M5 host tests, release-manifest unit tests, Python compile checks, project hygiene, staged publication hygiene, and Git diff checks.

## Mobile application (Flutter)

Per user request, the Flutter mobile client (`applications/wheelathlete_mobile`) has been brought to feature parity with the Windows research application:
- **Athlete & Experiment Setup**: Added optional Athlete Name text input and clear "Experiment / Topic" dropdown selection in Acquisition.
- **Editable Trial Stepper**: Replaced static trial text with an interactive stepper (`-` / `+`) and numeric input; pressing "New Recording" auto-increments `trialNumber` by 1 while preserving Topic and Athlete Name.
- **Windows-Parity Final QC Card**: Post-recording card displays `Final QC: <GOOD|FAIR|POOR> • <duration> s` with color-coded status, metadata line (`Experiment: <topic> • Trial <trial> • Athlete: <athlete>`), and detailed signal integrity reporting (sequence gaps, drops, FIFO faults, degradation reasons).
- **Results Page Parity**: Displays Athlete Name on session cards, includes Athlete Name in search query filtering, and provides **"Export CSV (Windows)"** generating `{TargetDirectory}/{Topic}/{Topic}_Trial{trialNumber}_{athlete}.csv`.
- **System Share Sheet**: Dedicated Share action for sharing session CSVs across device apps.

## Firmware and optional center sensor

The supported sensor roles are `L`, `R`, and optional chair-center `C` (`0x43`). The center mounting contract is **+Z pointing down toward the floor**; center X/Y remain physical board axes until a forward/lateral mapping is measured.

XIAO center identity is **green** and must not hide retry/error indication. M5 center retains its yellow display identity. Existing trajectory models still consume L/R only; C is acquisition/storage instrumentation unless a separately validated center-aware model is introduced.

The specific XIAO center board was flashed/read back as firmware 1.8.2 and role C. A post-flash run reached 1,780.865 s before board removal; the last 1,750 s snapshot contained 179,290 samples with zero observed sequence, malformed, host-queue, firmware-queue, notification or FIFO loss/fault counters. This is strong partial runtime evidence, not final physical acceptance, because the final STOP/QC/reopen/export sequence and simultaneous L/R/C bench run were not completed.

## Model and research boundary

The installed Windows default remains the frozen classical L/R XY+yaw model. Experimental residual/Slalom/hybrid research paths do not silently replace the default. `BiWheel3D/` remains a separate local research repository and is not staged, merged or published as part of WheelAthlete 1.8.3.

## Release publication status

GitHub Release `v1.8.3` ([https://github.com/NnopponS/WheelAthelse/releases/tag/v1.8.3](https://github.com/NnopponS/WheelAthelse/releases/tag/v1.8.3)) was built and published via automated GitHub Actions workflow Run [#35434186521](https://github.com/NnopponS/WheelAthelse/actions/runs/35434186521):
- `WheelAthleteSetup-1.8.3.exe` (58.9 MB) — Windows Inno Setup installer supporting interactive setup and direct auto-updater.
- `WheelAthlete-1.8.3-portable.zip` (83.5 MB) — Windows standalone portable package.
- `WheelAthlete-1.8.3-android.apk` (120.1 MB) — Android release APK with Athlete, Trial, QC, and Windows-format CSV export.
- `WheelAthlete-1.8.3-android.aab` (79.6 MB) — Android release App Bundle.
- `latest.json` (546 B) — Verified update manifest consumed by the Windows in-app updater.
- `SHA256SUMS.txt` (386 B) — Cryptographic checksums for all release binaries.
- `windows-signing-report.json` & `android-signing-report.json` — CI signing provenance reports.

## Publication boundary

Private recordings, generated packages, local evidence, signing material, absolute user paths and the separate `BiWheel3D/` repository remain outside the source commit. Local evidence belongs under ignored `.project/local/`.

## Source/repository acceptance

Repository-side v1.8.3 consolidation is complete with the commit visible through `main`, `release/main-v1.8.3`, and tag/Release `v1.8.3`. Old remote branches and old visible Release entries are intentionally absent; historical tags remain.

## Deferred external acceptance

Two items remain outside what source consolidation can prove:

- trusted public Windows code signing (unsigned community build mode currently utilized in CI);
- final physical L/R/C hardware acceptance after the boards return.

Do not describe either item as complete until measured evidence exists.
