# PC version Phase 3 — headless ingestion evidence

## RED -> GREEN

- RED: the first ingestion test collection failed because
  `tools.pc_acquisition.engine` did not exist.
- GREEN: `python -m pytest tools/pc_acquisition/tests/test_ingestion_core.py -q`
  reports `5 passed`.
- STATIC: `python -m compileall -q tools/pc_acquisition` succeeds.

## Implemented guarantees

- IMU notifications are strict: count must be 1..12 and payload length must be
  exactly `1 + count * 20`. Truncation and trailing bytes are rejected.
- Every BLE callback creates an immutable payload envelope with a PC monotonic
  arrival timestamp and performs only a non-blocking queue insertion.
- Left and Right use independent bounded `asyncio.Queue` instances and workers.
  No global cross-wheel processing order is assumed.
- Queue overflow never overwrites unread data. It records a fatal
  `host_ingestion_queue_overflow` fault for final QC.
- Sequence tracking distinguishes first/contiguous/gap/duplicate/out-of-order
  and remains correct across uint32 wrap.
- The authoritative sample sink receives every parsed sample. Preview delivery
  is decimated separately and may be dropped without changing raw ingestion.
- A production `BleakTransport` provides the WinRT-facing boundary while a
  deterministic `FakeBleTransport` allows all automated tests to run without
  Bluetooth hardware.

## Hardware gate

No Windows BLE connection was opened in this phase. The Bleak adapter is an
API boundary and compile-tested Python code, not evidence of negotiated MTU,
radio reliability, or two-board physical throughput.
