import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/state/recording_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

Uint8List _sample({
  required int seq,
  required int tDeviceUs,
  int ax = 0,
  int ay = 0,
  int az = 0,
  int gx = 0,
  int gy = 0,
  int gz = 0,
}) {
  final b = ByteData(20)
    ..setUint32(0, seq, Endian.little)
    ..setUint32(4, tDeviceUs, Endian.little)
    ..setInt16(8, ax, Endian.little)
    ..setInt16(10, ay, Endian.little)
    ..setInt16(12, az, Endian.little)
    ..setInt16(14, gx, Endian.little)
    ..setInt16(16, gy, Endian.little)
    ..setInt16(18, gz, Endian.little);
  return b.buffer.asUint8List();
}

Uint8List _batch(List<Uint8List> samples) {
  final body = BytesBuilder();
  for (final s in samples) {
    body.add(s);
  }
  return (BytesBuilder()..addByte(samples.length)..add(body.toBytes()))
      .toBytes();
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

const _rightInfo = DeviceInfo(
  wheelId: WheelId.right,
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
  late InMemoryStorageRepository storage;
  late ProviderContainer container;

  Future<void> pumpProviders() async {
    storage = InMemoryStorageRepository();
    ble = FakeBleRepository(
      devices: [
        const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
        const FakeDevice(id: 'R1', name: 'WheelAthlete-R', rssi: -55),
      ],
      infoFor: const {'L1': _leftInfo, 'R1': _rightInfo},
    );
    container = ProviderContainer(
      overrides: [
        bleRepositoryProvider.overrideWith((ref) => ble),
        storageRepositoryProvider.overrideWith((ref) => storage),
        rssiPollIntervalProvider.overrideWith((ref) => null),
        interConnectSettleDelayProvider.overrideWith((ref) => Duration.zero),
        // Default: emit every batch (immediate) so existing tests see state
        // updates synchronously. The throttling test overrides this per-test.
        recordingEmitIntervalProvider.overrideWith((ref) => Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    // Connect both wheels.
    await container.read(connectionManagerProvider.notifier).connect('L1');
    await container.read(connectionManagerProvider.notifier).connect('R1');
  }

  group('RecordingNotifier', () {
    test('initial state: idle, no config, no samples', () async {
      await pumpProviders();
      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.idle);
      expect(state.config, isNull);
      expect(state.sampleCount, 0);
    });

    test('startRecording sets status to recording + stores config', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final trialNum = await storage.nextTrialNumber('sprint_test');
      final notifier = container.read(recordingProvider.notifier);

      const config = SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
        athleteName: 'Athlete A',
      );
      await notifier.startRecording(config);

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.recording);
      expect(state.config, isNotNull);
      expect(state.config!.topic, 'sprint_test');
      expect(state.config!.trialNumber, trialNum);
      expect(state.startTime, isNotNull);
    });

    test('startRecording throws if already recording', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(const SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      ));
      expect(
        () => notifier.startRecording(const SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        )),
        throwsStateError,
      );
    });

    test('startRecording starts IMU streaming on both sides', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(const SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      ));

      // IMU stream should be active.
      final imuState = container.read(imuStreamProvider);
      expect(imuState.bySide[WheelSide.left]!.streaming, isTrue);
      expect(imuState.bySide[WheelSide.right]!.streaming, isTrue);
    });

    test('IMU samples are buffered during recording', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(const SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      ));

      // Emit a batch on the left wheel.
      ble.imuController('L1')!.add(_batch([
        _sample(seq: 0, tDeviceUs: 1000, ax: 16384),
      ]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(recordingProvider);
      expect(state.sampleCount, greaterThan(0));
    });

    test('markEvent is no longer exposed by RecordingNotifier', () async {
      await pumpProviders();
      final notifier = container.read(recordingProvider.notifier);
      // The Mark Event function was removed from the recording UI (Phase 3,
      // D16). The notifier must no longer expose a markEvent method —
      // invoking it via dynamic dispatch throws a NoSuchMethodError.
      final dynamic dyn = notifier;
      expect(
        () => dyn.markEvent(),
        throwsNoSuchMethodError,
      );
    });

    test('stopRecording sets status to stopped + saves session to storage',
        () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(const SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
        athleteName: 'Athlete A',
      ));

      // Emit some samples.
      ble.imuController('L1')!.add(_batch([
        _sample(seq: 0, tDeviceUs: 1000),
        _sample(seq: 1, tDeviceUs: 11000),
      ]));
      await Future<void>.delayed(Duration.zero);

      await notifier.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.stopped);
      expect(state.savedSessionId, isNotNull);

      // Verify the session was saved to storage.
      final meta = await storage.readSessionMeta(
        'sprint_test', 1, state.savedSessionId!);
      expect(meta, isNotNull);
      expect(meta!.topic, 'sprint_test');
      expect(meta.athleteName, 'Athlete A');
      expect(meta.sampleCount, greaterThan(0));
    });

    test('stopRecording stops IMU streaming', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(const SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      ));
      await notifier.stopRecording();

      final imuState = container.read(imuStreamProvider);
      expect(imuState.bySide[WheelSide.left]!.streaming, isFalse);
      expect(imuState.bySide[WheelSide.right]!.streaming, isFalse);
    });

    test('samples use absolute UTC timestamp when utcOffsetMs is set', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);

      const utcOffsetMs = 1780000000000;
      const startUtcMs = utcOffsetMs + 1000;
      await notifier.startRecording(SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
        utcStartMs: startUtcMs,
        utcOffsetMs: utcOffsetMs,
        startTime: DateTime.fromMillisecondsSinceEpoch(startUtcMs, isUtc: true),
      ));

      // Emit a sample with tDeviceUs = 5000 -> relativeSyncedMs = 5.0
      ble.imuController('L1')!.add(_batch([
        _sample(seq: 0, tDeviceUs: 5000),
      ]));
      await Future<void>.delayed(Duration.zero);

      await notifier.stopRecording();

      final sessionId = notifier.state.savedSessionId!;
      final samples = await storage.readSamples('sprint_test', 1, sessionId);
      expect(samples, isNotEmpty);
      expect(samples.first.timestampSyncedMs, startUtcMs.toDouble());

      final meta = await storage.readSessionMeta('sprint_test', 1, sessionId);
      expect(meta!.utcStartMs, startUtcMs);
      expect(meta.startTime.toUtc().millisecondsSinceEpoch, startUtcMs);
    });

    test('stopRecording throws if not recording', () async {
      await pumpProviders();
      final notifier = container.read(recordingProvider.notifier);
      expect(() => notifier.stopRecording(), throwsStateError);
    });

    test('reset returns to idle state', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(const SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      ));
      await notifier.stopRecording();
      notifier.reset();

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.idle);
      expect(state.config, isNull);
      expect(state.sampleCount, 0);
      expect(state.savedSessionId, isNull);
    });

    test('throttled emit: sampleCount state is not emitted on every batch when '
        'recordingEmitInterval is non-zero, but buffer accumulates all samples',
        () async {
      // Build a separate container with a non-zero emit interval.
      final storage2 = InMemoryStorageRepository();
      final ble2 = FakeBleRepository(
        devices: [
          const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
          const FakeDevice(id: 'R1', name: 'WheelAthlete-R', rssi: -55),
        ],
        infoFor: const {'L1': _leftInfo, 'R1': _rightInfo},
      );
      final container2 = ProviderContainer(
        overrides: [
          bleRepositoryProvider.overrideWith((ref) => ble2),
          storageRepositoryProvider.overrideWith((ref) => storage2),
          rssiPollIntervalProvider.overrideWith((ref) => null),
          interConnectSettleDelayProvider.overrideWith((ref) => Duration.zero),
          recordingEmitIntervalProvider
              .overrideWith((ref) => const Duration(milliseconds: 100)),
        ],
      );
      addTearDown(container2.dispose);
      await container2.read(connectionManagerProvider.notifier).connect('L1');
      await container2.read(connectionManagerProvider.notifier).connect('R1');

      await storage2.createTopic('sprint_test');
      final notifier = container2.read(recordingProvider.notifier);
      await notifier.startRecording(const SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      ));

      // Emit 3 batches in quick succession (no time advance).
      final ctrl = ble2.imuController('L1')!;
      ctrl.add(_batch([_sample(seq: 0, tDeviceUs: 0)]));
      ctrl.add(_batch([_sample(seq: 1, tDeviceUs: 1000)]));
      ctrl.add(_batch([_sample(seq: 2, tDeviceUs: 2000)]));
      await Future<void>.delayed(Duration.zero);

      // The state's sampleCount should NOT reflect all 3 batches yet — it
      // is throttled. The first batch emits immediately (initial emit), but
      // subsequent batches within the throttle window are held.
      final stateAfterBurst = container2.read(recordingProvider);
      expect(
        stateAfterBurst.sampleCount,
        lessThan(3),
        reason:
            'sampleCount should be throttled — not all 3 batches emitted yet',
      );

      // Advance time past the throttle interval and pump microtasks so the
      // pending emit fires.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final stateAfterDelay = container2.read(recordingProvider);
      expect(
        stateAfterDelay.sampleCount,
        3,
        reason: 'after the throttle interval, all buffered samples are '
            'reflected in sampleCount',
      );

      // The buffer itself always has all samples regardless of throttle.
      await notifier.stopRecording();
      final sessionId = notifier.state.savedSessionId!;
      final samples =
          await storage2.readSamples('sprint_test', 1, sessionId);
      expect(samples, hasLength(3));
    });

    test('zero emit interval: sampleCount updates on every batch (test mode)',
        () async {
      await pumpProviders();
      // The default in pumpProviders is Duration.zero (immediate).
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(const SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      ));

      ble.imuController('L1')!.add(_batch([_sample(seq: 0, tDeviceUs: 0)]));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(recordingProvider).sampleCount, 1);

      ble.imuController('L1')!.add(_batch([_sample(seq: 1, tDeviceUs: 1000)]));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(recordingProvider).sampleCount, 2);

      await notifier.stopRecording();
    });
  });
}
