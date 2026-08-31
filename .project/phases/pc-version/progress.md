# PC Version — Progress

Updated: 2026-09-01 (Asia/Bangkok)
Active branch: `codex/pc-version`

## Non-negotiable branch constraint

The user explicitly instructed on 2026-09-01 that this work must **never be
put into `main`**. All current work and commits remain on `codex/pc-version`.
No merge, rebase, reset, push, force-update, or other mutation of `main` is part
of this task.

## Completed phases

- Phase 1 `b970b69`: parity/architecture baseline.
- Phase 2 `8d0d0a9`: XIAO link/timing hardening; coherent 12-byte IMU burst,
  explicit connection-parameter request, diagnostics, `15 passed`, LEFT/RIGHT
  firmware builds green. FIFO activation remains hardware-gated.
- Phase 3 `857a164`: strict headless dual-board ingestion core with independent
  per-wheel bounded queues, strict packet parsing, sequence classification and
  non-overwriting fail-closed overflow behavior.
- Phase 4 `da6249a`: monotonic PC clock mapping, low-RTT sync fit, scheduled
  common-T0 start, START_FIRED/STOP_FIRED acknowledgements, STOP retry and
  disconnect failsafe. Added Windows host-timer slack without changing measured
  synchronization evidence.
- Phase 5 `118e1bc`: crash-safe append-only `.waj` journal, CRC validation,
  recovery, atomic finalization, derived CSV and fail-closed session QC.
- Phase 6 `a8927ae`: versioned localhost Python daemon ↔ Flutter Windows IPC;
  raw samples remain daemon-owned and only throttled preview/status cross IPC.
- Phase 7 `4b4aef9`: mobile backend boundary proven unchanged; Android still
  uses `FlutterBluePlusBleRepository` and desktop daemon remains opt-in.
- Phase 8 `083d7c8`: Windows operator shell + observability:
  - Dashboard / Connect / Live / Record / Experiments / Sessions / Diagnostics;
  - per-board name, firmware, RSSI, battery, MTU, configured/effective rates;
  - host queue depth/high-water/overflow, sequence gaps/duplicates/out-of-order,
    firmware produced/notified/drop/transport/FIFO health and clock-fit data;
  - 1 Hz status polling and bounded ~10 Hz preview history only;
  - Record flow configures every connected board to selected 50/100/200 Hz
    before recording;
  - protocol-template ID/tags preserved in journal metadata;
  - atomic `.summary.json`, PC session listing/search, CSV derivation, recovery
    and diagnostic report export;
  - Windows `main()` selects desktop shell while the default constructor keeps
    the existing mobile `HomePage`.

## Phase 9 — completed automated stress/fault work

Phase 9 closes the major simulated reliability risks without claiming physical
BLE/RF success.

### 1. 30-minute-equivalent dual-wheel simulations

`tools/pc_acquisition/tests/test_stress_simulation.py` runs both wheels with
12-sample batched notifications at all supported rates:

- 50 Hz: 90,000 samples/wheel, 180,000 total, 7,500 notifications/wheel;
- 100 Hz: 180,000 samples/wheel, 360,000 total, 15,000 notifications/wheel;
- 200 Hz: 360,000 samples/wheel, 720,000 total, 30,000 notifications/wheel.

Every simulated run requires exact sample/notification counts and:

- sequence gaps = 0;
- duplicates = 0;
- out-of-order = 0;
- malformed packets = 0;
- host queue overflow = 0;
- no fatal ingestion fault;
- empty queues after drain;
- preview bounded to approximately 10 Hz rather than becoming the raw path.

### 2. Notification burst test

A no-yield 400-notification burst per wheel is injected into the independent
512-notification queues. At 12 samples/notification this represents 4,800
samples per wheel. The complete burst is retained with no sequence loss or queue
overflow.

### 3. Authoritative journal long-run stress

The writer processes a dual-wheel 200 Hz, 30-minute-equivalent dataset:

- 360,000 samples/wheel;
- 720,000 raw samples total;
- 4,096-sample bounded writer queue;
- 720,002 valid finalized journal records including metadata/finalize;
- CRC/frame validation clean;
- no journal queue overflow;
- no writer fatal fault.

