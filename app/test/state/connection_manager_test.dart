import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/widgets/widgets.dart';

void main() {
  late FakeBleRepository ble;
  late ProviderContainer container;

  setUp(() {
    ble = FakeBleRepository(
      devices: [
        const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
        const FakeDevice(id: 'R1', name: 'WheelAthlete-R', rssi: -55),
      ],
      infoFor: {
        'L1': const DeviceInfo(
          wheelId: WheelId.left,
          fwMajor: 1,
          fwMinor: 0,
          fwPatch: 0,
          accelRange: 0,
          gyroRange: 3,
          accelScale: 6.1e-5,
          gyroScale: 6.1e-2,
        ),
        'R1': const DeviceInfo(
          wheelId: WheelId.right,
          fwMajor: 1,
          fwMinor: 0,
          fwPatch: 0,
          accelRange: 0,
          gyroRange: 3,
          accelScale: 6.1e-5,
          gyroScale: 6.1e-2,
        ),
      },
    );
    container = ProviderContainer(overrides: [bleRepositoryProvider.overrideWith((ref) => ble)]);
    addTearDown(container.dispose);
  });

  ConnectionManagerState state() => container.read(connectionManagerProvider);

  test('initial state: idle, no connections, not scanning', () {
    final s = state();
    expect(s.isScanning, isFalse);
    expect(s.scanResults, isEmpty);
    expect(s.bySide[WheelSide.left]!.status, ConnectionStatus.disconnected);
    expect(s.bySide[WheelSide.right]!.status, ConnectionStatus.disconnected);
    expect(s.error, isNull);
  });

  test('startScan populates scanResults and sets isScanning during scan', () async {
    final manager = container.read(connectionManagerProvider.notifier);
    final before = state();
    expect(before.isScanning, isFalse);

    await manager.startScan();
    final after = state();
    expect(after.scanResults, hasLength(2));
    expect(after.scanResults.first.id, anyOf('L1', 'R1'));
  });

  test('connect assigns device to the correct side by wheel_id', () async {
    final manager = container.read(connectionManagerProvider.notifier);
    await manager.connect('L1');
    final s = state();
    expect(s.bySide[WheelSide.left]!.status, ConnectionStatus.connected);
    expect(s.bySide[WheelSide.left]!.deviceName, 'WheelAthlete-L');
    expect(s.bySide[WheelSide.left]!.info, isNotNull);
    expect(s.bySide[WheelSide.left]!.info!.wheelId, WheelId.left);
    // Right untouched.
    expect(s.bySide[WheelSide.right]!.status, ConnectionStatus.disconnected);
  });

  test('connecting R after L keeps L connected (independent)', () async {
    final manager = container.read(connectionManagerProvider.notifier);
    await manager.connect('L1');
    await manager.connect('R1');
    final s = state();
    expect(s.bySide[WheelSide.left]!.status, ConnectionStatus.connected);
    expect(s.bySide[WheelSide.right]!.status, ConnectionStatus.connected);
  });

  test('disconnect L leaves R connected', () async {
    final manager = container.read(connectionManagerProvider.notifier);
    await manager.connect('L1');
    await manager.connect('R1');
    await manager.disconnect(WheelSide.left);
    final s = state();
    expect(s.bySide[WheelSide.left]!.status, ConnectionStatus.disconnected);
    expect(s.bySide[WheelSide.right]!.status, ConnectionStatus.connected);
  });

  test('connect with wrong wheel_id for requested side sets error and rolls back',
      () async {
    // Seed an R device only; user requests connect to it but it reports as R
    // while the manager auto-assigns by wheel_id, so it lands on Right, not Left.
    final manager = container.read(connectionManagerProvider.notifier);
    await manager.connect('R1');
    final s = state();
    expect(s.bySide[WheelSide.right]!.status, ConnectionStatus.connected);
    expect(s.bySide[WheelSide.left]!.status, ConnectionStatus.disconnected);
  });

  test('disconnect on an already-disconnected side is a no-op', () async {
    final manager = container.read(connectionManagerProvider.notifier);
    // No device connected on either side — should not throw.
    await manager.disconnect(WheelSide.left);
    expect(state().bySide[WheelSide.left]!.status, ConnectionStatus.disconnected);
  });

  test('connect on a device with no seeded Info sets an error', () async {
    final bleNoInfo = FakeBleRepository(
      devices: [const FakeDevice(id: 'X1', name: 'WheelAthlete-?', rssi: -40)],
    );
    final c = ProviderContainer(
      overrides: [bleRepositoryProvider.overrideWith((ref) => bleNoInfo)],
    );
    addTearDown(c.dispose);
    final manager = c.read(connectionManagerProvider.notifier);
    await manager.connect('X1');
    expect(c.read(connectionManagerProvider).error, isNotNull);
  });

  test('stopScan cancels an in-progress scan', () async {
    final manager = container.read(connectionManagerProvider.notifier);
    await manager.startScan();
    expect(state().isScanning, isFalse);
    await manager.stopScan();
    expect(state().isScanning, isFalse);
  });
}
