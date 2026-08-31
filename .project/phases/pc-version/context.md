# PC Version — Context / Decisions

## Task

Build a Windows WheelAthlete data-acquisition path with practical feature
parity with the Flutter mobile app, while prioritizing:

1. zero missing samples
2. accurate Left/Right synchronization
3. accurate device-derived timestamps
4. deterministic start/stop
5. integrity, recovery, and diagnostics
6. long-recording stability
7. usability and live visualization

The detailed user input remains at `pc-version-promt.txt`. The implementation
branch is `codex/pc-version`.

## Architecture decision

- A headless Python/Bleak process owns both Windows BLE connections, parses and
  validates notifications, writes an append-only raw journal, performs clock
  mapping/QC, and exposes localhost IPC.
- Flutter Windows is the UI and workflow layer; UI rendering is never in the
  lossless ingestion path.
- IPC is versioned localhost TCP with NDJSON so Python asyncio and Dart `dart:io`
  can communicate without a WebSocket or named-pipe dependency.
- Android keeps its existing native Flutter BLE backend.
- Existing Tkinter/matplotlib tools remain developer diagnostics only.

## Hardware constraint

No physical XIAO nRF52840 Sense boards are currently available. Internet and
source-code verification may proceed, but flash, negotiated-link, interrupt,
FIFO, radio-throughput, and two-board acceptance claims remain blocked until
real hardware is available.

## Firmware decisions

- Bluefruit `configPrphConn(247, 10, 10, 10)` is MTU/event-length/queue
  configuration; its second argument is not a 10 ms connection interval.
- Request a 10 ms interval explicitly with 8 BLE interval units, MTU 247, zero
  slave latency, and a 4 second supervision timeout.
- Read gyro + accelerometer output registers in one 12-byte burst with BDU and
  auto-increment enabled; use the I2C transaction midpoint as `t_device_us`.
- Count/log burst read failures instead of returning stale component values.
- The LSM6DS3TR-C and XIAO wiring support FIFO/INT1, but FIFO pattern alignment,
  watermark routing, timestamp reconstruction, and overflow accounting are
  hardware-gated. Do not enable FIFO acquisition until these are observed on
  the real board.

## Data-path decision

The PC BLE callback is not allowed to parse samples, update UI, write exports,
or block on disk. It only captures an immutable notification plus a monotonic
arrival timestamp and performs a non-overwriting enqueue into that board's
bounded queue. Overflow is a critical acquisition fault. Downstream consumers
own strict parsing, sequence validation, journaling, and preview decimation.
