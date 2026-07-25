import 'package:wheelathlete/theme/theme.dart';

/// Wheel identity as reported by the firmware in the Info characteristic
/// (§5, byte 0). Mirrors the firmware's `wheel_id` byte — `0x4C` = 'L',
/// `0x52` = 'R'.
enum WheelId {
  left(0x4C, 'L'),
  right(0x52, 'R');

  const WheelId(this.byte, this.label);

  final int byte;
  final String label;

  /// Parses the raw `wheel_id` byte from the Info characteristic.
  ///
  /// Throws [FormatException] for any byte that is not `0x4C` or `0x52` —
  /// this guards against connecting to a device that is not a WheelAthlete
  /// sensor or that has a corrupted Info payload.
  static WheelId fromByte(int byte) {
    switch (byte) {
      case 0x4C:
        return WheelId.left;
      case 0x52:
        return WheelId.right;
      default:
        throw FormatException(
          'Unknown wheel_id byte 0x${byte.toRadixString(16).padLeft(2, '0')} '
          '(expected 0x4C=L or 0x52=R)',
          byte,
        );
    }
  }

  /// Maps to the UI-level [WheelSide] used by the design system.
  WheelSide toWheelSide() => switch (this) {
    WheelId.left => WheelSide.left,
    WheelId.right => WheelSide.right,
  };
}
