# WheelAthlete Windows acquisition: Phase 1 audit

Status: implementation baseline for `codex/pc-version`
Audited release: WheelAthlete `v1.7.0` (`f6ad7d2`)
Primary hardware: two Seeed Studio XIAO nRF52840 Sense boards at 50/100/200 Hz

## Scope and evidence reviewed

The audit covered the complete tracked source inventory under `app/lib`,
`app/test`, `Xiao_firmware/src`, `Xiao_firmware/test`,
`M5plus2_firmware/src`, `M5plus2_firmware/test`, `tools`, `docs`, and the
existing `.project` plans. The critical flows inspected were:

- BLE discovery, dual connection, MTU request, serialized GATT operations,
  notification ownership, reconnect handling, and streaming preparation in
  `app/lib/ble/ble_repository.dart` and `app/lib/state/ble_providers.dart`.
- Packet parsing, wrap-aware sequence tracking, replay, sample fan-out, and
  presentation throttling in `app/lib/ble/imu_packet.dart`,
  `app/lib/ble/imu_batch_processor.dart`, `app/lib/state/sample_hub.dart`, and
  `app/lib/state/imu_presentation_buffer.dart`.
- Clock fit, scheduled start, START/STOP acknowledgement, bounded STOP retry,
  final acquisition health, session finalization, and single-wheel safeguards
  in `app/lib/state/sync_*`, `record_countdown_providers.dart`, and
  `recording_providers.dart`.
- Session models, topic/trial layout, metadata, preview, quality badges,
  protocols, experiment tracking, CSV/XLSX/ZIP export, and atomic folder
  export in `app/lib/records`, `app/lib/export`, and `app/lib/ui`.
- XIAO command lifecycle, batched BLE delivery, replay, health events, and its
  FreeRTOS IMU polling implementation in `Xiao_firmware/src`.
- Existing Bleak console and Tkinter/matplotlib clients in `tools`.
- Protocol and prior automated/physical-test evidence in `docs/ble-protocol.md`,
  `docs/data-collection-protocol.md`, and `docs/testing`.

## Findings

The mobile implementation is the reusable product shell. It already has an
abstract BLE repository, Riverpod state machines, immutable session models,
protocol templates, experiment tracking, browsing, preview, quality badges,
and exporters. Android must remain on `FlutterBluePlusBleRepository`.

The two Python PC programs are diagnostic utilities, not a safe acquisition
backend. They use wall-clock notification arrival as the synced timestamp,
append every sample to RAM, accept trailing bytes in a batch, send immediate
START commands one board after another, do not wait for START_FIRED or
STOP_FIRED, stop subscriptions before final queue/health reconciliation, and
write CSV as the only recording artifact. The GUI also holds a global lock
while copying plot buffers and redraws every 50 ms. They remain useful only as
manual BLE probes.

The XIAO currently uses FreeRTOS polling and six individual register reads,
then assigns `micros()` after the reads. `Bluefruit.configPrphConn(247, 10,
10, 10)` configures ATT MTU, SoftDevice event length, HVN queue size, and write
command queue size; its second argument is not a 10 ms connection interval.
The installed Bluefruit API exposes `requestConnectionParameter()` in units of
1.25 ms and `requestMtuExchange()`, so connection preferences can be requested
explicitly after connect. The actual negotiated values still require runtime
measurement.

The Seeed LSM6DS3 dependency must be checked against the exact installed
version before FIFO work. FIFO/interrupt code will not be added from guessed
APIs. Until hardware FIFO acquisition is built and measured, the existing
non-zero queue/transport counters are meaningful but the XIAO FIFO counters
must be described as unavailable rather than as proof of zero loss.

## Feature parity matrix

Legend: **Yes** = present in the current product path; **Partial** = present but
does not meet the new reliability contract; **No** = absent.

