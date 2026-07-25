import 'dart:typed_data';

import 'package:wheelathlete/ble/ble_uuids.dart';
import 'package:wheelathlete/ble/wheel_id.dart';

/// Parsed contents of the Info characteristic (§5, 16 bytes).
///
/// Read once per device right after connect. Holds everything the app needs
/// to convert raw IMU samples to physical units and to label the device L/R.
class DeviceInfo {
  const DeviceInfo({
    required this.wheelId,
    required this.fwMajor,
    required this.fwMinor,
    required this.fwPatch,
    required this.accelRange,
    required this.gyroRange,
    required this.accelScale,
    required this.gyroScale,
    this.hardwareModel = HardwareModel.legacy,
    this.capabilities = 0,
  });

  final WheelId wheelId;
  final int fwMajor;
  final int fwMinor;
  final int fwPatch;
  final int accelRange;
  final int gyroRange;

  /// LSB → g conversion factor (depends on `accelRange`).
  final double accelScale;

  /// LSB → dps conversion factor (depends on `gyroRange`).
  final double gyroScale;
  final HardwareModel hardwareModel;
  final int capabilities;

  static const int sampleReplayCapability = 0x01;
  bool get supportsSampleReplay => capabilities & sampleReplayCapability != 0;

  String get fwVersion => '$fwMajor.$fwMinor.$fwPatch';

  /// Human-readable accel range label (e.g. "±2g").
  String get accelRangeName => switch (accelRange) {
    0 => '±2g',
    1 => '±4g',
    2 => '±8g',
    3 => '±16g',
    _ => 'range#$accelRange',
  };

  /// Human-readable gyro range label (e.g. "±2000 dps").
  String get gyroRangeName => switch (gyroRange) {
    0 => '±250 dps',
    1 => '±500 dps',
    2 => '±1000 dps',
    3 => '±2000 dps',
    _ => 'range#$gyroRange',
  };

  /// Parses the 16-byte Info payload (little-endian) per protocol §5.
  ///
  /// Throws [ArgumentError] if [bytes] is not exactly 16 bytes.
  /// Throws [FormatException] if `wheel_id` is not 0x4C/0x52.
  factory DeviceInfo.parse(List<int> bytes) {
    if (bytes.length != BleUuids.infoSize) {
      throw ArgumentError(
        'Info payload must be ${BleUuids.infoSize} bytes, got ${bytes.length}',
        'bytes',
      );
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return DeviceInfo(
      wheelId: WheelId.fromByte(data.getUint8(0)),
      fwMajor: data.getUint8(1),
      fwMinor: data.getUint8(2),
      fwPatch: data.getUint8(3),
      accelRange: data.getUint8(4),
      gyroRange: data.getUint8(5),
      accelScale: data.getFloat32(6, Endian.little),
      gyroScale: data.getFloat32(10, Endian.little),
      hardwareModel: HardwareModel.fromByte(data.getUint8(14)),
      capabilities: data.getUint8(15),
    );
  }
}

enum HardwareModel {
  legacy(0, 'Legacy'),
  m5StickCPlus2(1, 'M5StickC Plus2'),
  xiaoBleSense(2, 'Xiao BLE Sense');

  const HardwareModel(this.id, this.label);
  final int id;
  final String label;

  static HardwareModel fromByte(int value) =>
      HardwareModel.values.where((model) => model.id == value).firstOrNull ??
      legacy;
}
