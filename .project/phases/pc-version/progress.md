# PC Version — Progress

Updated: 2026-08-31 (Asia/Bangkok)

## Completed

- Created branch `codex/pc-version` from release `v1.7.0` (`f6ad7d2`).
- Phase 1 commit `b970b69`: parity/architecture baseline and corrected stale
  async/STOP-ack test fixtures.
- Flutter baseline: `637 passed`, line coverage `81.83%`, `dart analyze lib`
  clean.
- Phase 2 commit `8d0d0a9`: XIAO link/timing hardening; `15 passed`; LEFT and
  RIGHT builds successful at 25,772 bytes RAM / 147,128 bytes flash.
- Phase 3 headless acquisition core:
  - strict exact-length IMU batch parser (1..12 samples),
  - uint32 wrap-aware sequence classification,
  - immutable notification envelopes with monotonic arrival time,
  - one bounded non-overwriting queue per wheel,
  - explicit fatal host-queue-overflow and malformed-packet faults,
  - authoritative sample sink independent from 10 Hz preview decimation,
  - dual-board engine with independent workers,
  - production Bleak adapter imported lazily and deterministic fake transport.
- Phase 3 tests: `5 passed`; `python -m compileall -q tools/pc_acquisition`
  successful.

## Current phase

Phase 4 — PC clock synchronization and deterministic START/STOP lifecycle.

Required first slice:

- strict parser for SYNC_RESPONSE, START_FIRED, STOP_FIRED, ACQ_HEALTH and
  command failure events.
- monotonic PC master timeline and uint32 device-clock unwrapping.
- robust min-RTT / low-RTT clock observations and linear drift fit.
- one future PC start T0 converted independently into both device clocks.
- START_FIRED required from both armed wheels.
- bounded STOP write retry and STOP_FIRED acknowledgement handling.
- no periodic dual-wheel control writes while recording.

## Blocked hardware evidence

- No boards available: no flash, serial link log, negotiated-link measurement,
  INT1 signal, FIFO behavior, radio throughput, dual-wheel sync, or zero-loss
  runtime evidence yet.