### 4. Slow-disk backpressure fault

The journal writer is deliberately slowed. When its bounded queue fills:

- the next sample is rejected rather than overwriting an unread sample;
- `journal_queue_overflow` increments;
- a fatal acquisition fault is set;
- every sample accepted before the boundary still drains to disk;
- the partial journal remains structurally valid.

### 5. Disk-write exception fault

A sample write is forced to raise `OSError`. The writer records
`journal_write_failure`, preserves a structurally parseable journal, and QC now
marks the session invalid instead of allowing a silent GOOD result.

### 6. Journal-vs-host integrity QC

`end_record` now waits for the journal writer queue to become idle before QC.
QC compares authoritative disk count against host-received count:

`journal samples written == sum(host samples received)`

Any mismatch produces `journal_count_mismatch = INVALID`. Any writer fatal fault
produces `journal_writer_fault = INVALID`. Final summary metadata includes
samples-written, writer queue high-water, queue-overflow count, max write
latency and fatal-fault details.

### 7. Slow/frozen Flutter UI isolation

PC preview IPC now has a bounded 256 KiB write-buffer threshold:

- raw IMU data never crosses IPC;
- `sample_preview` is disposable/best-effort;
- a slow UI drops preview only and increments a visible counter;
- preview does not await socket `drain()`;
- lifecycle/error/command traffic remains reliable/drained;
- Diagnostics shows clients, previews sent/dropped, max buffer and limit;
- exported diagnostic JSON also contains IPC isolation counters.

### 8. Phase 9 verification results

Latest source-tree gates:

- `python -m pytest tools/pc_acquisition/tests -q`
  - **31 passed in 22.09 s**
- focused journal/QC/backpressure set
  - **10 passed in 11.89 s**
- final stress/backpressure subset before QC integration
  - **7 passed in 18.60 s**
- `flutter test test/desktop`
  - **8 passed**
- `dart analyze lib test/desktop`
  - **No issues found**
- complete `flutter test`
  - **645 passed**
- `python -m compileall -q tools/pc_acquisition`
  - clean
- `python -m pytest Xiao_firmware/test -q`
  - **15 passed in 0.12 s**
- `pio run -e left`
  - SUCCESS; RAM 25,772/237,568 B (10.8%), Flash 147,128/811,008 B (18.1%)
- `pio run -e right`
  - SUCCESS; same RAM/Flash footprint
- `flutter build apk --release`
  - SUCCESS; `app-release.apk` ≈ **52.9 MB**

Detailed evidence: `docs/testing/pc-version-phase-09.tdd.md`.

## Windows release-build environment blocker

Rechecked using `flutter doctor -v` on 2026-09-01:

- Flutter stable 3.41.9 / Dart 3.11.5: OK;
- Android SDK/toolchain: OK;
- Windows desktop device: detected;
- **Visual Studio: not installed**;
- Flutter requires Visual Studio with the **Desktop development with C++**
  workload for Windows builds.

Therefore `flutter build windows --release` cannot currently be used as build
evidence on this host. This is an environment/toolchain blocker. No system-wide
Visual Studio installation has been performed automatically.

## Current phase

Automated implementation Phases 0–9 are complete. The remaining work that can
be done without hardware is to prepare the Phase 10 physical acceptance harness
and report format. After that, actual execution remains blocked until two real
XIAO nRF52840 Sense boards are connected.

## Phase 10 physical evidence still blocked

No physical board evidence is claimed yet for:

- flash/boot success of the modified firmware;
- negotiated MTU and connection interval on the actual Windows controller;
- RF throughput or packet-loss behavior at 0.5 m / 2 m / 5 m;
- LSM6DS3TR-C INT1/FIFO behavior;
- real 50/100/200 Hz effective rate;
- real dual-wheel `produced == notified == received == journal-written`;
- real Left/Right start skew;
- real sync RTT/clock drift;
- 2/10/30-minute physical recordings;
- 20-cycle physical Start/Stop test.

Those claims must remain blocked until measured on two real boards.
