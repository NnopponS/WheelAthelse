# PC version Phase 2 firmware evidence

## RED -> GREEN

- RED: `python -m pytest test/test_pc_link_and_timing_contract.py -q`
  reported `3 failed` before the link and timing changes.
- GREEN: `python -m pytest test -q` reports `15 passed`.
- BUILD: `pio run -e left -e right` reports both environments successful.
  Each image uses 25,772 bytes RAM and 147,128 bytes flash.

## Implemented guarantees

- `configPrphConn(247, 10, 10, 10)` is documented according to the installed
  Bluefruit API: MTU, SoftDevice event length, HVN queue, and write queue. Its
  second argument is not treated as a connection interval.
- On connect, the peripheral requests MTU 247, a 10 ms interval (8 BLE units),
  zero slave latency, and a 4 second supervision timeout.
- One second after connection, serial diagnostics print the negotiated MTU,
  connection interval, and supervision timeout from `BLEConnection`.
- IMU gyro and accelerometer output registers are read in one 12-byte burst.
  The device timestamp is the midpoint of that I2C transaction, and read
  failures are counted and logged.

## Deliberate hardware gate

The installed Seeed LSM6DS3 library exposes FIFO data/status registers, and the
XIAO Sense wiring exposes IMU INT1. FIFO mode is deliberately not enabled in
this checkpoint because sample pattern ordering, watermark interrupt behavior,
timestamp reconstruction, and overflow accounting have not been observed on a
physical board. Enabling it without that evidence would make the acquisition
path less trustworthy, not more.

The existing zero FIFO counters therefore mean "FIFO acquisition disabled",
not measured proof of zero FIFO loss. Physical FIFO work remains part of the
Phase 10 hardware gate.

No firmware was flashed in this phase. Build success does not prove negotiated
parameters, timestamp accuracy, FIFO behavior, or dual-board radio throughput.
