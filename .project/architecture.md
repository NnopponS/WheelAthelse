# WheelAthlete runtime architecture

Updated: 2026-09-10.

WheelAthlete v1.8.2 is a Windows-first acquisition/research release with maintained M5/XIAO firmware. The stable sensing/model baseline is two wheel-hub IMUs (`L`, `R`); the acquisition stack also supports an optional chair-center IMU (`C`) for controlled experiments.

## Public product and repository boundaries

```text
applications/
  wheelathlete_windows/                 active v1.8.3 Windows application
  wheelathlete_mobile/                  active v1.8.3 Flutter mobile application (feature parity with Windows)
hardware_firmware/
  m5stickc_plus2/                       ESP32/M5StickC Plus2 firmware
  xiao_nrf52840_sense/                  nRF52840/LSM6DS3 firmware
docs/                                   BLE/model contracts and public documentation
release/                                release notes + manifest tooling, not generated binaries
scripts/                                verification/hygiene tooling
.project/                               current engineering state + ignored local evidence
BiWheel3D/                              separate local research repository, never root-published
```

`BiWheel3D/` is not a root submodule and must not become an installed runtime dependency. Generated packages, participant data and local evidence are outside the source-publication boundary.

## Sensor roles

| Role | Identity | Physical meaning | Production model use |
|---|---|---|---|
| L | `0x4C` | left wheel-hub IMU | L/R model input |
| R | `0x52` | right wheel-hub IMU | L/R model input |
| C | `0x43` | optional chair-center/frame IMU | production: acquisition/storage only; explicit offline three-IMU research V5-V8 may consume C |

Center mounting contract: **+Z points down toward the floor**. Center X/Y remain physical board axes until forward/lateral orientation is measured. Code must not silently map C to R or extend the legacy L/R model tensor by enum iteration.

XIAO C uses a **green** identity/heartbeat. Retry/error indication has priority over identity color. M5 C retains its yellow display identity.

## Windows acquisition ownership

```text
L/R[/C]
   |
   v
BLE / WinRT
   |
   v
Acquisition daemon
   |-- packet parsing + per-role sequence/loss accounting
   |-- clock observations + synchronized lifecycle
   |-- append-only .waj journal + QC/recovery
   |
   +--> bounded localhost IPC --> PySide6 GUI
                                |-- Dashboard / Acquisition
                                |-- Results / export
                                |-- Diagnostics
                                `-- optional offline MODEL review
```

The GUI is not the authoritative raw-data path. Slow rendering, analysis or a GUI restart must not silently become a BLE recording bottleneck.

Only one operator application may own a given sensor set at a time.

## Storage and compatibility

The BLE 20-byte IMU sample payload remains unchanged; the role vocabulary is extended with C.

Windows:
- L/R-only journals retain journal v1 semantics.
- A recording containing C uses journal v2.
- v2 side codes are `L=0`, `R=1`, `C=2`.
- incomplete `.open` journals can be recovered through the existing recovery path.
- CSV and summaries are derived outputs; `.waj` remains authoritative.

Retained mobile source uses its own versioned storage. It is not part of the current v1.8.2 release publication.

## Clock and synchronization boundary

Raw packet data retains device microsecond timestamp, sequence, arrival timestamp and sequence classification. Saved clock observations and START evidence establish the application's chosen device-to-host mapping; they are not independent physical-synchronization proof.

Windows host timing uses the high-resolution `perf_counter_ns()`/QueryPerformanceCounter domain. Any L/R/C model, including research-only V5-V8 offline estimators, must preserve explicit three-stream clock provenance; independently setting each stream start to zero is not acceptable alignment.

## Offline analysis boundary

### Production default

The installed Windows default remains the frozen classical L/R XY+yaw runtime. Existing model feature extraction explicitly selects L/R and must be identical whether arbitrary C samples are present or absent.

### Experimental models

Residual/Slalom/hybrid estimators remain explicit research choices. Bundled three-IMU V5-V8 estimators are research-only: they consume synchronized L/R/C IMU streams and frozen development artifacts, while V3 remains the active/default 3-IMU application method and the installed production default remains the frozen L/R runtime. V7 adds a spin-orthogonal hub-yaw observation; V8 uses that observation to estimate a persistent causal center-yaw bias state. Neither is a promoted runtime. C3D/reference data is never an inference input. Protocol constraints must be reported separately from unconstrained motion estimates.

New portable models use the contained `wheelathlete-model.json` bundle contract and cannot escape the bundle directory or silently introduce arbitrary Python execution.

## Upgrade, uninstall and update architecture

The Inno Setup installer uses a stable application identity. Before upgrade/uninstall it invokes the installation-specific daemon shutdown path. Active journals are finalized through the normal recording end path when safe; failure to prove a clean shutdown blocks file replacement/removal. User recordings, logs and custom/seeded models are preserved.

Installed updater flow:

```text
GitHub Releases latest.json
        |
        | HTTPS + repository-path restriction
        v
version / exact size / SHA-256 validation
        |
        v
verified Inno installer downloaded in-app
        |
        v
idle acquisition safety check -> launch interactive setup dialog -> clean app exit -> upgrade
```

The v1.8.3 Release publishes `latest.json` alongside `WheelAthleteSetup-1.8.3.exe` and Android release assets.

## Trust and release architecture

A signed build requires a trusted RSA Code Signing identity with Code Signing EKU, current validity, exact expected publisher subject and a timestamp service. The packaging pipeline signs/verifies packaged EXE/DLL/PYD/PowerShell components and uses Inno signing for the generated uninstaller/installer. Release metadata reports component status and `public_release_ready`.

Unsigned community builds may be built and published in `ALLOW_UNSIGNED_RELEASE=true` mode for open-source distributions.

The intended public branch surface is `main` plus `release/main-v1.8.3`; release tag `v1.8.3` points at the exact final tested commit.
