# PC Version — Progress

Updated: 2026-08-31 (Asia/Bangkok)

## Completed

- Created branch `codex/pc-version` from release `v1.7.0` (`f6ad7d2`).
- Phase 1 commit `b970b69`: parity/architecture baseline and corrected stale
  async/STOP-ack test fixtures.
- Flutter baseline: `637 passed`, line coverage `81.83%`, `dart analyze lib`
  clean.
- Phase 2 XIAO host contracts: `15 passed`.
- Phase 2 XIAO LEFT and RIGHT release builds: SUCCESS.
  - RAM: 25,772 bytes / 237,568 bytes.
  - Flash: 147,128 bytes / 811,008 bytes.
- XIAO now requests MTU 247 and a 10 ms preferred connection interval, then
  logs the negotiated MTU, interval, and supervision timeout after connection.
- XIAO IMU polling now reads gyro+accelerometer in one coherent 12-byte burst
  with BDU + auto-increment and timestamps the I2C transaction midpoint.
- I2C burst failures are counted/logged rather than silently returning stale
  axes.
- FIFO/INT1 capability was researched against the installed Seeed/ST contract;
  activation is deliberately hardware-gated rather than implemented from
  unverified runtime assumptions.

## Current phase

Phase 3 — headless Python/Bleak dual-board acquisition engine.

Required first slice:

- BLE transport interface with a Bleak/WinRT production adapter.
- strict IMU/SYNC packet parsing.
- one bounded ingestion queue per board.
- callback path limited to immutable payload + `time.monotonic_ns()` enqueue.
- explicit overflow fault; never overwrite unread packets.
- sequence classification for contiguous/gap/duplicate/out-of-order/wrap.
- throttled preview separated from the authoritative stream.
- automated tests with no physical BLE dependency.

## Blocked hardware evidence

- No boards available: no flash, serial link log, negotiated-link measurement,
  INT1 signal, FIFO behavior, radio throughput, dual-wheel sync, or zero-loss
  runtime evidence yet.
