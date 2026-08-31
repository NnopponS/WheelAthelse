# PC Version — Progress

Updated: 2026-08-31 (Asia/Bangkok)

## Completed

- Phase 1 commit `b970b69`: parity/architecture baseline.
- Phase 2 commit `8d0d0a9`: XIAO link/timing hardening; `15 passed`; LEFT/RIGHT
  firmware builds green.
- Phase 3 commit `857a164`: strict headless dual-board ingestion core with
  independent bounded queues and preview isolation.
- Phase 4 commit `da6249a`: monotonic clock mapping, synchronized scheduled
  START, START/STOP acknowledgements, bounded STOP retry and fail-closed
  disconnect fallback.
- Phase 5 crash-safe storage/QC:
  - `WATHJNL1` versioned append-only journal with CRC32 per record,
  - dedicated bounded writer queue; overflow is a fatal QC fault and never
    overwrites unread data,
  - each sample preserves session UUID, side, seq, device-us, PC monotonic-ns,
    six raw axes, packet id, sequence class and missing-before count,
  - acquisition uses `.open`; clean finalization fsyncs then atomically renames
    to `.waj`,
  - recovery validates to the last checksum-complete record and writes a
    separate `.recovered.waj` while preserving the forensic `.open` original,
  - CSV is generated only as a derived artifact after journal reading,
  - QC levels GOOD/WARNING/DEGRADED/INVALID carry machine-readable reasons and
    reconcile host loss, writer overflow, final firmware counts/health,
    effective rate and synchronized-start skew.
- Phase 5 PC suite: `15 passed`; Python compileall clean.

## Current phase

Phase 6 — versioned localhost IPC and Flutter Windows backend integration.

Required slice:

- Python daemon can run without Flutter and owns BLE/journal/lifecycle state.
- localhost-only TCP NDJSON with version handshake and bounded message size.
- commands/events use `protocol_version`, `type`, optional `request_id`, and
  object `payload`; invalid versions/messages fail explicitly.
- Flutter Windows client receives device/status/preview/health/sync/QC events.
- raw 50/100/200 Hz samples never cross IPC.
- Android/mobile repository selection remains unchanged.

## Blocked hardware evidence

- No boards available: no flash, serial link log, negotiated-link measurement,
  INT1 signal, FIFO behavior, radio throughput, dual-wheel sync, or zero-loss
  runtime evidence yet.
