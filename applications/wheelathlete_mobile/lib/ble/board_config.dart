import 'dart:typed_data';

import 'package:wheelathlete/ble/wheel_id.dart';

/// Parsed contents of the Config characteristic (a1b7).
///
/// Current v1.6 layout:
/// ```
/// [name 24B ASCII null-padded][wheel_id 1B][rate_hz 2B LE]
/// [fw_major 1B][fw_minor 1B][fw_patch 1B][beep_enabled 1B]
/// ```
///
/// Read via `BleRepository.readConfig(deviceId)` to populate the Board
/// Settings screen with the current board name, wheel side, and sample rate.
class BoardConfig {
  const BoardConfig({
    required this.name,
    required this.wheelId,
    required this.rateHz,
    required this.fwMajor,
    required this.fwMinor,
    required this.fwPatch,
    required this.beepEnabled,
  });

  /// Board name (up to 24 ASCII chars, null-padded in the current payload).
  final String name;

  /// Wheel side byte: 0x4C = 'L', 0x52 = 'R'.
  final WheelId wheelId;

  /// Sampling rate in Hz (50 / 100 / 200).
  final int rateHz;

  final int fwMajor;
  final int fwMinor;
  final int fwPatch;

  /// Whether this board emits countdown audio cues. Older configs default on.
  final bool beepEnabled;

  String get fwVersion => '$fwMajor.$fwMinor.$fwPatch';

  /// Parses legacy 22/30-byte and current 31-byte Config payloads.
  ///
  /// Throws [ArgumentError] if [bytes] is not a supported payload size.
  /// Throws [FormatException] if `wheel_id` is not 0x4C/0x52.
  factory BoardConfig.parse(List<int> bytes) {
    if (bytes.length != 22 && bytes.length != 30 && bytes.length != 31) {
      throw ArgumentError(
        'Config payload must be legacy 22/30 bytes or v1.6 31 bytes, got ${bytes.length}',
        'bytes',
      );
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    // Name: first 16 bytes, ASCII, strip trailing nulls.
    final nameLength = bytes.length >= 30 ? 24 : 16;
    final nameBytes = bytes.sublist(0, nameLength);
    final name = String.fromCharCodes(nameBytes.takeWhile((b) => b != 0));
    final beepByte = bytes.length == 31 ? data.getUint8(30) : 1;
    if (beepByte != 0 && beepByte != 1) {
      throw FormatException('Invalid beep_enabled byte: $beepByte');
    }
    return BoardConfig(
      name: name,
      wheelId: WheelId.fromByte(data.getUint8(nameLength)),
      rateHz: data.getUint16(nameLength + 1, Endian.little),
      fwMajor: data.getUint8(nameLength + 3),
      fwMinor: data.getUint8(nameLength + 4),
      fwPatch: data.getUint8(nameLength + 5),
      beepEnabled: beepByte == 1,
    );
  }
}
