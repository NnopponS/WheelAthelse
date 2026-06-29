import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/control_command.dart';

void main() {
  group('ControlCommand encode (§3.1)', () {
    test('START with target_start_us → [0x01][u32 LE]', () {
      final bytes = ControlCommand.start(123456789);
      expect(bytes, [0x01, ..._u32LE(123456789)]);
      expect(bytes.length, 5);
    });

    test('START with 0 (immediate) → [0x01][0x00000000]', () {
      expect(ControlCommand.start(0), [0x01, 0, 0, 0, 0]);
    });

    test('STOP → [0x02] (1 byte, no payload)', () {
      expect(ControlCommand.stop(), [0x02]);
    });

    test('SET_RATE with 100 Hz → [0x03][u16 LE]', () {
      final bytes = ControlCommand.setRate(100);
      expect(bytes, [0x03, ..._u16LE(100)]);
      expect(bytes.length, 3);
    });

    test('SET_RATE with 50 and 200 Hz', () {
      expect(ControlCommand.setRate(50), [0x03, 50, 0]);
      expect(ControlCommand.setRate(200), [0x03, 0xC8, 0]);
    });

    test('SET_RATE throws ArgumentError for invalid rate', () {
      expect(() => ControlCommand.setRate(75), throwsArgumentError);
      expect(() => ControlCommand.setRate(0), throwsArgumentError);
      expect(() => ControlCommand.setRate(500), throwsArgumentError);
    });

    test('SYNC_PING with t_app_ms → [0x04][u32 LE]', () {
      final bytes = ControlCommand.syncPing(999999);
      expect(bytes, [0x04, ..._u32LE(999999)]);
      expect(bytes.length, 5);
    });

    test('SET_RANGE → [0x05][accel_range][gyro_range]', () {
      final bytes = ControlCommand.setRange(accelRange: 2, gyroRange: 1);
      expect(bytes, [0x05, 2, 1]);
      expect(bytes.length, 3);
    });

    test('SET_RANGE throws ArgumentError for out-of-range codes', () {
      expect(() => ControlCommand.setRange(accelRange: 4, gyroRange: 0),
          throwsArgumentError);
      expect(() => ControlCommand.setRange(accelRange: 0, gyroRange: 5),
          throwsArgumentError);
    });

    test('BEEP → [0x06][count][period_ms u16 LE]', () {
      final bytes = ControlCommand.beep(count: 3, periodMs: 1000);
      expect(bytes, [0x06, 3, ..._u16LE(1000)]);
      expect(bytes.length, 4);
    });

    test('BEEP throws ArgumentError for count=0', () {
      expect(() => ControlCommand.beep(count: 0, periodMs: 500),
          throwsArgumentError);
    });

    test('RESET_SEQ → [0xFF] (1 byte, no payload)', () {
      expect(ControlCommand.resetSeq(), [0xFF]);
    });

    test('SET_UTC with epoch ms → [0x09][u64 LE]', () {
      final bytes = ControlCommand.setUtc(1719691200456);
      expect(bytes.length, 9);
      expect(bytes[0], 0x09);
      expect(bytes.sublist(1), _u64LE(1719691200456));
    });

    test('SET_UTC with 0 → [0x09][0x0000000000000000]', () {
      expect(ControlCommand.setUtc(0), [0x09, 0, 0, 0, 0, 0, 0, 0, 0]);
    });
  });

  group('ControlCommand new encoders (Phase 2 §3.1)', () {
    test('SET_NAME → [0x07][16-byte name null-padded]', () {
      final bytes = ControlCommand.setName('MyBoard');
      expect(bytes[0], 0x07);
      expect(bytes.length, 17);
      // 'MyBoard' = 7 chars, rest null.
      expect(bytes.sublist(1, 8), 'MyBoard'.codeUnits);
      expect(bytes.sublist(8), everyElement(0));
    });

    test('SET_NAME truncates to 16 bytes', () {
      final bytes = ControlCommand.setName('A very long board name!');
      expect(bytes.length, 17);
      expect(bytes.sublist(1).where((b) => b != 0).length, 16);
    });

    test('SET_NAME with empty string → all nulls after cmd', () {
      final bytes = ControlCommand.setName('');
      expect(bytes[0], 0x07);
      expect(bytes.sublist(1), everyElement(0));
    });

    test('SET_WHEEL with 0x4C (L) → [0x08][0x4C]', () {
      expect(ControlCommand.setWheel(0x4C), [0x08, 0x4C]);
    });

    test('SET_WHEEL with 0x52 (R) → [0x08][0x52]', () {
      expect(ControlCommand.setWheel(0x52), [0x08, 0x52]);
    });

    test('SET_WHEEL throws ArgumentError for invalid byte', () {
      expect(() => ControlCommand.setWheel(0x00), throwsArgumentError);
      expect(() => ControlCommand.setWheel(0x41), throwsArgumentError);
    });
  });

  group('ControlCommand.cmd constants', () {
    test('match the protocol §3.1 values', () {
      expect(ControlCommandId.start, 0x01);
      expect(ControlCommandId.stop, 0x02);
      expect(ControlCommandId.setRate, 0x03);
      expect(ControlCommandId.syncPing, 0x04);
      expect(ControlCommandId.setRange, 0x05);
      expect(ControlCommandId.beep, 0x06);
      expect(ControlCommandId.setName, 0x07);
      expect(ControlCommandId.setWheel, 0x08);
      expect(ControlCommandId.setUtc, 0x09);
      expect(ControlCommandId.resetSeq, 0xFF);
    });
  });
}

List<int> _u32LE(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _u16LE(int v) {
  final b = ByteData(2)..setUint16(0, v, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _u64LE(int v) {
  final b = ByteData(8)..setUint64(0, v, Endian.little);
  return b.buffer.asUint8List();
}
