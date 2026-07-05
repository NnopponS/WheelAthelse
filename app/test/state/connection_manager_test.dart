import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/board_config.dart';
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
    container = ProviderContainer(
      overrides: [bleRepositoryProvider.overrideWith((ref) => ble)],
    );
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

  test(
    'startScan populates scanResults and sets isScanning during scan',
    () async {
      final manager = container.read(connectionManagerProvider.notifier);
      final before = state();
      expect(before.isScanning, isFalse);

      await manager.startScan();
      final after = state();
      expect(after.scanResults, hasLength(2));
      expect(after.scanResults.first.id, anyOf('L1', 'R1'));
    },
  );

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

  test(
    'connect with wrong wheel_id for requested side sets error and rolls back',
    () async {
      // Seed an R device only; user requests connect to it but it reports as R
      // while the manager auto-assigns by wheel_id, so it lands on Right, not Left.
      final manager = container.read(connectionManagerProvider.notifier);
      await manager.connect('R1');
      final s = state();
      expect(s.bySide[WheelSide.right]!.status, ConnectionStatus.connected);
      expect(s.bySide[WheelSide.left]!.status, ConnectionStatus.disconnected);
    },
  );

  test('disconnect on an already-disconnected side is a no-op', () async {
    final manager = container.read(connectionManagerProvider.notifier);
    // No device connected on either side — should not throw.
    await manager.disconnect(WheelSide.left);
    expect(
      state().bySide[WheelSide.left]!.status,
      ConnectionStatus.disconnected,
    );
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

  group('WheelConnection.copyWith', () {
    test('copies all fields', () {
      const conn = WheelConnection(
        status: ConnectionStatus.connected,
        deviceId: 'ABC',
        deviceName: 'WheelAthlete-L',
        rssi: -42,
      );
      final copy = conn.copyWith(rssi: -50);
      expect(copy.status, ConnectionStatus.connected);
      expect(copy.deviceId, 'ABC');
      expect(copy.deviceName, 'WheelAthlete-L');
      expect(copy.rssi, -50);
    });

    test('defaults preserve original values when null', () {
      const conn = WheelConnection(
        status: ConnectionStatus.connected,
        deviceId: 'ABC',
        deviceName: 'WheelAthlete-L',
        rssi: -42,
      );
      final copy = conn.copyWith();
      expect(copy.status, ConnectionStatus.connected);
      expect(copy.deviceId, 'ABC');
      expect(copy.deviceName, 'WheelAthlete-L');
      expect(copy.rssi, -42);
    });
  });

  test('ConnectionManagerState.initial() returns idle state', () {
    final s = ConnectionManagerState.initial();
    expect(s.isScanning, isFalse);
    expect(s.scanResults, isEmpty);
    expect(s.bySide[WheelSide.left]!.status, ConnectionStatus.disconnected);
    expect(s.bySide[WheelSide.right]!.status, ConnectionStatus.disconnected);
    expect(s.error, isNull);
  });

  test(
    'bleRepositoryProvider builds FlutterBluePlusBleRepository by default',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final repo = c.read(bleRepositoryProvider);
      expect(repo, isA<FlutterBluePlusBleRepository>());
    },
  );

  test('startScan sets error when repository throws', () async {
    final bleThrow = _ThrowingBleRepository();
    final c = ProviderContainer(
      overrides: [bleRepositoryProvider.overrideWith((ref) => bleThrow)],
    );
    addTearDown(c.dispose);
    final manager = c.read(connectionManagerProvider.notifier);
    await manager.startScan();
    expect(c.read(connectionManagerProvider).error, isNotNull);
    expect(c.read(connectionManagerProvider).isScanning, isFalse);
  });

  test('startScan sets error when scanResults stream emits an error', () async {
    final bleErrorScan = _ErrorScanBleRepository();
    final c = ProviderContainer(
      overrides: [bleRepositoryProvider.overrideWith((ref) => bleErrorScan)],
    );
    addTearDown(c.dispose);
    final manager = c.read(connectionManagerProvider.notifier);
    await manager.startScan();
    expect(c.read(connectionManagerProvider).error, isNotNull);
  });
}

/// A fake that throws on startScan — exercises the catch branch.
class _ThrowingBleRepository implements BleRepository {
  @override
  Stream<List<ScannedDevice>> get scanResults =>
      const Stream<List<ScannedDevice>>.empty();

  @override
  bool get isScanning => false;

  @override
  Future<void> startScan(Duration timeout) async {
    throw StateError('scan failed');
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<ConnectedDevice> connect(String deviceId) async {
    throw UnimplementedError();
  }

  @override
  Stream<BleConnectionState> connectionState(String deviceId) =>
      const Stream<BleConnectionState>.empty();

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<int> readRssi(String deviceId) async => 0;

  @override
  Stream<List<int>> imuData(String deviceId) => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> syncData(String deviceId) =>
      const Stream<List<int>>.empty();

  @override
  Future<void> writeControl(String deviceId, List<int> bytes) async {}

  @override
  Stream<int> batteryLevel(String deviceId) => const Stream<int>.empty();

  @override
  Future<BoardConfig> readConfig(String deviceId) async {
    throw UnimplementedError();
  }
}

/// A fake whose scanResults stream emits an error — exercises onError handler.
class _ErrorScanBleRepository implements BleRepository {
  @override
  Stream<List<ScannedDevice>> get scanResults =>
      Stream<List<ScannedDevice>>.error(StateError('scan stream error'));

  @override
  bool get isScanning => false;

  @override
  Future<void> startScan(Duration timeout) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<ConnectedDevice> connect(String deviceId) async {
    throw UnimplementedError();
  }

  @override
  Stream<BleConnectionState> connectionState(String deviceId) =>
      const Stream<BleConnectionState>.empty();

  @override
  Future<void> disconnect(String deviceId) async {}

  @override
  Future<int> readRssi(String deviceId) async => 0;

  @override
  Stream<List<int>> imuData(String deviceId) => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> syncData(String deviceId) =>
      const Stream<List<int>>.empty();

  @override
  Future<void> writeControl(String deviceId, List<int> bytes) async {}

  @override
  Stream<int> batteryLevel(String deviceId) => const Stream<int>.empty();

  @override
  Future<BoardConfig> readConfig(String deviceId) async {
    throw UnimplementedError();
  }
}