| Feature | Mobile v1.7.0 | Existing PC tools | New PC requirement | Shared code possible? |
|---|---|---|---|---|
| BLE scan | Yes, service/name filtered | Yes | Daemon scan with stable device events | UUIDs and discovery rules |
| Board discovery | Yes, reads Info | Partial, name then probing | Identify model, side, firmware, address | Info/config packet contract |
| Connect Left | Yes | Yes | Independent controlled state machine | Connection domain states |
| Connect Right | Yes | Yes | Independent controlled state machine | Connection domain states |
| Simultaneous dual-board connection | Yes | Yes, diagnostic | Concurrent links without shared data loss | Side assignment and UI cards |
| Board name | Yes | Partial | Display and configure | `BoardConfig` semantics |
| Wheel assignment | Yes | Read only | Display and configure safely | `WheelId` semantics |
| Sample-rate configuration | Yes, 50/100/200 | No | Configure before arm; record applied value | Control command semantics |
| Accelerometer range | Yes | Read scale only | Configure and record applied range | Info/config semantics |
| Gyro range | Yes | Read scale only | Configure and record applied range | Info/config semantics |
| Battery | Yes | Console only; GUI omits | Per-board live telemetry | Existing UI presentation |
| RSSI | Yes | Scan-time only | Poll and store distribution | Existing presentation rules |
| Connection status | Yes | Coarse global state | Per-board state and failure reason | Connection domain states |
| MTU visibility | Requested, not shown | No | Show and journal actual negotiated MTU | MTU threshold constant only |
| Connection-quality diagnostics | Partial | Partial counters | RSSI plus throughput, loss, queues, faults | Health terminology |
| Countdown | Yes | No | Preserve desktop workflow | Countdown UI/state concepts |
| Synchronized START | Yes, scheduled | No, immediate sequential | One PC T0 mapped to both devices | Sync math and command contract |
| Synchronized STOP | Partial, bounded ACK flow | No | Retry, ACK, drain, health reconciliation | STOP state semantics |
| START_FIRED handling | Yes | Ignored | Required from every armed wheel | Event parser semantics |
| STOP_FIRED handling | Yes | Ignored | Required before finalization or explicit failure | Event parser semantics |
| Live IMU | Yes | Yes | Throttled copy only | Physical units and wheel colors |
| Realtime graphs | Yes, presentation buffer | Yes, callback-adjacent | 10-20 Hz preview isolated from raw path | Flutter charts and decimation ideas |
| Recording | Yes, memory then CSV | CSV after RAM capture | Daemon-owned append journal | Session workflow only |
| Athlete/session metadata | Yes | No | Preserve plus board/link/sync provenance | `SessionConfig` fields |
| Topic | Yes | No | Preserve | Domain/storage UI |
| Trial number | Yes | No | Preserve | Domain/storage UI |
| Notes | Yes | No | Preserve | Domain/storage UI |
| Protocol templates | Yes | No | Preserve | Repository and UI |
| Experiment tracker | Yes | No | Preserve and desktop-size layout | Providers and UI |
| Session browser | Yes | No | Include complete/recovered sessions | Browse domain and UI |
| Session preview | Yes | No | Read journal-derived exports/previews | Stats and chart UI |
| Quality badges | Yes, sync residual | No | GOOD/WARNING/DEGRADED/INVALID with reasons | Badge presentation, new QC model |
| CSV export | Yes | Yes, authoritative | Generate after acquisition | CSV schema/export concepts |
| Excel export | Yes | No | Generate after acquisition | Existing exporter where compatible |
| Raw export | Yes, raw CSV/ZIP | No | Preserve authoritative binary journal | Export workflow only |
| Error messages | Yes | Console/status string | Typed actionable errors, no silent discard | UI state views |
| Acquisition-health diagnostics | Yes, recording-focused | Partial | Full per-board and writer telemetry | ACQ_HEALTH parser semantics |
| Queue drops | Yes | Yes | Firmware and every host queue separately | Names and firmware counters |
| Transport failures | Yes | Yes | Firmware plus host I/O failures | Firmware event field |
| FIFO faults | Yes for telemetry-capable firmware | No | Real values or explicitly unavailable | Event field only |
| Effective sampling rate | Yes | Yes | Rolling and final device-time rate | Stats presentation |
| Sequence gaps | Yes with replay | Yes, simplistic | Gap/duplicate/reorder/wrap classification | Parser test cases |
| Synchronization quality | Yes, offset/drift residual | No | RTT, offset, drift, mapped skew, confidence | `SyncPoint`, fit, quality UI concepts |

## Target architecture

