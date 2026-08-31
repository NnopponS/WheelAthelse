# PC Version — Context / Decisions

## Task

Build a Windows WheelAthlete data-acquisition path with practical feature
parity with the mobile app while prioritizing:

1. zero missing samples;
2. accurate Left/Right synchronization;
3. accurate device-derived timestamps;
4. deterministic start/stop;
5. integrity, recovery, and diagnostics;
6. long-recording stability;
7. usability and complete realtime visibility.

The detailed initial prompt remains at `pc-version-promt.txt`. Active
implementation branch: `codex/pc-version`.

## Branch safety — hard constraint

- All PC-version implementation, tests, tracker updates and commits stay on
  `codex/pc-version`.
- **Do not merge, rebase, reset, force-update, push, or otherwise modify
  `main` as part of this task.**
- The user explicitly prohibited putting this work into `main` on 2026-09-01.
- Before every commit/final verification, confirm the active branch is still
  `codex/pc-version`.

## Authoritative acquisition architecture

- A headless Python/Bleak process owns both Windows BLE connections.
- It owns strict notification parsing, per-wheel bounded queues, sequence
  classification, clock mapping, scheduled START/STOP, `.waj` journaling,
  recovery and final QC.
- Raw IMU samples are never owned by a UI process.
- UI processes communicate over versioned localhost TCP/NDJSON.
- Lifecycle/error/command traffic is reliable; `sample_preview` is disposable
  display telemetry.
- Android/mobile keeps its existing FlutterBluePlus implementation.

## PC UI choices

Two PC UIs now coexist and use the same acquisition daemon:

### Flutter Windows UI

- retained for Flutter/mobile workflow parity;
- implemented in Phase 8;
- Windows release packaging remains blocked on this host because Visual Studio
  `Desktop development with C++` is not installed.

### Python Research Edition

Added after the user requested a simpler and maximally stable PC research app.
Decisions:

- use PySide6 for native Windows UI;
- use QtCharts for the ~10 Hz display path;
- do not add PyQtGraph because QtCharts is already present and 10 Hz preview
  does not justify another dependency;
- use Qt `QTcpSocket` for event-driven localhost IPC;
- keep the GUI and DAQ in separate processes even though both are Python;
- use only six operator pages: Dashboard, Live, Record, Experiments, Sessions,
  Diagnostics;
- fold board connection/settings into Dashboard to reduce navigation burden;
- render only bounded ~10 Hz preview history; never send raw 50/100/200 Hz
  data through Qt;
- if the UI closes during an active recording, leave the DAQ daemon alive so
  UI lifecycle cannot terminate the authoritative session;
- provide `--demo` with unmistakable `DEMO DATA` labeling and prohibit demo
  data from becoming research evidence.

## Firmware decisions

- Bluefruit `configPrphConn(247, 10, 10, 10)` is MTU/event-length/queue
  configuration; the second argument is not a 10 ms connection interval.
- Request a 10 ms connection interval explicitly, MTU 247, zero slave latency,
  and a 4 second supervision timeout.
- XIAO IMU release path reads gyro+accelerometer coherently in one 12-byte
  register burst with BDU/auto-increment and midpoint timestamping.
- FIFO/DRDY remains hardware-gated until pattern alignment, watermark behavior,
  timestamp reconstruction and overflow accounting are measured on real XIAO
  hardware.
- Firmware resets sequence numbering at each START; the PC host therefore
  resets its sequence epoch at each recording boundary after draining previous
  notifications.

## Sensor range / scale decision

`SET_RANGE` changes both range codes and raw→physical conversion scales. The
acquisition service must not infer or locally fabricate new scale values.
After SET_RANGE it re-reads the firmware Info characteristic, verifies wheel
identity, and stores the firmware-authoritative range/scale values before
reporting success. This keeps realtime g and deg/s values correct immediately
without requiring reconnect.

## Data-path decision

The Windows BLE callback is not allowed to parse samples, update UI, write
exports, or block on disk. It captures immutable notification bytes plus a PC
monotonic arrival timestamp and attempts a non-overwriting enqueue into that
wheel's bounded queue. Overflow is a critical acquisition fault.

Downstream workers own strict parsing, sequence validation, journaling, health
and preview decimation.

## IPC / UI backpressure decision

- Raw samples never cross the IPC boundary.
- `sample_preview` is explicitly best-effort.
- Preview can be dropped for a slow/frozen client at the bounded socket-buffer
  threshold and the drop count is visible in Diagnostics.
- Lifecycle, errors and command responses remain reliable/drained traffic.
- A GUI rendering problem must therefore not create data loss in the
  authoritative BLE → parser → journal path.

## Journal / QC decision

- `.waj` is the source of truth;
- CSV is derived after acquisition;
- writer queue is bounded and never silently overwrites unread samples;
- writer faults/count mismatch invalidate the session;
- STOP waits for accepted journal work to settle before final QC;
- final QC compares host, firmware and journal evidence where available;
- incomplete `.open` files are recoverable only to the last structurally valid
  CRC-framed record.

## Hardware constraint

No physical two-XIAO evidence is available in this environment. Automated tests
may prove software behavior but must not be promoted to claims about physical
RF throughput, negotiated link behavior, real L/R start skew, clock drift,
FIFO/INT1, or zero-loss recordings at 0.5/2/5 m.

Phase 10's physical acceptance plan/harness is ready; execution remains BLOCKED
until two real XIAO nRF52840 Sense boards are attached.
