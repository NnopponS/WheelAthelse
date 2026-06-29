import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/theme/theme.dart';

void main() {
  group('WheelId.fromByte', () {
    test('0x4C maps to left (protocol §5)', () {
      expect(WheelId.fromByte(0x4C), WheelId.left);
    });

    test('0x52 maps to right (protocol §5)', () {
      expect(WheelId.fromByte(0x52), WheelId.right);
    });

    test('any other byte throws FormatException', () {
      expect(() => WheelId.fromByte(0x00), throwsFormatException);
      expect(() => WheelId.fromByte(0x4D), throwsFormatException);
      expect(() => WheelId.fromByte(0xFF), throwsFormatException);
    });
  });

  group('WheelId.toWheelSide', () {
    test('left → WheelSide.left', () {
      expect(WheelId.left.toWheelSide(), WheelSide.left);
    });

    test('right → WheelSide.right', () {
      expect(WheelId.right.toWheelSide(), WheelSide.right);
    });
  });

  group('WheelId.byte / label', () {
    test('byte round-trips', () {
      expect(WheelId.left.byte, 0x4C);
      expect(WheelId.right.byte, 0x52);
    });

    test('label is single char L/R', () {
      expect(WheelId.left.label, 'L');
      expect(WheelId.right.label, 'R');
    });
  });
}
