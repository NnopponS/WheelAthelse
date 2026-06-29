import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/board_config.dart';
import 'package:wheelathlete/ble/wheel_id.dart';

void main() {
  group('BoardConfig.parse', () {
    List<int> configBytes({
      String name = 'WheelAthlete-L',
      int wheelByte = 0x4C,
      int rateHz = 100,
      int fwMajor = 1,
      int fwMinor = 1,
      int fwPatch = 0,
    }) {
      final bytes = List<int>.filled(22, 0);
      // Name: 16 bytes ASCII null-padded.
      final nameBytes = name.codeUnits;
      for (var i = 0; i < nameBytes.length && i < 16; i++) {
        bytes[i] = nameBytes[i] & 0xFF;
      }
      // wheel_id at offset 16.
      bytes[16] = wheelByte;
      // rate_hz at offset 17 (uint16 LE).
      final b = ByteData(2)..setUint16(0, rateHz, Endian.little);
      bytes[17] = b.getUint8(0);
      bytes[18] = b.getUint8(1);
      // fw version at 19, 20, 21.
      bytes[19] = fwMajor;
      bytes[20] = fwMinor;
      bytes[21] = fwPatch;
      return bytes;
    }

    test('parses a valid 22-byte Config payload', () {
      final config = BoardConfig.parse(configBytes());
      expect(config.name, 'WheelAthlete-L');
      expect(config.wheelId, WheelId.left);
      expect(config.rateHz, 100);
      expect(config.fwMajor, 1);
      expect(config.fwMinor, 1);
      expect(config.fwPatch, 0);
      expect(config.fwVersion, '1.1.0');
    });

    test('parses right wheel with 200 Hz', () {
      final config = BoardConfig.parse(configBytes(
        name: 'Board-R',
        wheelByte: 0x52,
        rateHz: 200,
      ));
      expect(config.name, 'Board-R');
      expect(config.wheelId, WheelId.right);
      expect(config.rateHz, 200);
    });

    test('parses 50 Hz rate', () {
      final config = BoardConfig.parse(configBytes(rateHz: 50));
      expect(config.rateHz, 50);
    });

    test('strips trailing nulls from name', () {
      final bytes = configBytes(name: 'AB');
      // 'AB' + 14 null bytes.
      final config = BoardConfig.parse(bytes);
      expect(config.name, 'AB');
    });

    test('handles empty name (all nulls)', () {
      final bytes = List<int>.filled(22, 0);
      bytes[16] = 0x4C;
      final config = BoardConfig.parse(bytes);
      expect(config.name, '');
    });

    test('truncates name to 16 bytes', () {
      final bytes = configBytes(name: 'A very long board name!');
      final config = BoardConfig.parse(bytes);
      expect(config.name.length, 16);
      expect(config.name, 'A very long boar');
    });

    test('throws ArgumentError for wrong byte count', () {
      expect(() => BoardConfig.parse(List.filled(20, 0)), throwsArgumentError);
      expect(() => BoardConfig.parse(List.filled(24, 0)), throwsArgumentError);
    });

    test('throws FormatException for invalid wheel_id', () {
      final bytes = configBytes(wheelByte: 0x00);
      expect(() => BoardConfig.parse(bytes), throwsFormatException);
    });
  });
}
