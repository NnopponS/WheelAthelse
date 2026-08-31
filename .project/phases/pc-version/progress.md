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
- Phase 3 commit `857a164`: strict headless dual-board ingestion core with
  independent bounded queues and preview isolation.
- Phase 4 synchronization/lifecycle:
  - strict Sync parser for v1.7 + compatible legacy event sizes,
  - uint32 `micros()` unwrapping,
  - low-RTT affine PC/device clock fit with drift/RTT/residual metrics,
  - common future PC T0 converted to independent device START targets,
  - required START_FIRED mapping and measured Left/Right start skew,
  - serialized bounded STOP retries,
  - STOP_FIRED required before success,
  - persistent STOP-write failure or ACK timeout disconnects through the engine
    to trigger firmware failsafe and clear local ownership,
  - no periodic dual-wheel control traffic is introduced during recording.
- PC acquisition tests: `11 passed`.

## Current phase

Phase 5 — append-only journal, crash recovery, QC, and derived exports.

Required first slice:

- versioned binary journal with magic/header and checksum per record.
- `.open` during acquisition, fsync checkpoints, atomic rename to `.waj` only
  after successful finalization.
- raw sample records preserve side, seq, device us, PC monotonic ns, six raw
  axes, packet id and sequence classification.
- recovery scans incomplete `.open` files, validates to last complete checksum,
  and preserves partial data.
- QC reconciles final firmware produced/notified/received counts, host gaps,
  queue overflow, malformed data, FIFO loss, transport failures, effective rate
  and synchronized-start skew.
- CSV export is derived from the journal after acquisition.

## Blocked hardware evidence

- No boards available: no flash, serial link log, negotiated-link measurement,
  INT1 signal, FIFO behavior, radio throughput, dual-wheel sync, or zero-loss
  runtime evidence yet.
