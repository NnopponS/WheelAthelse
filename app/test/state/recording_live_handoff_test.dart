import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/live_acquisition_providers.dart';
import 'package:wheelathlete/state/record_countdown_providers.dart';
import 'package:wheelathlete/state/recording_providers.dart';

Uint8List _batch(int sequence) {
  final sample = ByteData(20)
    ..setUint32(0, sequence, Endian.little)
    ..setUint32(4, 1000, Endian.little)
    ..setInt16(12, 16384, Endian.little);
  return Uint8List.fromList([1, ...sample.buffer.asUint8List()]);
}

void main() {
  test(
    'recording stops Live and accepts a fresh firmware sequence zero',
    () async {
      final ble = FakeBleRepository(
        devices: const [
          FakeDevice(id: 'L1', name: 'WheelAthlete-M5-L', rssi: -40),
        ],
        infoFor: const {
          'L1': DeviceInfo(
            wheelId: WheelId.left,
            fwMajor: 1,
            fwMinor: 3,
            fwPatch: 0,
            accelRange: 0,
            gyroRange: 3,
            accelScale: 1 / 16384,
            gyroScale: 1 / 16.4,
          ),
        },
        autoAcknowledgeControls: true,
      );
      final storage = InMemoryStorageRepository();
      final container = ProviderContainer(
        overrides: [
          bleRepositoryProvider.overrideWith((ref) => ble),
          storageRepositoryProvider.overrideWith((ref) => storage),
          rssiPollIntervalProvider.overrideWith((ref) => null),
          interConnectSettleDelayProvider.overrideWith((ref) => Duration.zero),
          countdownDurationProvider.overrideWith((ref) => Duration.zero),
          recordingEmitIntervalProvider.overrideWith((ref) => Duration.zero),
        ],
      );
      addTearDown(container.dispose);
      await container.read(connectionManagerProvider.notifier).connect('L1');
      await storage.createTopic('handoff');

      await container.read(liveAcquisitionProvider.notifier).start();
      ble.imuController('L1')!.add(_batch(100));
      expect(container.read(liveAcquisitionProvider).active, isTrue);

      await container
          .read(recordCountdownProvider.notifier)
          .start(
            const SessionConfig(
              topic: 'handoff',
              trialNumber: 1,
              sampleRateHz: 100,
            ),
          );
      await Future<void>.delayed(Duration.zero);
      ble.imuController('L1')!.add(_batch(0));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(liveAcquisitionProvider).status,
        LiveAcquisitionStatus.idle,
      );
      expect(
        container.read(recordingProvider).status,
        RecordingStatus.recording,
      );
      expect(container.read(recordingProvider).sampleCount, 1);
    },
  );
}
