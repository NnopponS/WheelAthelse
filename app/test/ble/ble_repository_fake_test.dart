import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';

void main() {
  group('FakeBleRepository', () {
    test('scan emits the seeded devices then completes', () async {
      final repo = FakeBleRepository(
        devices: [
          const FakeDevice(id: 'AA', name: 'WheelAthlete-L', rssi: -42),
          const FakeDevice(id: 'BB', name: 'WheelAthlete-R', rssi: -55),
        ],
      );

      final results = <List<ScannedDevice>>[];
      final sub = repo.scanResults.listen(results.add);
      await repo.startScan(const Duration(seconds: 1));
      await sub.cancel();

      expect(results, hasLength(1));
      expect(results.first.map((d) => d.id), ['AA', 'BB']);
      expect(results.first.first.name, 'WheelAthlete-L');
    });

    test('connect returns DeviceInfo parsed from Info bytes', () async {
      const info = DeviceInfo(
        wheelId: WheelId.left,
        fwMajor: 1,
        fwMinor: 2,
        fwPatch: 3,
        accelRange: 0,
        gyroRange: 3,
        accelScale: 6.1e-5,
        gyroScale: 6.1e-2,
      );
      final repo = FakeBleRepository(
        devices: [const FakeDevice(id: 'AA', name: 'WheelAthlete-L', rssi: -40)],
        infoFor: {'AA': info},
      );

      final conn = await repo.connect('AA');
      expect(conn.id, 'AA');
      expect(conn.name, 'WheelAthlete-L');
      expect(conn.info.wheelId, WheelId.left);
      expect(conn.info.fwVersion, '1.2.3');
    });

    test('connectionState stream emits connected then disconnected', () async {
      final repo = FakeBleRepository(
        devices: [const FakeDevice(id: 'AA', name: 'n', rssi: -40)],
        infoFor: {
          'AA': const DeviceInfo(
            wheelId: WheelId.left,
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
      final states = <BleConnectionState>[];
      final sub = repo.connectionState('AA').listen(states.add);
      await repo.connect('AA');
      await repo.disconnect('AA');
      await sub.cancel();
      expect(states, contains(BleConnectionState.connected));
      expect(states, contains(BleConnectionState.disconnected));
    });

    test('connect on unknown id throws StateError', () async {
      final repo = FakeBleRepository(devices: const []);
      expect(() => repo.connect('missing'), throwsStateError);
    });
  });
}
