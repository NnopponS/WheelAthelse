# Android dual-wheel start race — v1.6.1 TDD evidence

Date: 2026-07-21
Branch: `codex/ble-reliability-v1.1`

## User journeys

1. Before the countdown, the Android app opens both notification channels and
   requests connection priority exactly once for each newly armed wheel.
2. When both boards report `START_FIRED`, recording reuses the existing
   subscriptions and does not renegotiate either BLE link.
3. If acquisition fails, the operator sees whether the source was the sample
   queue, the IMU FIFO, or BLE notification transport.
4. A release operator can compare each board's final produced/notified counts
   and split fault counters in COM4/COM15 logs.

## RED → GREEN evidence

| Requirement | RED evidence | GREEN evidence |
|---|---|---|
| Repeated `armStreaming()` is idempotent | New regression expected no calls on the second arm; old code returned `[L1, R1]`. | `second armStreaming with existing subscriptions does not prepare again` passes. |
| Prepare before countdown; reuse after start | Countdown integration test asserted preparation before injecting `START_FIRED` and the call list remaining unchanged afterwards. | Recording reaches `recording` with the same two preparation calls, one per wheel. |
| Split firmware health counters | Parser and host tests initially failed because FIFO fields/accessors and the 28-byte health packet did not exist. | App, M5, and XIAO tests accept the 28-byte packet; legacy 20-byte packets remain readable. |
| Report the correct failure cause | Recording test initially could not inject or classify an IMU FIFO fault independently. | An injected FIFO fault reports `left wheel IMU FIFO fault`, not BLE congestion. |
| Auditable final board counts | Structural test initially failed because no final acquisition summary existed. | M5 STOP completion logs `produced`, `notified`, `queue_drops`, `fifo_faults`, `fifo_drops`, `transport_failures`, and `queue_depth`. |

## Automated validation

| Gate | Result |
|---|---|
| Targeted Flutter recording/countdown tests | PASS — 40 tests |
| Full Flutter test suite (`flutter test --concurrency=1`) | PASS — 630 tests |
| Dart analyzer (`dart analyze lib`) | PASS — no issues |
| M5 host tests | PASS — 134 tests |
| XIAO host tests | PASS — 12 tests |
| M5 PlatformIO left/right release builds | PASS — 2 environments |
| XIAO PlatformIO left/right release builds | PASS — 2 environments |

## Physical release gate

The physical gate must be filled from live evidence, not inferred from unit
tests. The required evidence is 20 dual-wheel phone Start/Stop cycles with one
final summary per side per cycle, no queue/FIFO/transport loss, and matching
produced/notified counts. APK installation, M5 flashing, and COM4/COM15 capture
are tracked in the continuation of this task.

## Worktree note

The branch already contained extensive uncommitted reliability work when this
TDD pass began. No RED/GREEN checkpoint commits were created because staging
the overlapping files would risk including or rewriting unrelated user work;
the failing and passing observations are preserved above instead.
