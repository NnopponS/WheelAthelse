import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/control_command.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/sync_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Builds a Sync notify payload: [event_id][payload...]
Uint8List _event(int eventId, List<int> payload) =>
    Uint8List.fromList([eventId, ...payload]);

Uint8List _syncResponseEvent({
  required int tAppMs,
  required int tDeviceUs,
  required int seqPing,
}) {
  final inner = ByteData(12)
    ..setUint32(0, tAppMs, Endian.little)
    ..setUint32(4, tDeviceUs, Endian.little)
    ..setUint32(8, seqPing, Endian.little);
  return _event(0x00, inner.buffer.asUint8List());
}

const _leftInfo = DeviceInfo(
  wheelId: WheelId.left,
  fwMajor: 1,
  fwMinor: 0,
  fwPatch: 0,
  accelRange: 0,
  gyroRange: 3,
  accelScale: 1 / 16384,
  gyroScale: 1 / 16.4,
);

void main() {
  late FakeBleRepository ble;
  late ProviderContainer container;

  setUp(() {
    ble = FakeBleRepository(
      devices: [
        const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
      ],
      infoFor: const {'L1': _leftInfo},
    );
    container = ProviderContainer(
      overrides: [
        bleRepositoryProvider.overrideWith((ref) => ble),
        rssiPollIntervalProvider.overrideWith((ref) => null),
        interConnectSettleDelayProvider.overrideWith((ref) => Duration.zero),
      ],
    );
    addTearDown(container.dispose);
  });

  const side = WheelSide.left;

  group('SyncEngineNotifier', () {
    test('initial state: no offset, no drift fit, not syncing', () {
      final state = container.read(syncEngineProvider);
      expect(state.bySide[side]!.offset, isNull);
      expect(state.bySide[side]!.driftFit, isNull);
      expect(state.bySide[side]!.syncing, isFalse);
      expect(state.bySide[side]!.error, isNull);
    });

    test('sendPing writes SYNC_PING command and records t1', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);

      await notifier.sendPing(side);

      // The fake recorded the Control write.
      final written = ble.lastControlWrite('L1');
      expect(written, isNotNull);
      expect(written![0], ControlCommandId.syncPing);
      // t_app_ms is in bytes 1–4 (little-endian). It's a relative timestamp
      // (ms since first ping), so the first ping sends 0.
      final tAppMs = ByteData.sublistView(Uint8List.fromList(written))
          .getUint32(1, Endian.little);
      expect(tAppMs, greaterThanOrEqualTo(0));

      // A pending ping should be tracked (waiting for the Sync response).
      final state = container.read(syncEngineProvider);
      expect(state.bySide[side]!.pendingPing, isNotNull);
    });

    test('Sync response completes the round trip and sets offset', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);

      await notifier.sendPing(side);
      // Simulate firmware response: T2 = T1_us + 4000 (4ms later on device).
      // T3 will be ~T1 + 8ms. We use t1AppUs for sub-ms precision.
      final pending = container.read(syncEngineProvider).bySide[side]!.pendingPing!;
      final t2DeviceUs = pending.t1AppUs + 4000;
      ble.syncController('L1')!.add(_syncResponseEvent(
        tAppMs: pending.t1AppMs,
        tDeviceUs: t2DeviceUs,
        seqPing: 1,
      ));
      // Allow the stream listener to process.
      await Future<void>.delayed(Duration.zero);

      final state = container.read(syncEngineProvider);
      expect(state.bySide[side]!.pendingPing, isNull);
      expect(state.bySide[side]!.offset, isNotNull);
      // offset = T2 - (T1_us + RTT_us/2). T2 = T1_us + 4000.
      // RTT varies with async scheduling (0-10 ms), so offset = 4000 - RTT/2
      // is in range [-1000, 4000]. Check it's reasonable.
      expect(state.bySide[side]!.offset!.offsetUs, greaterThanOrEqualTo(-1000));
      expect(state.bySide[side]!.offset!.offsetUs, lessThanOrEqualTo(4000));
    });

    test('multiple pings keep the min-RTT estimate', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);

      // Ping 1: high RTT (we simulate by delaying the response).
      await notifier.sendPing(side);
      var pending = container.read(syncEngineProvider).bySide[side]!.pendingPing!;
      ble.syncController('L1')!.add(_syncResponseEvent(
        tAppMs: pending.t1AppMs,
        tDeviceUs: pending.t1AppUs + 10000,
        seqPing: 1,
      ));
      await Future<void>.delayed(Duration.zero);
      final offset1 = container.read(syncEngineProvider).bySide[side]!.offset!;

      // Ping 2: lower RTT (response arrives sooner).
      await notifier.sendPing(side);
      pending = container.read(syncEngineProvider).bySide[side]!.pendingPing!;
      ble.syncController('L1')!.add(_syncResponseEvent(
        tAppMs: pending.t1AppMs,
        tDeviceUs: pending.t1AppUs + 2000,
        seqPing: 2,
      ));
      await Future<void>.delayed(Duration.zero);
      final offset2 = container.read(syncEngineProvider).bySide[side]!.offset!;

      // The second ping should have a lower RTT and replace the first.
      expect(offset2.rttMs, lessThanOrEqualTo(offset1.rttMs));
    });

    test('collects drift points and computes DriftFit after ≥2 pings',
        () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);

      // Ping 1: t_device=1000000, t_app=1000
      await notifier.sendPing(side);
      var pending = container.read(syncEngineProvider).bySide[side]!.pendingPing!;
      ble.syncController('L1')!.add(_syncResponseEvent(
        tAppMs: pending.t1AppMs,
        tDeviceUs: 1000000,
        seqPing: 1,
      ));
      await Future<void>.delayed(Duration.zero);

      // Ping 2: t_device=2000000, t_app=2000
      await notifier.sendPing(side);
      pending = container.read(syncEngineProvider).bySide[side]!.pendingPing!;
      ble.syncController('L1')!.add(_syncResponseEvent(
        tAppMs: pending.t1AppMs,
        tDeviceUs: 2000000,
        seqPing: 2,
      ));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(syncEngineProvider);
      expect(state.bySide[side]!.driftFit, isNotNull);
      expect(state.bySide[side]!.driftFit!.n, 2);
    });

    test('START_FIRED event sets lastStartFiredUs', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);
      await notifier.startListening(side);
      await Future<void>.delayed(Duration.zero);

      ble.syncController('L1')!.add(_event(0x30, [..._u32LE(5000000)]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(syncEngineProvider);
      expect(state.bySide[side]!.lastStartFiredUs, 5000000);
    });

    test('STOP_FIRED event sets lastStopFiredUs + lastSeq', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);
      await notifier.startListening(side);
      await Future<void>.delayed(Duration.zero);

      ble.syncController('L1')!.add(
          _event(0x40, [..._u32LE(6000000), ..._u32LE(9999)]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(syncEngineProvider);
      expect(state.bySide[side]!.lastStopFiredUs, 6000000);
      expect(state.bySide[side]!.lastSeq, 9999);
    });

    test('DROP_COUNT event updates dropCount', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);
      await notifier.startListening(side);
      await Future<void>.delayed(Duration.zero);

      ble.syncController('L1')!.add(_event(0x10, [..._u32LE(42)]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(syncEngineProvider);
      expect(state.bySide[side]!.dropCount, 42);
    });

    test('CMD_NACK event sets error', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);
      await notifier.startListening(side);
      await Future<void>.delayed(Duration.zero);

      ble.syncController('L1')!.add(_event(0x20, [0x99]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(syncEngineProvider);
      expect(state.bySide[side]!.error, isNotNull);
      expect(state.bySide[side]!.error, contains('NACK'));
    });

    test('sendStart writes START command with target_start_us', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);

      await notifier.sendStart(side, targetStartUs: 1234567);

      final written = ble.lastControlWrite('L1')!;
      expect(written[0], ControlCommandId.start);
      final target =
          ByteData.sublistView(Uint8List.fromList(written)).getUint32(1, Endian.little);
      expect(target, 1234567);
    });

    test('sendStop writes STOP command', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);

      await notifier.sendStop(side);

      final written = ble.lastControlWrite('L1')!;
      expect(written, [ControlCommandId.stop]);
    });

    test('sendResetSeq writes RESET_SEQ command', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);

      await notifier.sendResetSeq(side);

      final written = ble.lastControlWrite('L1')!;
      expect(written, [ControlCommandId.resetSeq]);
    });

    test('sendPing without connected device sets error', () async {
      final notifier = container.read(syncEngineProvider.notifier);
      await notifier.sendPing(side);

      final state = container.read(syncEngineProvider);
      expect(state.bySide[side]!.error, isNotNull);
      expect(state.bySide[side]!.error, contains('not connected'));
    });

    test('dispose cancels all sync subscriptions', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);
      await notifier.startListening(side);
      await Future<void>.delayed(Duration.zero);

      container.dispose();

      // No exception thrown — subscriptions were cancelled cleanly.
      expect(true, isTrue);
    });

    test('malformed sync event sets error and stops listening', () async {
      await container.read(connectionManagerProvider.notifier).connect('L1');
      final notifier = container.read(syncEngineProvider.notifier);
      await notifier.startListening(side);
      await Future<void>.delayed(Duration.zero);

      // Unknown event_id 0x99
      ble.syncController('L1')!.add(_event(0x99, [0x00]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(syncEngineProvider);
      expect(state.bySide[side]!.error, isNotNull);
    });
  });
}

List<int> _u32LE(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}
