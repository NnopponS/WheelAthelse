import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_uuids.dart';

void main() {
  group('BleUuids', () {
    test('service UUID matches protocol §1 (a1b2 base)', () {
      expect(
        BleUuids.service,
        '0000a1b2-0000-1000-8000-00805f9b34fb',
      );
    });

    test('characteristic UUIDs match protocol §1.1', () {
      expect(BleUuids.imuData, '0000a1b3-0000-1000-8000-00805f9b34fb');
      expect(BleUuids.control, '0000a1b4-0000-1000-8000-00805f9b34fb');
      expect(BleUuids.sync, '0000a1b5-0000-1000-8000-00805f9b34fb');
      expect(BleUuids.info, '0000a1b6-0000-1000-8000-00805f9b34fb');
    });

    test('packet sizes match ble_types.h constants', () {
      expect(BleUuids.imuSampleSize, 20);
      expect(BleUuids.syncResponseSize, 12);
      expect(BleUuids.infoSize, 16);
    });

    test('default MTU request value is 247 (protocol §1 note)', () {
      expect(BleUuids.defaultMtu, 247);
    });
  });
}
