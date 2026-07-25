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
  static const int setName = 0x07;
  static const int setWheel = 0x08;
  static const int setUtc = 0x09;
  static const int replayRange = 0x0A;
  static const int setBeepEnabled = 0x0B;
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
  ///
  /// The firmware expects a uint32 (0..4294967295). Values outside this
  /// range are wrapped to uint32 to match the firmware's `micros()` wrap
  /// behavior (every ~71 minutes at 4.29e9 µs).
  static List<int> start(int targetStartUs) {
    // Wrap to uint32 range — matches firmware's micros() wrap behavior.
    final wrapped = targetStartUs.toUnsigned(32);
    final b = ByteData(5)
      ..setUint8(0, ControlCommandId.start)
      ..setUint32(1, wrapped, Endian.little);
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
      throw ArgumentError(
        'accelRange must be 0–3, got $accelRange',
        'accelRange',
      );
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

  /// `SET_NAME` (0x07): set the board name (persisted to NVS by firmware).
  /// [name] is truncated/padded to exactly 24 bytes (ASCII, null-padded).
  static List<int> setName(String name) {
    final encoded = name.codeUnits.take(24).toList();
    final padded = List<int>.filled(25, 0);
    padded[0] = ControlCommandId.setName;
    for (var i = 0; i < encoded.length; i++) {
      padded[1 + i] = encoded[i] & 0xFF;
    }
    return padded;
  }

  /// `SET_WHEEL` (0x08): set the wheel side. [wheelByte] must be 0x4C ('L')
  /// or 0x52 ('R').
  static List<int> setWheel(int wheelByte) {
    if (wheelByte != 0x4C && wheelByte != 0x52) {
      throw ArgumentError(
        'wheelByte must be 0x4C (L) or 0x52 (R), got 0x${wheelByte.toRadixString(16)}',
        'wheelByte',
      );
    }
    return Uint8List.fromList([ControlCommandId.setWheel, wheelByte]);
  }

  /// `SET_UTC` (0x09): set the board's UTC epoch reference (ms since Unix
  /// epoch). Used for camera alignment — the board stamps START_FIRED with
  /// the UTC instant. Payload is uint64 LE (8 bytes).
  static List<int> setUtc(int epochMs) {
    final b = ByteData(9)..setUint8(0, ControlCommandId.setUtc);
    // Write uint64 LE manually (ByteData.setUint64 may not be available on
    // all platforms; use two uint32 writes).
    b.setUint32(1, epochMs & 0xFFFFFFFF, Endian.little);
    b.setUint32(5, (epochMs >> 32) & 0xFFFFFFFF, Endian.little);
    return b.buffer.asUint8List();
  }

  /// `REPLAY_RANGE` (0x0A): retransmit a bounded sequence range from the
  /// protocol 1.3 firmware history buffer.
  static List<int> replayRange({required int startSeq, required int count}) {
    if (count < 1 || count > 128) {
      throw RangeError.range(count, 1, 128, 'count');
    }
    final b = ByteData(7)
      ..setUint8(0, ControlCommandId.replayRange)
      ..setUint32(1, startSeq.toUnsigned(32), Endian.little)
      ..setUint16(5, count, Endian.little);
    return b.buffer.asUint8List();
  }

  /// `SET_BEEP_ENABLED` (0x0B): persist the countdown sound preference.
  static List<int> setBeepEnabled(bool enabled) =>
      Uint8List.fromList([ControlCommandId.setBeepEnabled, enabled ? 1 : 0]);

  /// `RESET_SEQ` (0xFF): reset the sample sequence counter to 0.
  static List<int> resetSeq() =>
      Uint8List.fromList([ControlCommandId.resetSeq]);
}
