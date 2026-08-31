# PC Version — Progress

Updated: 2026-08-31 (Asia/Bangkok)

## Completed

- Created branch `codex/pc-version` from release `v1.7.0` (`f6ad7d2`).
- Phase 1 commit `b970b69`: parity/architecture baseline and corrected stale
  async/STOP-ack test fixtures.
- Flutter: `637 passed`, line coverage `81.83%`, `dart analyze lib` clean.
- XIAO Phase 2 RED test captured, then all `15` host contract tests passed.
- XIAO LEFT and RIGHT release images both build successfully; current image
  size is 25,772 bytes RAM and 147,128 bytes flash.

## In progress (not yet committed)

- Peripheral requests MTU 247 and a 10 ms preferred interval and logs actual
  negotiated MTU/interval/supervision values after connection.
- IMU polling uses one coherent register burst with BDU + auto-increment and a
  midpoint device timestamp; I2C read faults are counted/logged.
- Official ST/Seeed research confirms a 4 KB sensor FIFO, watermark/status and
  FIFO pattern registers, and XIAO IMU INT1 routed to nRF52840 P0.11.
- Reviewing FIFO word pattern and overrun handling before enabling FIFO mode.

## Blocked hardware evidence

- No boards available: no flash, serial link log, INT1 signal, FIFO behavior,
  radio throughput, dual-wheel sync, or zero-loss runtime evidence yet.

## Next

1. Finish or explicitly defer the FIFO drain implementation based on the ST
   pattern contract and build reliability.
2. Commit Phase 2.
3. Start Phase 3 headless Python collector with tests first.
