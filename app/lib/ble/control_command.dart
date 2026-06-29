import 'dart:typed_data';

/// Control command IDs from the Control characteristic (protocol §3.1).
///
/// Mirrors `firmware/src/ble_types.h` `enum class Cmd`.
class ControlCommandId {
  const ControlCommandId._(); // coverage:ignore-line

  static const int start = 0x01;
  static const int stop = 0x02;
  static const int setRate = 0x03;
  static const int syncPing = 0x04;
  static const int setRange = 0x05;
  static const int beep = 0x06;
  static const int resetSeq = 0xFF;
}

/// Encodes commands for the Control characteristic (§3.1).
///
/// Every command starts with a `uint8 cmd` byte followed by its payload,
/// all little-endian. The app writes the returned byte list via
/// `BleRepository.writeControl(deviceId, bytes)`.
class ControlCommand {
  const ControlCommand._(); // coverage:ignore-line

  /// `START` (0x01): begin acquisition at `targetStartUs` (local micros).
  /// Pass 0 for immediate start; pass a scheduled time for synchronized
  /// start across two wheels (§3.2).
  static List<int> start(int targetStartUs) {
    final b = ByteData(5)
      ..setUint8(0, ControlCommandId.start)
      ..setUint32(1, targetStartUs, Endian.little);
    return b.buffer.asUint8List();
  }

  /// `STOP` (0x02): stop acquisition + flush the last batch.
  static List<int> stop() => Uint8List.fromList([ControlCommandId.stop]);

  /// `SET_RATE` (0x03): change sampling rate. Must be called while stopped.
  /// Only 50, 100, or 200 Hz are valid (firmware rejects others).
  static List<int> setRate(int rateHz) {
    if (rateHz != 50 && rateHz != 100 && rateHz != 200) {
      throw ArgumentError(
        'rateHz must be 50, 100, or 200 — got $rateHz',
        'rateHz',
      );
    }
    final b = ByteData(3)
      ..setUint8(0, ControlCommandId.setRate)
      ..setUint16(1, rateHz, Endian.little);
    return b.buffer.asUint8List();
  }

  /// `SYNC_PING` (0x04): send phone timestamp; firmware echoes via Sync
  /// characteristic (§4). Used for clock-offset estimation.
  static List<int> syncPing(int tAppMs) {
    final b = ByteData(5)
      ..setUint8(0, ControlCommandId.syncPing)
      ..setUint32(1, tAppMs, Endian.little);
    return b.buffer.asUint8List();
  }

  /// `SET_RANGE` (0x05): change IMU accel/gyro ranges (0–3 each).
  static List<int> setRange({required int accelRange, required int gyroRange}) {
    if (accelRange < 0 || accelRange > 3) {
      throw ArgumentError('accelRange must be 0–3, got $accelRange', 'accelRange');
    }
    if (gyroRange < 0 || gyroRange > 3) {
      throw ArgumentError('gyroRange must be 0–3, got $gyroRange', 'gyroRange');
    }
    return Uint8List.fromList([
      ControlCommandId.setRange,
      accelRange,
      gyroRange,
    ]);
  }

  /// `BEEP` (0x06): emit `count` beeps with `periodMs` spacing (sync marker).
  static List<int> beep({required int count, required int periodMs}) {
    if (count <= 0) {
      throw ArgumentError('count must be > 0, got $count', 'count');
    }
    final b = ByteData(4)
      ..setUint8(0, ControlCommandId.beep)
      ..setUint8(1, count)
      ..setUint16(2, periodMs, Endian.little);
    return b.buffer.asUint8List();
  }

  /// `RESET_SEQ` (0xFF): reset the sample sequence counter to 0.
  static List<int> resetSeq() => Uint8List.fromList([ControlCommandId.resetSeq]);
}
