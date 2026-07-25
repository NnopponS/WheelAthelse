# BLE sustained reliability v1.4 TDD evidence

## Root causes

1. The M5 dedicated BLE task existed as a function but was never created, so
   queue draining depended on the display/button loop.
2. M5 Control callbacks could execute STOP/final flush concurrently with live
   batch transmission.
3. Flutter copied up to 300 chart samples for every incoming IMU sample before
   the recording listener ran, creating allocation and main-isolate backlog.
4. M5 display battery reads and XIAO averaged ADC reads could perform
   nonessential power telemetry work in the acquisition path.
5. Sync and battery stream cancellation removed the wrong repository cache.
6. M5 used NimBLE-Arduino's `void notify()` wrapper, so host congestion or
   allocation failures cleared live batches without a usable result code.

## RED

- `imu_presentation_buffer_test.dart` did not compile because the bounded O(1)
  presentation buffer did not exist.
- M5 ownership tests found two `bleTask()` call sites, then proved the intended
  sole task was dormant because `xTaskCreatePinnedToCore` was absent.
- M5 command serialization test failed because Control callbacks called
  `handleCommand` directly and no FreeRTOS control queue existed.
- M5 battery test found a direct `M5.Power.getBatteryLevel()` read in the
  high-frequency display loop.
- XIAO telemetry test found no acquisition guard before its blocking ADC loop.
- M5 notify-retention test proved a failed transport attempt could not retain
  its pending live/replay batch; the first result-aware implementation also
  exposed that NimBLE-Arduino 1.4.x discards the underlying host return code.

## GREEN

- M5 uses one created Core 1 streaming task and a bounded Control command queue.
- Flutter chart ingestion is O(1); ordered chart snapshots are created at 10 Hz.
- A sustained fake-BLE test delivers 4,000 samples per side at 200 Hz semantics
  and verifies all 8,000 reach the recording buffer.
- Battery ADC work is deferred during acquisition and the M5 screen uses the
  cached battery value.
- M5 sends IMU batches through the result-returning NimBLE host API and clears
  live/replay state only after successful queueing; transport failures remain
  pending for retry and are counted separately.
- Both firmware targets alternate live and replay batches during acquisition,
  preventing gap recovery from starving current samples at small MTUs.
- Targeted Flutter, firmware host, and left/right firmware build verification
  completed: 18 focused Flutter tests, 608 full Flutter tests, 81.48% line
  coverage, 122 M5 host tests, and 4 XIAO host tests.
- Flutter analysis of `lib/` is clean. Release builds succeeded for the Android
  APK and the left/right M5 and XIAO firmware targets.
- Physical dual-board acceptance remains required because no Android/ADB test
  device was attached during this verification run.
