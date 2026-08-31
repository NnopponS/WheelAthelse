import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/sync_packet.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/imu_providers.dart';
import 'package:wheelathlete/state/recording_providers.dart';
import 'package:wheelathlete/state/sync_providers.dart';
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
  return (BytesBuilder()
        ..addByte(samples.length)
        ..add(body.toBytes()))
      .toBytes();
}

Uint8List _startFired(int tDeviceUs) {
  final data = ByteData(5)
    ..setUint8(0, 0x30)
    ..setUint32(1, tDeviceUs, Endian.little);
  return data.buffer.asUint8List();
}

Uint8List _acqHealth({
  required int produced,
  required int notified,
  required int drops,
  required int failures,
  required int queueDepth,
  int fifoFaults = 0,
  int fifoDroppedSamples = 0,
}) {
  final data = ByteData(28)
    ..setUint8(0, 0x60)
    ..setUint8(1, drops > 0 || fifoFaults > 0 ? 4 : (failures > 0 ? 3 : 2))
    ..setUint32(2, produced, Endian.little)
    ..setUint32(6, notified, Endian.little)
    ..setUint32(10, drops, Endian.little)
    ..setUint32(14, failures, Endian.little)
    ..setUint16(18, queueDepth, Endian.little)
    ..setUint32(20, fifoFaults, Endian.little)
    ..setUint32(24, fifoDroppedSamples, Endian.little);
  return data.buffer.asUint8List();
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

class _ImmediateFirstPacketBleRepository extends FakeBleRepository {
  _ImmediateFirstPacketBleRepository({
    required super.devices,
    required super.infoFor,
    required this.firstPackets,
  });

  final Map<String, List<int>> firstPackets;
  final Map<String, StreamController<List<int>>> _immediateControllers = {};

  @override
  BleNotificationChannel<List<int>> imuNotifications(String deviceId) {
    late StreamController<List<int>> controller;
    controller = _immediateControllers.putIfAbsent(
      deviceId,
      () => StreamController<List<int>>.broadcast(
        sync: true,
        onListen: () {
          final packet = firstPackets[deviceId];
          if (packet != null) controller.add(packet);
        },
      ),
    );
    return BleNotificationChannel<List<int>>(
      stream: controller.stream,
      ready: Future<void>.value(),
      close: () async {},
    );
  }
}

void main() {
  late FakeBleRepository ble;
  late InMemoryStorageRepository storage;
  late ProviderContainer container;

  Future<void> pumpProviders({
    bool autoAcknowledgeControls = false,
    Map<String, int> stopWriteFailuresFor = const {},
  }) async {
    storage = InMemoryStorageRepository();
    ble = FakeBleRepository(
      devices: [
        const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
        const FakeDevice(id: 'R1', name: 'WheelAthlete-R', rssi: -55),
      ],
      infoFor: const {'L1': _leftInfo, 'R1': _rightInfo},
      autoAcknowledgeControls: autoAcknowledgeControls,
      stopWriteFailuresFor: stopWriteFailuresFor,
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
        recordingStopAckTimeoutProvider.overrideWith(
          (ref) => const Duration(milliseconds: 10),
        ),
        stopCommandRetryDelayProvider.overrideWith((ref) => Duration.zero),
      ],
    );
    addTearDown(container.dispose);
    // Connect both wheels.
    await container.read(connectionManagerProvider.notifier).connect('L1');
    await container.read(connectionManagerProvider.notifier).connect('R1');
  }

  group('RecordingNotifier', () {
    test(
      'lossless recorder is attached before an immediate first packet',
      () async {
        storage = InMemoryStorageRepository();
        final immediateBle = _ImmediateFirstPacketBleRepository(
          devices: const [
            FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
          ],
          infoFor: const {'L1': _leftInfo},
          firstPackets: {
            'L1': _batch([_sample(seq: 0, tDeviceUs: 1000)]),
          },
        );
        container = ProviderContainer(
          overrides: [
            bleRepositoryProvider.overrideWith((ref) => immediateBle),
            storageRepositoryProvider.overrideWith((ref) => storage),
            rssiPollIntervalProvider.overrideWith((ref) => null),
            interConnectSettleDelayProvider.overrideWith(
              (ref) => Duration.zero,
            ),
            recordingEmitIntervalProvider.overrideWith((ref) => Duration.zero),
          ],
        );
        addTearDown(container.dispose);
        await container.read(connectionManagerProvider.notifier).connect('L1');
        await storage.createTopic('first_packet');

        final notifier = container.read(recordingProvider.notifier);
        await notifier.startRecording(
          const SessionConfig(
            topic: 'first_packet',
            trialNumber: 1,
            sampleRateHz: 100,
          ),
        );

        expect(notifier.bufferedSamples, hasLength(1));
        expect(notifier.bufferedSamples.single.reading.seq, 0);
      },
    );

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
      await notifier.startRecording(
        const SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        ),
      );
      expect(
        () => notifier.startRecording(
          const SessionConfig(
            topic: 'sprint_test',
            trialNumber: 1,
            sampleRateHz: 100,
          ),
        ),
        throwsStateError,
      );
    });

    test('startRecording starts IMU streaming on both sides', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(
        const SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        ),
      );

      // IMU stream should be active.
      final imuState = container.read(imuStreamProvider);
      expect(imuState.bySide[WheelSide.left]!.streaming, isTrue);
      expect(imuState.bySide[WheelSide.right]!.streaming, isTrue);
      expect(ble.streamPreparationCalls, unorderedEquals(['L1', 'R1']));
    });

    test(
      'second armStreaming with existing subscriptions does not prepare again',
      () async {
        await pumpProviders();
        final notifier = container.read(recordingProvider.notifier);

        await notifier.armStreaming();
        expect(ble.streamPreparationCalls, unorderedEquals(['L1', 'R1']));

        ble.streamPreparationCalls.clear();
        await notifier.armStreaming();

        expect(ble.streamPreparationCalls, isEmpty);
      },
    );

    test(
      'critical transport health aborts before the firmware queue fills',
      () {
        expect(
          isCriticalTransportHealth(
            const AcqHealthEvent(
              acquisitionState: 3,
              producedSamples: 100,
              notifiedSamples: 30,
              queueDrops: 0,
              transportFailures: 3,
              queueDepth: 64,
            ),
          ),
          isTrue,
        );
        expect(
          isCriticalTransportHealth(
            const AcqHealthEvent(
              acquisitionState: 3,
              producedSamples: 20,
              notifiedSamples: 19,
              queueDrops: 0,
              transportFailures: 1,
              queueDepth: 1,
            ),
          ),
          isFalse,
        );
        expect(
          isCriticalTransportHealth(
            const AcqHealthEvent(
              acquisitionState: 4,
              producedSamples: 200,
              notifiedSamples: 150,
              queueDrops: 1,
              transportFailures: 1,
              queueDepth: 50,
            ),
          ),
          isTrue,
        );
      },
    );

    test('acquisition health reports the actual loss source', () {
      expect(
        criticalAcquisitionFailure(
          const AcqHealthEvent(
            acquisitionState: 4,
            producedSamples: 100,
            notifiedSamples: 99,
            queueDrops: 1,
            transportFailures: 0,
            queueDepth: 0,
          ),
        ),
        AcquisitionFailureCause.sampleQueueOverflow,
      );
      expect(
        criticalAcquisitionFailure(
          const AcqHealthEvent(
            acquisitionState: 4,
            producedSamples: 100,
            notifiedSamples: 98,
            queueDrops: 0,
            transportFailures: 0,
            queueDepth: 0,
            fifoFaults: 1,
            fifoDroppedSamples: 2,
          ),
        ),
        AcquisitionFailureCause.imuFifoFault,
      );
      expect(
        criticalAcquisitionFailure(
          const AcqHealthEvent(
            acquisitionState: 3,
            producedSamples: 100,
            notifiedSamples: 30,
            queueDrops: 0,
            transportFailures: 3,
            queueDepth: 64,
          ),
        ),
        AcquisitionFailureCause.bleTransportCongestion,
      );
    });

    test(
      'one-sided firmware congestion stops and quarantines both wheels',
      () async {
        await pumpProviders(autoAcknowledgeControls: true);
        await storage.createTopic('transport_abort');
        final sync = container.read(syncEngineProvider.notifier);
        await Future.wait([
          sync.startListening(WheelSide.left),
          sync.startListening(WheelSide.right),
        ]);
        final notifier = container.read(recordingProvider.notifier);
        await notifier.startRecording(
          const SessionConfig(
            topic: 'transport_abort',
            trialNumber: 1,
            sampleRateHz: 100,
          ),
        );
        ble
            .imuController('L1')!
            .add(_batch([_sample(seq: 0, tDeviceUs: 1000)]));
        ble
            .imuController('R1')!
            .add(_batch([_sample(seq: 0, tDeviceUs: 1000)]));
        ble
            .syncController('R1')!
            .add(
              _acqHealth(
                produced: 100,
                notified: 30,
                drops: 0,
                failures: 3,
                queueDepth: 64,
              ),
            );

        await Future<void>.delayed(const Duration(milliseconds: 600));

        final state = container.read(recordingProvider);
        expect(state.status, RecordingStatus.failed);
        expect(state.error, contains('right wheel BLE transport congested'));
        expect(
          container.read(imuStreamProvider).bySide[WheelSide.left]!.streaming,
          isFalse,
        );
        expect(
          container.read(imuStreamProvider).bySide[WheelSide.right]!.streaming,
          isFalse,
        );
      },
    );

    test('firmware FIFO loss is reported as an IMU fault', () async {
      await pumpProviders(autoAcknowledgeControls: true);
      await storage.createTopic('fifo_abort');
      final sync = container.read(syncEngineProvider.notifier);
      await Future.wait([
        sync.startListening(WheelSide.left),
        sync.startListening(WheelSide.right),
      ]);
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(
        const SessionConfig(
          topic: 'fifo_abort',
          trialNumber: 1,
          sampleRateHz: 100,
        ),
      );
      ble.imuController('L1')!.add(_batch([_sample(seq: 0, tDeviceUs: 1000)]));
      ble.imuController('R1')!.add(_batch([_sample(seq: 0, tDeviceUs: 1000)]));
      ble
          .syncController('L1')!
          .add(
            _acqHealth(
              produced: 100,
              notified: 98,
              drops: 0,
              failures: 0,
              queueDepth: 0,
              fifoFaults: 1,
              fifoDroppedSamples: 2,
            ),
          );

      await Future<void>.delayed(const Duration(milliseconds: 600));

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.failed);
      expect(state.error, contains('left wheel IMU FIFO fault'));
      expect(state.error, isNot(contains('BLE transport congested')));
    });

    test('IMU samples are buffered during recording', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(
        const SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        ),
      );

      // Emit a batch on the left wheel.
      ble
          .imuController('L1')!
          .add(_batch([_sample(seq: 0, tDeviceUs: 1000, ax: 16384)]));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(recordingProvider);
      expect(state.sampleCount, greaterThan(0));
    });

    test(
      'scheduled recording fails and discards when one side has no sample',
      () async {
        await pumpProviders();
        await storage.createTopic('sprint_test');
        final sync = container.read(syncEngineProvider.notifier);
        await Future.wait([
          sync.startListening(WheelSide.left),
          sync.startListening(WheelSide.right),
        ]);
        ble.syncController('L1')!.add(_startFired(1000));
        ble.syncController('R1')!.add(_startFired(2000));

        final notifier = container.read(recordingProvider.notifier);
        await notifier.startRecording(
          SessionConfig(
            topic: 'sprint_test',
            trialNumber: 1,
            sampleRateHz: 100,
            utcStartMs: 1780000000000,
            startTime: DateTime.fromMillisecondsSinceEpoch(
              1780000000000,
              isUtc: true,
            ),
          ),
        );
        expect(notifier.state.status, RecordingStatus.awaitingSamples);
        ble
            .imuController('L1')!
            .add(_batch([_sample(seq: 0, tDeviceUs: 2000)]));

        await Future<void>.delayed(const Duration(milliseconds: 2100));
        expect(notifier.state.status, RecordingStatus.failed);
        expect(notifier.state.error, contains('right wheel'));
        expect(notifier.state.savedSessionId, isNull);
        expect(notifier.bufferedSamples, isEmpty);
      },
    );

    test(
      'sustained dual-wheel input is buffered without app-side loss',
      () async {
        await pumpProviders();
        await storage.createTopic('endurance_test');
        final notifier = container.read(recordingProvider.notifier);
        await notifier.startRecording(
          const SessionConfig(
            topic: 'endurance_test',
            trialNumber: 1,
            sampleRateHz: 200,
          ),
        );

        const samplesPerSide = 4000;
        const samplesPerBatch = 8;
        for (var start = 0; start < samplesPerSide; start += samplesPerBatch) {
          for (final deviceId in ['L1', 'R1']) {
            ble
                .imuController(deviceId)!
                .add(
                  _batch([
                    for (var offset = 0; offset < samplesPerBatch; offset++)
                      _sample(
                        seq: start + offset,
                        tDeviceUs: (start + offset) * 5000,
                      ),
                  ]),
                );
          }
        }
        await Future<void>.delayed(Duration.zero);

        final buffered = notifier.bufferedSamples;
        expect(buffered, hasLength(samplesPerSide * 2));
        expect(
          buffered.where((sample) => sample.wheel == WheelSide.left),
          hasLength(samplesPerSide),
        );
        expect(
          buffered.where((sample) => sample.wheel == WheelSide.right),
          hasLength(samplesPerSide),
        );
      },
    );

    test('markEvent is no longer exposed by RecordingNotifier', () async {
      await pumpProviders();
      final notifier = container.read(recordingProvider.notifier);
      // The Mark Event function was removed from the recording UI (Phase 3,
      // D16). The notifier must no longer expose a markEvent method —
      // invoking it via dynamic dispatch throws a NoSuchMethodError.
      final dynamic dyn = notifier;
      expect(() => dyn.markEvent(), throwsNoSuchMethodError);
    });

    test(
      'stopRecording sets status to stopped + saves session to storage',
      () async {
        await pumpProviders();
        await storage.createTopic('sprint_test');
        final notifier = container.read(recordingProvider.notifier);
        await notifier.startRecording(
          const SessionConfig(
            topic: 'sprint_test',
            trialNumber: 1,
            sampleRateHz: 100,
            athleteName: 'Athlete A',
          ),
        );

        // Emit some samples.
        ble
            .imuController('L1')!
            .add(
              _batch([
                _sample(seq: 0, tDeviceUs: 1000),
                _sample(seq: 1, tDeviceUs: 11000),
              ]),
            );
        await Future<void>.delayed(Duration.zero);

        await notifier.stopRecording();

        final state = container.read(recordingProvider);
        expect(state.status, RecordingStatus.stopped);
        expect(state.savedSessionId, isNotNull);

        // Verify the session was saved to storage.
        final meta = await storage.readSessionMeta(
          'sprint_test',
          1,
          state.savedSessionId!,
        );
        expect(meta, isNotNull);
        expect(meta!.topic, 'sprint_test');
        expect(meta.athleteName, 'Athlete A');
        expect(meta.sampleCount, greaterThan(0));
      },
    );

    test('stopRecording stops IMU streaming', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(
        const SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        ),
      );
      await notifier.stopRecording();

      final imuState = container.read(imuStreamProvider);
      expect(imuState.bySide[WheelSide.left]!.streaming, isFalse);
      expect(imuState.bySide[WheelSide.right]!.streaming, isFalse);
    });

    test('repeated stop calls issue only one STOP per board', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(
        const SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        ),
      );

      final first = notifier.stopRecording();
      final repeated = notifier.stopRecording();
      await Future.wait([first, repeated]);

      for (final deviceId in ['L1', 'R1']) {
        final stopWrites = ble
            .allControlWrites(deviceId)
            .where((bytes) => bytes.isNotEmpty && bytes.first == 0x02);
        expect(stopWrites, hasLength(1));
      }
    });

    test(
      'transient STOP write failure is retried before stream teardown',
      () async {
        await pumpProviders(
          autoAcknowledgeControls: true,
          stopWriteFailuresFor: const {'R1': 1},
        );
        await storage.createTopic('stop_retry');
        final notifier = container.read(recordingProvider.notifier);
        final sync = container.read(syncEngineProvider.notifier);
        await Future.wait([
          sync.startListening(WheelSide.left),
          sync.startListening(WheelSide.right),
        ]);
        await notifier.startRecording(
          const SessionConfig(
            topic: 'stop_retry',
            trialNumber: 1,
            sampleRateHz: 100,
          ),
        );
        ble
            .imuController('L1')!
            .add(_batch([_sample(seq: 0, tDeviceUs: 1000)]));
        ble
            .imuController('R1')!
            .add(_batch([_sample(seq: 0, tDeviceUs: 1000)]));
        await Future<void>.delayed(Duration.zero);

        await notifier.stopRecording();

        expect(
          container.read(recordingProvider).status,
          RecordingStatus.stopped,
        );
        expect(
          ble.allControlWrites('R1').where((bytes) => bytes.first == 0x02),
          hasLength(2),
        );
        expect(ble.disconnectCount('R1'), 0);
      },
    );

    test('persistent STOP failure disconnects the board for safety', () async {
      await pumpProviders(
        autoAcknowledgeControls: true,
        stopWriteFailuresFor: const {'R1': 10},
      );
      await storage.createTopic('stop_fallback');
      final notifier = container.read(recordingProvider.notifier);
      final sync = container.read(syncEngineProvider.notifier);
      await Future.wait([
        sync.startListening(WheelSide.left),
        sync.startListening(WheelSide.right),
      ]);
      await notifier.startRecording(
        const SessionConfig(
          topic: 'stop_fallback',
          trialNumber: 1,
          sampleRateHz: 100,
        ),
      );
      ble.imuController('L1')!.add(_batch([_sample(seq: 0, tDeviceUs: 1000)]));
      ble.imuController('R1')!.add(_batch([_sample(seq: 0, tDeviceUs: 1000)]));
      await Future<void>.delayed(Duration.zero);

      await notifier.stopRecording();

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.stopped);
      expect(state.error, contains('disconnected for safety'));
      expect(ble.disconnectCount('R1'), 1);
    });

    test(
      'scheduled samples stay START-relative while UTC remains metadata',
      () async {
        await pumpProviders();
        await storage.createTopic('sprint_test');
        final notifier = container.read(recordingProvider.notifier);

        const utcOffsetMs = 1780000000000;
        const startUtcMs = utcOffsetMs + 1000;
        final sync = container.read(syncEngineProvider.notifier);
        await Future.wait([
          sync.startListening(WheelSide.left),
          sync.startListening(WheelSide.right),
        ]);
        ble.syncController('L1')!.add(_startFired(1000));
        ble.syncController('R1')!.add(_startFired(21000));
        await notifier.startRecording(
          SessionConfig(
            topic: 'sprint_test',
            trialNumber: 1,
            sampleRateHz: 100,
            utcStartMs: startUtcMs,
            utcOffsetMs: utcOffsetMs,
            startTime: DateTime.fromMillisecondsSinceEpoch(
              startUtcMs,
              isUtc: true,
            ),
          ),
        );

        // Different raw uptimes map to the same 4 ms START-relative instant.
        ble
            .imuController('L1')!
            .add(_batch([_sample(seq: 0, tDeviceUs: 5000)]));
        ble
            .imuController('R1')!
            .add(_batch([_sample(seq: 0, tDeviceUs: 25000)]));
        await Future<void>.delayed(Duration.zero);

        await notifier.stopRecording();

        final sessionId = notifier.state.savedSessionId!;
        final samples = await storage.readSamples('sprint_test', 1, sessionId);
        expect(samples, isNotEmpty);
        expect(
          samples.map((sample) => sample.timestampSyncedMs),
          everyElement(4.0),
        );

        final meta = await storage.readSessionMeta('sprint_test', 1, sessionId);
        expect(meta!.utcStartMs, startUtcMs);
        expect(meta.startTime.toUtc().millisecondsSinceEpoch, startUtcMs);
      },
    );

    test('stopRecording throws if not recording', () async {
      await pumpProviders();
      final notifier = container.read(recordingProvider.notifier);
      expect(() => notifier.stopRecording(), throwsStateError);
    });

    test('reset returns to idle state', () async {
      await pumpProviders();
      await storage.createTopic('sprint_test');
      final notifier = container.read(recordingProvider.notifier);
      await notifier.startRecording(
        const SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        ),
      );
      await notifier.stopRecording();
      notifier.reset();

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.idle);
      expect(state.config, isNull);
      expect(state.sampleCount, 0);
      expect(state.savedSessionId, isNull);
    });

    test(
      'throttled emit: sampleCount state is not emitted on every batch when '
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
            interConnectSettleDelayProvider.overrideWith(
              (ref) => Duration.zero,
            ),
            recordingEmitIntervalProvider.overrideWith(
              (ref) => const Duration(milliseconds: 100),
            ),
          ],
        );
        addTearDown(container2.dispose);
        await container2.read(connectionManagerProvider.notifier).connect('L1');
        await container2.read(connectionManagerProvider.notifier).connect('R1');

        await storage2.createTopic('sprint_test');
        final notifier = container2.read(recordingProvider.notifier);
        await notifier.startRecording(
          const SessionConfig(
            topic: 'sprint_test',
            trialNumber: 1,
            sampleRateHz: 100,
          ),
        );

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
          reason:
              'after the throttle interval, all buffered samples are '
              'reflected in sampleCount',
        );

        // The buffer itself always has all samples regardless of throttle.
        await notifier.stopRecording();
        final sessionId = notifier.state.savedSessionId!;
        final samples = await storage2.readSamples('sprint_test', 1, sessionId);
        expect(samples, hasLength(3));
      },
    );

    test(
      'zero emit interval: sampleCount updates on every batch (test mode)',
      () async {
        await pumpProviders();
        // The default in pumpProviders is Duration.zero (immediate).
        await storage.createTopic('sprint_test');
        final notifier = container.read(recordingProvider.notifier);
        await notifier.startRecording(
          const SessionConfig(
            topic: 'sprint_test',
            trialNumber: 1,
            sampleRateHz: 100,
          ),
        );

        ble.imuController('L1')!.add(_batch([_sample(seq: 0, tDeviceUs: 0)]));
        await Future<void>.delayed(Duration.zero);
        expect(container.read(recordingProvider).sampleCount, 1);

        ble
            .imuController('L1')!
            .add(_batch([_sample(seq: 1, tDeviceUs: 1000)]));
        await Future<void>.delayed(Duration.zero);
        expect(container.read(recordingProvider).sampleCount, 2);

        await notifier.stopRecording();
      },
    );
  });
}
