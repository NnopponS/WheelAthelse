# PC version Phase 4 — synchronization and lifecycle evidence

## RED -> GREEN

- RED: sync/lifecycle tests failed collection because the clock, control, sync
  parser, and lifecycle modules did not exist.
- GREEN: `python -m pytest tools/pc_acquisition/tests -q` reports `11 passed`.

## Implemented guarantees

- Sync events use exact allowed packet sizes. Truncated/trailing packets are
  rejected rather than accepted on a best-effort basis.
- PC time is `time.monotonic_ns()`. SYNC_PING stores T1 locally; the Sync
  callback contributes T3 from the notification envelope; the clock observation
  uses the T1/T3 midpoint and firmware T2 device timestamp.
- The uint32 device `micros()` counter is unwrapped across rollover.
- Clock fitting keeps the lowest-RTT half of observations, reports best/median
  RTT, affine drift ppm and residual RMS, and maps in both directions.
- Synchronized START chooses one PC T0 and converts it to each board's local
  device timestamp. Command write order is not used as the synchronization
  mechanism.
- START success requires START_FIRED and reports mapped Left/Right skew.
- STOP writes are serialized across peripherals and retried with bounded
  backoff. ACKs are then awaited independently.
- Persistent STOP write failure and missing STOP_FIRED both disconnect the
  affected board through the engine so firmware disconnect handling is the
  final acquisition failsafe.
- Final ACQ_HEALTH received before STOP_FIRED is retained with the Stop result.

## Hardware gate

The clock and lifecycle state machines are deterministic simulated evidence.
No claim is made for actual BLE RTT, drift, START skew, STOP latency, or radio
reliability until two physical XIAO boards are exercised.
