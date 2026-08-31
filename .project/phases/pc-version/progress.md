# PC Version — Progress

Updated: 2026-09-01 (Asia/Bangkok)

## Completed

- Phase 1 `b970b69`: parity/architecture baseline.
- Phase 2 `8d0d0a9`: XIAO link/timing hardening; `15 passed`; LEFT/RIGHT
  firmware builds green.
- Phase 3 `857a164`: strict headless dual-board ingestion core.
- Phase 4 `da6249a`: monotonic clock mapping and safe synchronized lifecycle.
- Phase 5 `118e1bc`: crash-safe append-only journal, recovery and fail-closed QC.
- Phase 6 `a8927ae`: versioned localhost Python daemon ↔ Flutter Windows IPC;
  raw samples remain daemon-owned and only throttled preview/status cross IPC.
- Phase 7 `4b4aef9`: mobile backend boundary proven unchanged; full mobile
  regression and Android release packaging remained green.
- Phase 8: Windows operator shell + observability:
  - Dashboard / Connect / Live / Record / Experiments / Sessions / Diagnostics;
  - per-board name, firmware, RSSI, battery, MTU, configured/effective rates;
  - host queue depth/high-water/overflow, sequence gaps/duplicates/out-of-order,
    firmware produced/notified/drop/transport/FIFO health and clock-fit data;
  - 1 Hz status polling and bounded 10 Hz preview history only;
  - deterministic Record flow through daemon, with selected 50/100/200 Hz
    written to every connected board before `start_record`;
  - protocol-template ID/tags preserved in journal metadata;
  - atomic `.summary.json`, PC session listing/search, CSV derivation, recovery
    and diagnostic report export;
  - Windows `main()` selects the desktop shell while the default app constructor
    continues to use the existing mobile `HomePage`.

## Phase 8 verification

- PC acquisition suite: `21 passed`.
- Desktop Flutter suite: `8 passed`.
- `python -m compileall -q tools\pc_acquisition`: clean.
- `dart analyze lib test\desktop`: `No issues found!`.
- complete Flutter suite with current production code: `644 passed`.
- Android release build: green, `app-release.apk` ≈ `52.9 MB`.
- Evidence: `docs/testing/pc-version-phase-08.tdd.md`.

## Windows build environment blocker

`flutter build windows --release` cannot run on this machine because Flutter
reports `Unable to find suitable Visual Studio toolchain.` A supported Visual
Studio installation with Desktop development with C++ is required. No
system-wide toolchain was installed automatically during this task.

## Current phase

Phase 9 — accelerated long-run simulation, burst/backpressure tests and fault
injection. The target is at least 30 minutes equivalent per wheel at both 100 Hz
and 200 Hz, plus the 50 Hz configuration path, without inventing hardware claims.

## Blocked hardware evidence

- No boards available: no flash, serial link log, negotiated-link measurement,
  INT1 signal, FIFO behavior, radio throughput, dual-wheel sync, or zero-loss
  physical-runtime evidence yet.
