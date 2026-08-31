# PC Version — Progress

Updated: 2026-08-31 (Asia/Bangkok)

## Completed

- Phase 1 `b970b69`: parity/architecture baseline.
- Phase 2 `8d0d0a9`: XIAO link/timing hardening; `15 passed`; LEFT/RIGHT
  firmware builds green.
- Phase 3 `857a164`: strict headless dual-board ingestion core.
- Phase 4 `da6249a`: monotonic clock mapping and safe synchronized lifecycle.
- Phase 5 `118e1bc`: crash-safe append-only journal, recovery and fail-closed QC.
- Phase 6 Windows process boundary:
  - Python `AcquisitionService` composes transport, dual-board engine,
    synchronization, lifecycle, recording journal and QC.
  - commands include scan/connect/disconnect/configure/sync/arm/scheduled_start/
    stop/status/start_record/end_record/recover.
  - daemon IPC binds only to `127.0.0.1`, uses protocol v1 NDJSON, 64 KiB
    bounded messages, hello/version handshake and request-id correlation.
  - raw sample stream never crosses IPC; only a 10 Hz `sample_preview` plus
    status/health/sync/recording events are exposed.
  - Dart `DesktopDaemonClient` implements the same versioned contract and a
    Riverpod desktop acquisition state is available without replacing the
    mobile `BleRepository`.
  - scheduled START timeout was corrected to include remaining lead time to T0
    plus the post-start ACK margin.
- Phase 6 Python suite: `18 passed`.
- Desktop Dart IPC tests: `2 passed`; desktop Dart analysis: no issues.
- Python compileall: clean.

## Windows build environment blocker

`flutter build windows --release` currently cannot run on this machine because
Flutter reports: `Unable to find suitable Visual Studio toolchain.` A supported
Visual Studio installation with Desktop development with C++ is required. No
system-wide toolchain was installed automatically during this task.

## Current phase

Phase 7 — prove Android/mobile behavior remains intact before adding desktop UI.

## Blocked hardware evidence

- No boards available: no flash, serial link log, negotiated-link measurement,
  INT1 signal, FIFO behavior, radio throughput, dual-wheel sync, or zero-loss
  runtime evidence yet.
