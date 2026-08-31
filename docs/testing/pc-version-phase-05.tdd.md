# PC version Phase 5 — journal, recovery and QC evidence

## RED -> GREEN

- RED: journal/QC tests failed collection because the modules did not exist.
- Targeted GREEN: `test_journal_qc.py` reports `4 passed`.
- Full PC GREEN: `python -m pytest tools/pc_acquisition/tests -q` reports
  `15 passed`.
- STATIC: `python -m compileall -q tools/pc_acquisition` succeeds.

## Implemented guarantees

- The authoritative session artifact is a versioned binary journal, not CSV.
- Every record is framed with kind, bounded payload length and CRC32.
- Raw sample records preserve session UUID, wheel, sequence number, device
  timestamp, PC monotonic arrival timestamp, raw six-axis values, packet id,
  sequence classification and missing-before count.
- The writer owns a bounded queue and dedicated thread. Queue overflow is a
  fatal `journal_queue_overflow` fault and unread data is never overwritten.
- Header and bounded record checkpoints are flushed/fsynced. Clean finalization
  appends FINALIZE, fsyncs, closes and atomically renames `.open` to `.waj`.
- Recovery never mutates or deletes the original incomplete `.open`. It copies
  only the checksum-valid prefix into a separate `.recovered.waj`.
- CSV export is derived by reading a validated journal after acquisition.
- QC is fail-closed: known sample loss, malformed packets, host/writer overflow,
  FIFO loss and produced/notified/received mismatch are INVALID. Missing final
  evidence is DEGRADED, and non-loss transport retries/rate deviations can be
  WARNING. RSSI alone never determines quality.

## Hardware gate

These tests prove storage/recovery/QC logic under simulated inputs only. Final
firmware counters and real radio behavior remain unverified until Phase 10.
