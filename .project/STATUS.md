# WheelAthlete current status

Updated: 2026-09-10

## Release line

- Product: **WheelAthlete 1.8.2**
- Primary branch: `main`
- Release branch target: `release/main-v1.8.2`
- Windows application: `1.8.2`
- M5StickC Plus2 firmware: `1.8.2`
- XIAO nRF52840 Sense firmware: `1.8.2`
- BLE protocol: `1.8.0`
- Flutter source: `1.8.2+12`, maintenance only and excluded from the current release publication

## Consolidation state

The 1.8.2 repair work and earlier dual-IMU coaching-analysis work are already ancestors of `main`. The remaining Windows trust-hardening branch was merged into `main` on 2026-09-10 without force-pushing or conflicts. No mobile source file was introduced by that merge.

The current consolidation is standardizing the public repository around only two remote branches: `main` and `release/main-v1.8.2`. Historical release entries are being removed from the GitHub Releases page while historical version tags are retained for traceability. The separate local `BiWheel3D/` repository is outside this publication boundary.

## Windows application

The maintained Windows application uses a PySide6 GUI plus a separate acquisition daemon. The daemon owns BLE, sequence accounting, synchronization, append-only `.waj` recording, QC and recovery; the GUI owns operator workflow, preview, Results, diagnostics, export and optional offline model review.

Implemented 1.8.2 release features include:

- persistent Day -> Experiment -> Trial Results selection and deduplicated batch export;
- explicit daemon shutdown and active-journal finalization before upgrade/uninstall;
- preservation of recordings and custom/seeded models through installer lifecycle operations;
- high-resolution `perf_counter_ns()` timing for Windows acquisition and scheduled-start calculations;
- concrete sensor fault reporting instead of an unexplained generic `CHECK` state;
- contained versioned portable model bundles with compatibility/path validation;
- installed-app update support through a verified GitHub Release manifest when a trusted signed release exists;
- fail-closed Windows release signing that verifies packaged EXE/DLL/PYD/PowerShell components, the generated uninstaller and the installer.

Fresh 2026-09-10 consolidation verification passed **195/195** Windows tests, **4/4** Windows packaging-layout tests, **19/19** XIAO host tests, **147/147** M5 host tests, release-manifest unit tests, Python compile checks, project hygiene, and `git diff --check`. XIAO and M5 L/R/C PlatformIO environments all produced fresh build artifacts. A full local unsigned Windows package build also completed through PyInstaller, Inno Setup, portable ZIP, checksums, and signing-report generation.

## Firmware and optional center sensor

The supported sensor roles are `L`, `R`, and optional chair-center `C` (`0x43`). The center mounting contract is **+Z pointing down toward the floor**; center X/Y remain physical board axes until a forward/lateral mapping is measured.

XIAO center identity is **green** and must not hide retry/error indication. M5 center retains its yellow display identity. Existing trajectory models still consume L/R only; C is acquisition/storage instrumentation unless a separately validated center-aware model is introduced.

The specific XIAO center board was flashed/read back as firmware 1.8.2 and role C. A post-flash run reached 1,780.865 s before board removal; the last 1,750 s snapshot contained 179,290 samples with zero observed sequence, malformed, host-queue, firmware-queue, notification or FIFO loss/fault counters. This is strong partial runtime evidence, not final physical acceptance, because the final STOP/QC/reopen/export sequence and simultaneous L/R/C bench run were not completed.

## Model and research boundary

The installed Windows default remains the frozen classical L/R XY+yaw model. Experimental residual/Slalom/hybrid research paths do not silently replace the default. `BiWheel3D/` remains a separate local research repository and is not staged, merged or published as part of WheelAthlete 1.8.2.

## Release and trust status

The current GitHub v1.8.2 page is source-only. Public Windows binaries and `latest.json` remain blocked until a trusted RSA Code Signing identity with Code Signing EKU, the exact expected publisher subject and an RFC3161 timestamp service are available. Local unsigned packages are development artifacts only and must not be presented as solving SmartScreen/Application Control trust.

The fresh unsigned-local packaging run generated a 63,571,038-byte installer (SHA-256 `BE5C2B8769E3DC87116A7CD491F54B780984BE2D12D03418A807635EE899F5C4`) and a 92,775,101-byte portable ZIP (SHA-256 `E662D1D9A43660966FB02121F1C4763AAAA8A20050B913820F4E2649B36497A7`). Its signing report is schema 2, covers 163 executable components, and correctly reports `public_release_ready=false` because no trusted signing identity is configured. These generated files remain ignored local evidence and must not be uploaded.

When signing is configured, the release build must return `public_release_ready=true` before Windows installer/portable/update assets are published.

## Publication boundary

The current consolidation does **not** publish new mobile source changes or mobile binaries. Existing Flutter history/source is retained as maintenance material, but no APK/AAB/IPA or mobile update offer belongs to v1.8.2.

Private recordings, generated packages, local evidence, signing material, absolute user paths and the separate `BiWheel3D/` repository must remain outside the source commit. Local evidence belongs under ignored `.project/local/`.

## Final gates for this consolidation

1. Refresh EN/TH README, release documentation, current project-state documents and stale center/release references.
2. Confirm repository hygiene and no accidental mobile/BiWheel3D/private-material diff.
3. Run the full Windows test suite and release/package checks at the exact final commit.
4. Run firmware host verification/build checks for maintained targets.
5. Push `main`, create/push `release/main-v1.8.2`, retarget the source-only `v1.8.2` tag/release to the final tested commit, remove old visible GitHub Release entries, and remove obsolete remote branches.

## Deferred external acceptance

Two items remain outside what source consolidation can prove:

- trusted public Windows code signing;
- final physical L/R/C hardware acceptance after the boards return.

Do not describe either item as complete until measured evidence exists.
