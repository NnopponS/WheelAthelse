import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/control_command.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/record_countdown_providers.dart';
import 'package:wheelathlete/state/recording_providers.dart';
import 'package:wheelathlete/state/sync_engine.dart';

/// Builds a START_FIRED Sync notify payload: [0x30][uint32 t_device_us].
Uint8List _startFiredEvent(int tDeviceUs) {
  final inner = ByteData(4)..setUint32(0, tDeviceUs, Endian.little);
  return Uint8List.fromList([0x30, ...inner.buffer.asUint8List()]);
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
  group('computeUtcStartMs (pure)', () {
    test('utc_start = utc_now + (T_start - now_phone)', () {
      const utcNow = 1780000000000;
      const nowPhone = 1780000005000;
      const tStart = nowPhone + 5000;
      expect(
        computeUtcStartMs(
          utcEpochNowMs: utcNow,
          nowPhoneMs: nowPhone,
          tStartPhoneMs: tStart,
        ),
        utcNow + 5000,
      );
    });

    test('T_start in the past → utc_start < utc_now', () {
      const utcNow = 1780000000000;
      const nowPhone = 1780000005000;
      const tStart = nowPhone - 2000;
      expect(
        computeUtcStartMs(
          utcEpochNowMs: utcNow,
          nowPhoneMs: nowPhone,
          tStartPhoneMs: tStart,
        ),
        utcNow - 2000,
      );
    });

    test('T_start == now → utc_start == utc_now', () {
      const utcNow = 1780000000000;
      const nowPhone = 1780000005000;
      expect(
        computeUtcStartMs(
          utcEpochNowMs: utcNow,
          nowPhoneMs: nowPhone,
          tStartPhoneMs: nowPhone,
        ),
        utcNow,
      );
    });
  });

  group('RecordCountdownNotifier', () {
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
          // Short countdown so the test completes quickly.
          countdownDurationProvider.overrideWith((ref) => const Duration(milliseconds: 200)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(connectionManagerProvider.notifier).connect('L1');
      await container.read(connectionManagerProvider.notifier).connect('R1');
      await storage.createTopic('sprint_test');
    }

    test('initial state is idle', () async {
      await pumpProviders();
      final state = container.read(recordCountdownProvider);
      expect(state.status, RecordCountdownStatus.idle);
      expect(state.countdownSeconds, 0);
      expect(state.tStartPhoneMs, isNull);
      expect(state.utcStartMs, isNull);
    });

    test('start transitions to syncing then counting and sends SET_UTC + START',
        () async {
      await pumpProviders();
      final notifier = container.read(recordCountdownProvider.notifier);
      const config = SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      );

      await notifier.start(config);

      // After start completes the sync burst + sends, state should be counting.
      final state = container.read(recordCountdownProvider);
      expect(state.status, RecordCountdownStatus.counting);
      expect(state.tStartPhoneMs, isNotNull);
      expect(state.utcStartMs, isNotNull);

      // SET_UTC was written to both wheels (0x09). The fake only keeps the
      // last write per device, so verify the last write is the START command
      // (0x01) which is sent after SET_UTC.
      final leftWrite = ble.lastControlWrite('L1');
      expect(leftWrite, isNotNull);
      expect(leftWrite![0], ControlCommandId.start);
      final rightWrite = ble.lastControlWrite('R1');
      expect(rightWrite, isNotNull);
      expect(rightWrite![0], ControlCommandId.start);
    });

    test('START_FIRED from both wheels transitions to recording', () async {
      await pumpProviders();
      final notifier = container.read(recordCountdownProvider.notifier);
      const config = SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      );

      await notifier.start(config);

      // Inject START_FIRED from both wheels.
      ble.syncController('L1')?.add(_startFiredEvent(1000000));
      ble.syncController('R1')?.add(_startFiredEvent(1000500));

      // Allow the stream listeners + recording start to process.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(recordCountdownProvider);
      expect(state.status, RecordCountdownStatus.recording);

      // The recording notifier should now be recording with utcStartMs.
      final recState = container.read(recordingProvider);
      expect(recState.status, RecordingStatus.recording);
      expect(recState.config?.utcStartMs, isNotNull);
    });

    test('cancel during counting sends STOP and returns to idle', () async {
      await pumpProviders();
      final notifier = container.read(recordCountdownProvider.notifier);
      const config = SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      );

      await notifier.start(config);
      expect(
        container.read(recordCountdownProvider).status,
        RecordCountdownStatus.counting,
      );

      await notifier.cancel();

      final state = container.read(recordCountdownProvider);
      expect(state.status, RecordCountdownStatus.idle);

      // STOP (0x02) was sent to both wheels.
      final leftWrite = ble.lastControlWrite('L1');
      expect(leftWrite, isNotNull);
      expect(leftWrite![0], ControlCommandId.stop);
      final rightWrite = ble.lastControlWrite('R1');
      expect(rightWrite, isNotNull);
      expect(rightWrite![0], ControlCommandId.stop);
    });

    test('start with one wheel disconnected sets error', () async {
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
          countdownDurationProvider.overrideWith((ref) => const Duration(milliseconds: 200)),
        ],
      );
      addTearDown(container.dispose);
      // Only connect the left wheel.
      await container.read(connectionManagerProvider.notifier).connect('L1');
      await storage.createTopic('sprint_test');

      final notifier = container.read(recordCountdownProvider.notifier);
      const config = SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      );
      await notifier.start(config);

      final state = container.read(recordCountdownProvider);
      expect(state.status, RecordCountdownStatus.error);
      expect(state.error, isNotNull);
    });

    test('utcStartMs is baked into the saved session meta on stop', () async {
      await pumpProviders();
      final countdown = container.read(recordCountdownProvider.notifier);
      const config = SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      );
      await countdown.start(config);
      final expectedUtc = container.read(recordCountdownProvider).utcStartMs;
      expect(expectedUtc, isNotNull);

      // Fire START_FIRED to begin recording.
      ble.syncController('L1')?.add(_startFiredEvent(1000000));
      ble.syncController('R1')?.add(_startFiredEvent(1000500));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        container.read(recordingProvider).status,
        RecordingStatus.recording,
      );

      // Stop the recording.
      await container.read(recordingProvider.notifier).stopRecording();

      // Read back the saved meta.
      final metas = await storage.listSessions('sprint_test', 1);
      expect(metas, hasLength(1));
      expect(metas.first.utcStartMs, expectedUtc);
    });

    test('reset returns to idle from any state', () async {
      await pumpProviders();
      final notifier = container.read(recordCountdownProvider.notifier);
      const config = SessionConfig(
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
      );
      await notifier.start(config);
      expect(
        container.read(recordCountdownProvider).status,
        RecordCountdownStatus.counting,
      );

      notifier.reset();
      final state = container.read(recordCountdownProvider);
      expect(state.status, RecordCountdownStatus.idle);
      expect(state.tStartPhoneMs, isNull);
      expect(state.utcStartMs, isNull);
    });
  });

  group('SessionMeta utcStartMs JSON roundtrip', () {
    test('toJson/fromJson preserves utcStartMs', () {
      final meta = SessionMeta(
        sessionId: 'abc123',
        topic: 'sprint_test',
        trialNumber: 1,
        sampleRateHz: 100,
        startTime: DateTime.utc(2026, 6, 29, 12, 0, 0),
        durationMs: 5000,
        sampleCount: 500,
        markerCount: 1,
        utcStartMs: 1780000000000,
      );
      final json = meta.toJson();
      expect(json['utc_start_ms'], 1780000000000);
      final restored = SessionMeta.fromJson(json);
      expect(restored.utcStartMs, 1780000000000);
    });

    test('fromJson handles missing utc_start_ms (legacy)', () {
      final json = {
        'session_id': 'abc',
        'topic': 't',
        'trial_number': 1,
        'sample_rate_hz': 100,
        'start_time': DateTime.utc(2026, 1, 1).toIso8601String(),
        'duration_ms': 1000,
        'sample_count': 10,
        'marker_count': 0,
      };
      final meta = SessionMeta.fromJson(json);
      expect(meta.utcStartMs, isNull);
    });
  });
}
