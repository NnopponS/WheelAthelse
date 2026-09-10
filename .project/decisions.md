# WheelAthlete current engineering decisions

Updated: 2026-09-10.

Only active durable decisions belong here. Historical experiment outcomes and superseded branch instructions belong in Git history or `.project/history/`.

## D1 - v1.8.2 is Windows-first

The active release surface is the Python/PySide6 **WheelAthlete Windows Research Application** plus maintained M5/XIAO firmware. Flutter Android/iOS source remains maintenance material, but new mobile source changes, mobile binaries and mobile updater assets are excluded from the current v1.8.2 publication unless explicitly requested later.

## D2 - One BLE protocol, explicit role semantics

All clients and firmware use `docs/ble-protocol.md`. Role bytes are `L=0x4C`, `R=0x52`, and optional chair-center `C=0x43`. Packet/command semantic changes require coordinated documentation and compatibility tests.

## D3 - L/R is the production model baseline; C is optional instrumentation

L/R wheel hubs remain the production sensing/model input. C is a chair-frame IMU with declared **+Z down toward the floor**. Center X/Y remain physical board axes until measured. Existing production trajectory models must not silently consume C.

## D4 - Center identity is hardware-specific

XIAO center uses a **green** identity/heartbeat while preserving higher-priority retry/error indication. M5 center retains the yellow display identity. Identity color is not evidence of correct orientation, range, sample rate or data integrity.

## D5 - Supported acquisition rates are explicit

Supported board acquisition rates are 50, 100 and 200 Hz. Metadata alone is not evidence that the connected hardware actually applied the requested configuration.

## D6 - Windows raw-data ownership stays outside the GUI

`tools.pc_acquisition` owns BLE, clocks, sequence/loss accounting, append-only journal writes, QC and recovery. `tools.pc_gui` receives state/preview/control over localhost IPC. Preview may be bounded; authoritative raw capture must fail visibly rather than silently drop data.

## D7 - `.waj` is authoritative

Windows raw recording truth is append-only `.waj`; CSV and summaries are derived. L/R-only recordings retain journal v1 semantics. Recordings containing C use journal v2 with explicit `C` side code. Historical data must not be reinterpreted by newer readers.

## D8 - Synchronization requires provenance

Cross-sensor timing uses saved clock observations/drift fitting and common scheduled-start evidence. Independently zeroing L/R/C epochs is not synchronization proof. Windows uses the high-resolution performance-counter clock domain for host timing.

## D9 - One operator owns a sensor set

Do not operate the same connected L/R[/C] set concurrently from multiple operator clients.

## D10 - Model defaults remain frozen until accepted evidence exists

The installed Windows default remains the frozen classical L/R model. Experimental residual, Slalom and hybrid paths are opt-in research tools. Model promotion requires reproducible application-runtime behavior plus independent grouped validation/final evidence.

## D11 - Course constraints must be labeled as constraints

Slalom endpoint/heading closure uses known protocol structure. Report raw pose, constrained pose and correction magnitudes separately. A constrained endpoint near zero is not independent odometry accuracy.

## D12 - Research/private boundaries are strict

`BiWheel3D/` is a separate local repository and is not part of the WheelAthlete root publication. Do not publish athlete recordings, participant-derived data, pseudo-GT, generated private models, local evidence, absolute private paths or signing material.

## D13 - Build artifacts are not source state

Packaging definitions are source-controlled; generated installers, portable archives, firmware binaries, `.pio` trees, Python caches and recordings remain ignored/untracked. A successful build is not a physical flash, release or acceptance result.

## D14 - Public Windows binaries require trusted signing

A public Windows installer/portable/update manifest is allowed only when the fail-closed signing pipeline verifies the required packaged executable components, generated uninstaller and installer, and `public_release_ready=true`. Checksums do not establish publisher trust.

## D15 - Installed upgrades must preserve research data

Upgrade/uninstall must gracefully stop the installation-owned daemon, finalize active journals when safe, and preserve recordings, logs and custom/seeded models. If safe daemon shutdown cannot be verified, setup must stop instead of replacing/removing files.

## D16 - Branch surface is intentionally small

The normal public branch surface after v1.8.2 consolidation is `main` plus `release/main-v1.8.2`. `main` must not be force-pushed. Release tags identify exact tested commits. Obsolete remote development/release branches may be removed once their work is fully contained in the integrated release history.

## D17 - Historical tags are traceability, not active release branches

Old GitHub Release entries and remote branches may be removed from the visible project surface when explicitly requested. Historical version tags may remain so released source ancestry can still be traced without keeping obsolete branches alive.

## D18 - Physical claims require physical evidence

Unit tests, simulated BLE and compile output prove software/build behavior only. Real RF throughput, start skew, gravity orientation, sensor ranges, data loss and trajectory accuracy require physical/reference measurements.

## D19 - Deferred hardware acceptance does not block source hygiene

The XIAO C 1.8.2 partial runtime evidence may be documented accurately, but final C QC/reopen/export and simultaneous L/R/C acceptance remain deferred until hardware returns. The source repository can still be consolidated and released source-only while that external evidence is pending.
