import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';

void main() {
  group('DeviceInfo.parse', () {
    Uint8List buildInfo({
      required int wheelId,
      int fwMajor = 1,
      int fwMinor = 0,
      int fwPatch = 0,
      int accelRange = 0,
      int gyroRange = 3,
      double accelScale = 6.103515625e-5, // ±2g
      double gyroScale = 6.1035156e-2, // ±2000 dps
    }) {
      final b = ByteData(16);
      b.setUint8(0, wheelId);
      b.setUint8(1, fwMajor);
      b.setUint8(2, fwMinor);
      b.setUint8(3, fwPatch);
      b.setUint8(4, accelRange);
      b.setUint8(5, gyroRange);
      b.setFloat32(6, accelScale, Endian.little);
      b.setFloat32(10, gyroScale, Endian.little);
      b.setUint16(14, 0, Endian.little);
      return b.buffer.asUint8List();
    }

    test('parses left wheel with ±2g / ±2000dps scales', () {
      final info = DeviceInfo.parse(buildInfo(wheelId: 0x4C));
      expect(info.wheelId, WheelId.left);
      expect(info.fwVersion, '1.0.0');
      expect(info.accelRange, 0);
      expect(info.gyroRange, 3);
      expect(info.accelScale, closeTo(6.103515625e-5, 1e-12));
      expect(info.gyroScale, closeTo(6.1035156e-2, 1e-9));
    });

    test('parses right wheel', () {
      final info = DeviceInfo.parse(buildInfo(wheelId: 0x52, fwMajor: 2));
      expect(info.wheelId, WheelId.right);
      expect(info.fwVersion, '2.0.0');
    });

    test('throws FormatException for unknown wheel_id byte', () {
      expect(
        () => DeviceInfo.parse(buildInfo(wheelId: 0x00)),
        throwsFormatException,
      );
    });

    test('throws ArgumentError when bytes < 16 (truncated)', () {
      expect(
        () => DeviceInfo.parse(Uint8List(15)),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when bytes > 16', () {
      expect(
        () => DeviceInfo.parse(Uint8List(17)),
        throwsArgumentError,
      );
    });

    test('reserved bytes are ignored (do not throw)', () {
      final b = buildInfo(wheelId: 0x4C);
      b[14] = 0xAB;
      b[15] = 0xCD;
      // Should still parse fine — reserved is not validated.
      expect(DeviceInfo.parse(b).wheelId, WheelId.left);
    });
  });

  group('DeviceInfo.accelRangeName / gyroRangeName', () {
    test('maps range codes to human labels', () {
      final base = ByteData(16)
        ..setUint8(0, 0x4C)
        ..setUint8(4, 2)
        ..setUint8(5, 1)
        ..setFloat32(6, 0.0, Endian.little)
        ..setFloat32(10, 0.0, Endian.little);
      final info = DeviceInfo.parse(base.buffer.asUint8List());
      expect(info.accelRangeName, '±8g');
      expect(info.gyroRangeName, '±500 dps');
    });
  });
}
