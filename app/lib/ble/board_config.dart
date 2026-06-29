import 'dart:typed_data';

import 'package:wheelathlete/ble/wheel_id.dart';

/// Parsed contents of the Config characteristic (a1b7, 22 bytes).
///
/// Layout (Phase 2 §1.2):
/// ```
/// [name 16B ASCII null-padded][wheel_id 1B][rate_hz 2B LE]
/// [fw_major 1B][fw_minor 1B][fw_patch 1B]
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
  });

  /// Board name (up to 16 ASCII chars, null-padded in the raw payload).
  final String name;

  /// Wheel side byte: 0x4C = 'L', 0x52 = 'R'.
  final WheelId wheelId;

  /// Sampling rate in Hz (50 / 100 / 200).
  final int rateHz;

  final int fwMajor;
  final int fwMinor;
  final int fwPatch;

  String get fwVersion => '$fwMajor.$fwMinor.$fwPatch';

  /// Parses the 22-byte Config payload (little-endian) per Phase 2 §1.2.
  ///
  /// Throws [ArgumentError] if [bytes] is not exactly 22 bytes.
  /// Throws [FormatException] if `wheel_id` is not 0x4C/0x52.
  factory BoardConfig.parse(List<int> bytes) {
    if (bytes.length != 22) {
      throw ArgumentError(
        'Config payload must be 22 bytes, got ${bytes.length}',
        'bytes',
      );
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    // Name: first 16 bytes, ASCII, strip trailing nulls.
    final nameBytes = bytes.sublist(0, 16);
    final name = String.fromCharCodes(
      nameBytes.takeWhile((b) => b != 0),
    );
    return BoardConfig(
      name: name,
      wheelId: WheelId.fromByte(data.getUint8(16)),
      rateHz: data.getUint16(17, Endian.little),
      fwMajor: data.getUint8(19),
      fwMinor: data.getUint8(20),
      fwPatch: data.getUint8(21),
    );
  }
}