```text
XIAO L ---- BLE ----\
                    > Python 3 / Bleak acquisition daemon
XIAO R ---- BLE ----/       |
                              +-- per-board bounded callback queue
                              +-- strict packet parser / sequence validator
                              +-- append-only journal writer
                              +-- sync and dual-board lifecycle controller
                              +-- health/QC/recovery
                              +-- throttled preview publisher
                                       |
                          versioned localhost TCP NDJSON
                                       |
                              Flutter Windows UI
```

### Process boundary and IPC

Use localhost TCP with newline-delimited JSON. Python `asyncio` and Dart
`dart:io` both provide it without another dependency; Windows named pipes add
platform code and WebSockets add protocol machinery that is not needed for a
single local client. Every message carries `protocol_version`, `type`,
`request_id` when applicable, and a validated object payload. The first
message is a version handshake. Unknown versions, commands, fields that exceed
size limits, and invalid state transitions are rejected explicitly.

Commands: `scan`, `connect`, `disconnect`, `configure`, `sync`, `arm`,
`scheduled_start`, `stop`, `status`, `start_record`, `end_record`, and
`recover`. Events: `device_found`, `connection_state`, `sample_preview`,
`imu_summary`, `sync_status`, `health`, `recording_state`, and `error`.
Raw samples never cross IPC.

### Lossless path and concurrency

The Bleak callback validates only board identity and enqueues an immutable
payload with `time.monotonic_ns()`. Each board has its own bounded queue and
consumer. A full queue never overwrites unread data: it raises a critical
fault, preserves the session, and makes final QC INVALID.

The consumer performs strict batch-length validation, parsing, and sequence
classification, then submits fixed records to a dedicated journal writer. A
sample becomes visible to preview consumers only after the writer accepts it.
The writer owns the file, batches writes, flushes at bounded intervals, tracks
backlog/high-water/latency, and fsyncs at lifecycle checkpoints. UI preview is
decimated to 10 Hz per wheel from a copy and may be dropped without affecting
the journal.

### Journal and crash recovery

The authoritative session is an append-only, versioned binary journal. It has
a magic/version header, length-prefixed records, and a checksum per record.
Record kinds cover session metadata, board/link configuration, raw sample,
sync observation, lifecycle acknowledgement, health snapshot, error, and
finalization. Each raw sample preserves session ID, side, sequence,
device-time microseconds, PC monotonic receive nanoseconds, raw six-axis
values, and packet ID.

Recording starts in an `.open` journal. Clean STOP appends final health and a
finalization record, flushes/fsyncs, then atomically renames it to `.waj`.
Startup scans only the journal root for `.open` files, validates complete
records to the last checksum, and offers recovery without deleting partial
data. CSV/XLSX are derived artifacts.

### Synchronization and lifecycle

Use `time.monotonic_ns()` as the PC master. For each board, collect repeated
round trips, reject high-RTT observations, unwrap the device uint32 clock, and
fit `pc_ns = a * device_us * 1000 + b`. Arm both boards against one future PC
T0, send each converted device target before T0, and require START_FIRED from
both. During normal recording send no periodic control traffic. Perform a
post-stop sync set to estimate drift and map both START/STOP events to the PC
timeline.

STOP is a state machine: quiesce nonessential control traffic, bounded write
retry, await STOP_FIRED, allow firmware drain, await final ACQ_HEALTH,
reconcile produced/notified/received, finalize the journal, then calculate QC.
One-wheel failure never discards the other wheel.

### QC contract

- **GOOD:** zero sequence gaps after recovery, queue drops, FIFO loss, and
  critical transport failures; produced = notified = received; effective rate
  within tolerance; start skew below one sample period.
- **WARNING:** complete data with a non-critical rate/sync/diagnostic warning.
- **DEGRADED:** usable partial data or an unconfirmed lifecycle/health value.
- **INVALID:** known missing/malformed/out-of-order unrecovered data, host
  overflow, FIFO loss, critical transport failure, or failed required sync.

Every non-GOOD state stores machine-readable reason codes and human-readable
details. No quality state is inferred from RSSI alone.

## Delivery boundaries

- Keep Android on the current mobile backend and preserve all mobile tests.
- Keep Tkinter/matplotlib as developer diagnostics only.
- Do not change the BLE wire format without a versioned compatible reader.
- Do not claim actual MTU, connection interval, FIFO behavior, clock skew, or
  zero-loss hardware performance until observed on two physical XIAO boards.
- Do not mix model training or dataset processing into this branch.
