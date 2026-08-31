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
- Phase 6 Python suite: `18 passed`; desktop Dart IPC tests: `2 passed`;
  Python compileall and desktop Dart analysis clean.
- Phase 7 mobile regression evidence:
  - complete Flutter test suite: `641/641 passed`;
  - production `bleRepositoryProvider` still constructs
    `FlutterBluePlusBleRepository`;
  - desktop daemon provider remains opt-in and disconnected until requested;
  - `dart analyze lib`: no issues;
  - `flutter build apk --release`: green, generated 52.8 MB APK.

## Windows build environment blocker

`flutter build windows --release` currently cannot run on this machine because
Flutter reports: `Unable to find suitable Visual Studio toolchain.` A supported
Visual Studio installation with Desktop development with C++ is required. No
system-wide toolchain was installed automatically during this task.

## Current phase

Phase 8 — build the desktop operator UI and serious diagnostics around the
daemon process boundary without altering the lossless raw path.

## Blocked hardware evidence

- No boards available: no flash, serial link log, negotiated-link measurement,
  INT1 signal, FIFO behavior, radio throughput, dual-wheel sync, or zero-loss
  runtime evidence yet.
