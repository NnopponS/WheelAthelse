import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/live_acquisition_providers.dart';
import 'package:wheelathlete/state/sync_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/connection_card.dart';

const _deviceInfo = DeviceInfo(
  wheelId: WheelId.left,
  fwMajor: 1,
  fwMinor: 6,
  fwPatch: 1,
  accelRange: 0,
  gyroRange: 3,
  accelScale: 1 / 16384,
  gyroScale: 1 / 16.4,
);

Future<(FakeBleRepository, ProviderContainer)> _connectedLiveContainer({
  required Map<String, int> stopWriteFailuresFor,
}) async {
  final ble = FakeBleRepository(
    devices: const [
      FakeDevice(id: 'L1', name: 'WheelAthlete-M5-L', rssi: -40),
      FakeDevice(id: 'R1', name: 'WheelAthlete-M5-R', rssi: -42),
    ],
    infoFor: const {
      'L1': _deviceInfo,
      'R1': DeviceInfo(
        wheelId: WheelId.right,
        fwMajor: 1,
        fwMinor: 6,
        fwPatch: 1,
        accelRange: 0,
        gyroRange: 3,
        accelScale: 1 / 16384,
        gyroScale: 1 / 16.4,
      ),
    },
    autoAcknowledgeControls: true,
    stopWriteFailuresFor: stopWriteFailuresFor,
  );
  final container = ProviderContainer(
    overrides: [
      bleRepositoryProvider.overrideWith((ref) => ble),
      rssiPollIntervalProvider.overrideWith((ref) => null),
      interConnectSettleDelayProvider.overrideWith((ref) => Duration.zero),
      liveAckTimeoutProvider.overrideWith(
        (ref) => const Duration(milliseconds: 10),
      ),
      stopCommandRetryDelayProvider.overrideWith((ref) => Duration.zero),
    ],
  );
  final manager = container.read(connectionManagerProvider.notifier);
  await manager.connect('L1');
  await manager.connect('R1');
  await container.read(liveAcquisitionProvider.notifier).start();
  expect(
    container.read(liveAcquisitionProvider).status,
    LiveAcquisitionStatus.live,
  );
  return (ble, container);
}

void main() {
  test('starting and stopping acquisition are not toggleable', () {
    expect(
      const LiveAcquisitionState(
        status: LiveAcquisitionStatus.starting,
      ).canToggle,
      isFalse,
    );
    expect(
      const LiveAcquisitionState(
        status: LiveAcquisitionStatus.stopping,
      ).canToggle,
      isFalse,
    );
    expect(
      const LiveAcquisitionState(status: LiveAcquisitionStatus.live).canToggle,
      isTrue,
    );
  });

  test(
    'transient STOP write failure is retried without disconnecting',
    () async {
      final (ble, container) = await _connectedLiveContainer(
        stopWriteFailuresFor: const {'R1': 1},
      );
      addTearDown(container.dispose);

      await container.read(liveAcquisitionProvider.notifier).stop();

      expect(
        container.read(liveAcquisitionProvider).status,
        LiveAcquisitionStatus.idle,
      );
      expect(
        ble.allControlWrites('R1').where((bytes) => bytes.first == 0x02),
        hasLength(2),
      );
      expect(ble.disconnectCount('L1'), 0);
      expect(ble.disconnectCount('R1'), 0);
    },
  );

  test(
    'persistent STOP failure force-disconnects only the failed board',
    () async {
      final (ble, container) = await _connectedLiveContainer(
        stopWriteFailuresFor: const {'R1': 10},
      );
      addTearDown(container.dispose);

      await container.read(liveAcquisitionProvider.notifier).stop();

      final live = container.read(liveAcquisitionProvider);
      expect(live.status, LiveAcquisitionStatus.failed);
      expect(live.activeSides, isEmpty);
      expect(live.failedSide, WheelSide.right);
      expect(live.error, contains('disconnected for safety'));
      expect(ble.disconnectCount('L1'), 0);
      expect(ble.disconnectCount('R1'), 1);
      expect(
        container
            .read(connectionManagerProvider)
            .bySide[WheelSide.right]!
            .status,
        ConnectionStatus.disconnected,
      );
    },
  );
}
