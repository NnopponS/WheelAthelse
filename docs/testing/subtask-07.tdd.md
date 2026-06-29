# Subtask #7 — TDD Evidence Report

## Scope
Flutter: clock sync engine — offset estimation, drift correction, synchronized
start, Sync event parsing, Control command encoding.

## What was built

### Pure logic (host-testable, no Flutter/BLE)
- `app/lib/ble/sync_packet.dart`:
  - `SyncEvent.parse(bytes)` — parses Sync notify payloads `[event_id][payload]`
    (verified against firmware `ble_service.cpp:handleSyncPing` which prepends
    event_id via `packSyncEvent`). Sealed class hierarchy:
    - `SyncResponseEvent` (0x00): 13B `[0x00][t_app_ms u32@1][t_device_us u32@5][seq_ping u32@9]`
    - `DropCountEvent` (0x10): 5B `[0x10][count u32@1]`
    - `CmdNackEvent` (0x20): 2B `[0x20][cmd u8@1]`
    - `StartFiredEvent` (0x30): 5B `[0x30][t_device_us u32@1]`
    - `StopFiredEvent` (0x40): 9B `[0x40][t_device_us u32@1][last_seq u32@5]`
  - Throws `ArgumentError` on empty/truncated buffers, `FormatException` on
    unknown event_id.
- `app/lib/ble/control_command.dart`:
  - `ControlCommand.*` encoders for all §3.1 commands:
    - `start(targetStartUs)` → `[0x01][u32 LE]` (5B)
    - `stop()` → `[0x02]` (1B)
    - `setRate(rateHz)` → `[0x03][u16 LE]` (3B, validates 50/100/200)
    - `syncPing(tAppMs)` → `[0x04][u32 LE]` (5B)
    - `setRange(accelRange, gyroRange)` → `[0x05][u8][u8]` (3B, validates 0–3)
    - `beep(count, periodMs)` → `[0x06][u8][u16 LE]` (4B, validates count > 0)
    - `resetSeq()` → `[0xFF]` (1B)
- `app/lib/state/sync_engine.dart`:
  - `OffsetEstimate.compute(t1AppMs, t2DeviceUs, t3AppMs)` — NTP-lite offset
    per §4.2: `RTT = T3 - T1`, `offset = T2 - (T1*1000 + RTT_us/2)`.
  - `MinRttTracker` — keeps the estimate with lowest RTT across N pings (§4.2).
  - `DriftFit.fit(points)` — ordinary least squares linear regression
    `t_app_ms = slope * t_device_us + intercept` per §4.3. Returns slope,
    intercept, residual RMS (sync quality metric), n. `toSyncedMs(tDeviceUs)`
    maps device timestamps to the common phone timeline.
  - `ScheduledStart.compute(tStartPhoneMs, tAppRefMs, offsetUs, tDeviceRefUs)`
    — converts phone start time to device-local micros per §3.2 formula.

### State layer (Riverpod)
- `app/lib/state/sync_providers.dart`:
  - `WheelSyncState` — per-side: syncing, offset, driftFit, pendingPing,
    dropCount, lastStartFiredUs, lastStopFiredUs, lastSeq, error.
  - `SyncEngineNotifier` — orchestrates:
    - `sendPing(side)`: writes SYNC_PING, records T1 (relative to first ping
      to fit uint32), waits for Sync response to compute offset.
    - `startListening(side)`: subscribes to `BleRepository.syncData`, dispatches
      to `_handleEvent` for each SyncEvent subclass.
    - `sendStart/sendStop/sendResetSeq(side)`: write Control commands.
  - Uses relative timestamps (`now - tAppRefMs`) so `t_app_ms` fits in the
    protocol's uint32 field (absolute Unix epoch ms overflows uint32 in 2026).

### BLE repository extension
- `app/lib/ble/ble_repository.dart`:
  - Added `Stream<List<int>> syncData(String deviceId)` to abstract interface.
  - Added `Future<void> writeControl(String deviceId, List<int> bytes)`.
  - `FlutterBluePlusBleRepository`: syncData resolves Sync characteristic from
    `servicesList`, enables notify, forwards `lastValueStream` via broadcast
    controller. writeControl writes to Control characteristic.
  - `FakeBleRepository`: syncData returns `sync: true` broadcast controller
    per device. `syncController(deviceId)` exposes it for test injection.
    `lastControlWrite(deviceId)` records the last written command bytes.

## TDD workflow
1. RED: `test/ble/sync_packet_test.dart` (13 tests) — all 5 event types,
   truncation errors, unknown event_id, uint32 max values.
2. GREEN: `sync_packet.dart` — all 13 pass.
3. RED: `test/ble/control_command_test.dart` (13 tests) — all 7 commands,
   validation errors, constant values.
4. GREEN: `control_command.dart` — all 13 pass.
5. RED: `test/state/sync_engine_test.dart` (18 tests) — offset computation
   (zero/positive/negative), MinRttTracker, DriftFit (perfect/offset/drift/
   noise/too-few-points/toSyncedMs), ScheduledStart (normal/negative/immediate).
6. GREEN: `sync_engine.dart` — all 18 pass.
7. RED: `test/state/sync_providers_test.dart` (15 tests) — sendPing, sync
   response round trip, min-RTT tracking, drift fit accumulation, START_FIRED/
   STOP_FIRED/DROP_COUNT/CMD_NACK events, sendStart/sendStop/sendResetSeq,
   not-connected error, dispose, malformed event.
8. GREEN: extended `ble_repository.dart` + implemented `sync_providers.dart`
   — all 15 pass.

## Test results
- `flutter analyze`: **clean** (0 issues)
- `flutter test`: **204/204 PASS** (was 145 before #7; +59 new tests)
  - `test/ble/sync_packet_test.dart`: 13 tests
  - `test/ble/control_command_test.dart`: 13 tests
  - `test/state/sync_engine_test.dart`: 18 tests
  - `test/state/sync_providers_test.dart`: 15 tests
- Coverage (new files):
  - `lib/ble/sync_packet.dart`: **95.5%** (42/44 lines)
  - `lib/ble/control_command.dart`: **100%** (34/34 lines)
  - `lib/state/sync_engine.dart`: **100%** (48/48 lines)
  - `lib/state/sync_providers.dart`: **92.6%** (100/108 lines)
  - `lib/ble/ble_repository.dart`: 100% of testable lines

## Bugs caught by TDD
- **uint32 overflow**: `DateTime.now().millisecondsSinceEpoch` in 2026
  (~1.78e12) overflows the protocol's uint32 `t_app_ms` field (max ~4.29e9).
  Fixed by using relative timestamps (`now - tAppRefMs`) in the notifier.
- **Test offset expectations**: assumed RTT=0 with sync controller, but
  `await writeControl` adds ~4ms. Fixed test to use range-based assertions.
- **First ping t_app_ms=0**: relative timestamp is 0 on the first ping.
  Fixed test to accept `>= 0` instead of `> 0`.
- **`copyWith` sentinel pattern**: `PendingPing?` parameter with `Object _unset`
  default requires `Object?` type, not `PendingPing?`.
- **Unused `seqPing` in pattern**: destructured but not used → analyzer warning.
  Removed from pattern.
- **Dangling library doc comment**: `///` before first declaration without
  `library;` directive. Added `library;`.
- **Fake repos missing new abstract methods**: `_ThrowingBleRepository` and
  `_ErrorScanBleRepository` in `connection_manager_test.dart` needed
  `syncData` + `writeControl` stubs.

## Skills used
dart-flutter-patterns, tdd-workflow, gateguard, latency-critical-systems,
intent-driven-development, verification-loop
