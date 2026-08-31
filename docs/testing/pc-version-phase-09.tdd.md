# WheelAthlete PC Version — Phase 9 Stress / Fault Verification

Date: 2026-09-01 (Asia/Bangkok)
Branch: `codex/pc-version`
Scope: automated/simulated evidence only; no physical XIAO claims

## Goal

Prove that the PC acquisition architecture remains fail-closed and lossless
under accelerated long-run load, notification bursts, slow UI backpressure,
slow/failing disk behavior, and release-regression gates.

The test evidence in this phase is intentionally separated from physical RF,
BLE-controller, sensor-FIFO, and real dual-XIAO evidence. Those remain Phase 10.

## Stress matrix

`tools/pc_acquisition/tests/test_stress_simulation.py` simulates two independent
wheel streams with strict 12-sample BLE batches and synthetic device timestamps.
Each rate represents 30 minutes of logical acquisition per wheel:

| Rate | Samples / wheel | Samples total | Notifications / wheel | Batch interval |
|---:|---:|---:|---:|---:|
| 50 Hz | 90,000 | 180,000 | 7,500 | 240 ms |
| 100 Hz | 180,000 | 360,000 | 15,000 | 120 ms |
| 200 Hz | 360,000 | 720,000 | 30,000 | 60 ms |

For every simulated wheel/rate the test requires:

- exact authoritative sample count;
- exact notification count;
- sequence gaps = 0;
- duplicates = 0;
- out-of-order samples = 0;
- malformed packets = 0;
- host ingestion queue overflow = 0;
- no fatal ingestion fault;
- queue fully drains at completion;
- preview remains bounded to approximately 10 Hz and therefore cannot become
  the authoritative raw path.

A separate burst test injects 400 notifications per wheel without yielding,
which is 4,800 samples per wheel at the maximum 12-sample packet size. The
configured 512-notification per-wheel queues absorb the burst with no loss.

## Authoritative journal stress

`tools/pc_acquisition/tests/test_journal_stress.py` performs an accelerated
30-minute-equivalent writer test at dual-wheel 200 Hz:

- 360,000 samples per wheel;
- 720,000 total raw samples;
- bounded 4,096-sample writer queue;
- append-only `.waj` format;
- final CRC/frame validation;
- no queue overflow and no writer fatal fault;
- completed journal contains exactly 720,002 valid records
  (720,000 samples + metadata + finalize).

The phase also injects two storage faults:

1. **Slow disk / writer backpressure** — the writer is deliberately delayed.
   Once its bounded queue fills, `submit_sample()` rejects the next sample,
   increments `journal_queue_overflow`, and sets a fatal acquisition fault.
   Previously accepted samples still drain to disk; unread queued samples are
   never overwritten.
2. **Disk write exception** — one sample write raises a simulated `OSError`.
   The writer records `journal_write_failure`, continues keeping the file
   structurally parseable, and never silently certifies the session as valid.

Phase 9 hardens final QC so `end_record` waits for the journal writer to become
idle before evaluation, then compares:

`journal samples written == sum(host samples received)`

Any journal writer fatal fault or count mismatch is `INVALID`. The finalized
summary now preserves journal samples-written, queue high-water, overflow count,
max write latency, and fatal-fault details.

## Slow/frozen Flutter UI isolation

`tools/pc_acquisition/tests/test_ipc_backpressure.py` verifies the localhost IPC
boundary:

- raw IMU samples never cross IPC;
- `sample_preview` is best-effort only;
- preview is dropped when a client socket reaches the 256 KiB preview-buffer
  threshold;
- preview publishing never awaits `drain()`;
- critical lifecycle/error traffic retains reliable `drain()` behavior;
- preview sent/dropped/max-buffer counters are exposed in `status`;
- exported diagnostic reports contain the IPC isolation counters as well.

The Flutter Diagnostics page surfaces:

- ready UI clients;
- preview events sent;
- preview events dropped;
- maximum observed preview socket buffer;
- configured preview buffer limit.

This makes UI slowness observable without allowing it to compromise the
BLE → parser → journal acquisition path.

## QC fault evidence

`tools/pc_acquisition/tests/test_journal_qc.py` verifies that an incomplete or
faulted authoritative journal is `INVALID`, including both:

- `journal_writer_fault`;
- `journal_count_mismatch`.

Existing fail-closed evidence remains active for malformed packets, sequence
gaps, host queue overflow, firmware queue loss, FIFO loss, count mismatch,
missing lifecycle acknowledgements, and transport failures.

## Automated results

Final Phase 9 gates on the current source tree:

- `python -m pytest tools/pc_acquisition/tests -q`
  - **31 passed in 22.09 s**
- Phase 9 stress/fault subset after all additions
  - all stress/backpressure/journal tests passed
- `flutter test test/desktop`
  - **8 passed**
- `dart analyze lib test/desktop`
  - **No issues found**
- `flutter test`
  - **645 passed**
- `python -m compileall -q tools/pc_acquisition`
  - clean
- `python -m pytest Xiao_firmware/test -q`
  - **15 passed**
- `pio run -e left`
  - SUCCESS
  - RAM: 25,772 / 237,568 bytes (10.8%)
  - Flash: 147,128 / 811,008 bytes (18.1%)
- `pio run -e right`
  - SUCCESS
  - RAM: 25,772 / 237,568 bytes (10.8%)
  - Flash: 147,128 / 811,008 bytes (18.1%)
- `flutter build apk --release`
  - SUCCESS
  - `build/app/outputs/flutter-apk/app-release.apk` ≈ 52.9 MB

## What this phase proves

The simulated acquisition/data path can process the configured 50/100/200 Hz
workloads for at least 30 minutes equivalent per wheel without dropping samples,
and it fails closed under explicit host/UI/storage fault injection.

## What this phase does NOT prove

This phase does **not** prove real-world zero packet loss, RF performance,
negotiated connection interval, physical MTU behavior, RSSI distribution,
LSM6DS3TR-C FIFO/INT timing, actual Left/Right start skew, or clock drift on two
real XIAO boards. Those measurements require the Phase 10 physical acceptance
matrix.
