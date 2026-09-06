import 'dart:typed_data';

import 'package:wheelathlete/ble/ble_uuids.dart';
import 'package:wheelathlete/ble/device_info.dart';

/// One raw IMU sample as received from the firmware (protocol §2.1, 20 bytes).
///
/// All axis values are kept as raw int16 LSB until [toReading] converts them
/// to physical units using the per-device scales from [DeviceInfo]. Keeping
/// raw values here means the parser is independent of the active range and
/// can be unit-tested without constructing a [DeviceInfo].
class ImuSample {
  const ImuSample({
    required this.seq,
    required this.tDeviceUs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  /// Sample sequence number from firmware (wraps at 2^32). Used to detect
  /// packet loss / dropped samples.
  final int seq;

  /// `micros()` on the M5 at the moment the sample was taken (µs, wraps at
  /// ~71.58 min). Used by the clock-sync engine (subtask #7) to map onto the
  /// common phone timeline.
  final int tDeviceUs;

  // Raw int16 LSB values — convert via [toReading].
  final int ax, ay, az;
  final int gx, gy, gz;

  /// Parses a single 20-byte sample at [offset] (little-endian, §2.1).
  ///
  /// Throws [ArgumentError] if the buffer is too short for one sample at the
  /// given offset.
  factory ImuSample.parse(List<int> bytes, {int offset = 0}) {
    final end = offset + BleUuids.imuSampleSize;
    if (bytes.length < end) {
      throw ArgumentError(
        'IMU sample needs ${BleUuids.imuSampleSize} bytes at offset $offset, '
            'buffer has ${bytes.length}',
        'bytes',
      );
    }
    final payload = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final data = ByteData.sublistView(payload, offset, end);
    return ImuSample(
      seq: data.getUint32(0, Endian.little),
      tDeviceUs: data.getUint32(4, Endian.little),
      ax: data.getInt16(8, Endian.little),
      ay: data.getInt16(10, Endian.little),
      az: data.getInt16(12, Endian.little),
      gx: data.getInt16(14, Endian.little),
      gy: data.getInt16(16, Endian.little),
      gz: data.getInt16(18, Endian.little),
    );
  }

  /// Converts raw LSB values to physical units (g and dps) using the scales
  /// reported by the device in its Info characteristic (§2.3, §5).
  ///
  /// `accel_g = raw * accelScale`, `gyro_dps = raw * gyroScale`.
  ImuReading toReading(DeviceInfo info) => ImuReading(
    seq: seq,
    tDeviceUs: tDeviceUs,
    ax: ax * info.accelScale,
    ay: ay * info.accelScale,
    az: az * info.accelScale,
    gx: gx * info.gyroScale,
    gy: gy * info.gyroScale,
    gz: gz * info.gyroScale,
  );
}

/// An [ImuSample] converted to physical units (g for accel, dps for gyro).
///
/// Produced by [ImuSample.toReading]. This is what the realtime display and
/// the CSV exporter consume.
class ImuReading {
  const ImuReading({
    required this.seq,
    required this.tDeviceUs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  final int seq;
  final int tDeviceUs;

  // Physical units: accel in g, gyro in dps.
  final double ax, ay, az;
  final double gx, gy, gz;
}

/// Result of parsing a batch with seq-gap tracking.
class ParsedBatch {
  const ParsedBatch({required this.samples, required this.newGaps});

  final List<ImuSample> samples;

  /// Number of samples missing between this batch's seq numbers and the
  /// previously expected seq (cumulative across batches is on the tracker).
  final int newGaps;
}

/// Tracks the next expected `seq` across batches to detect dropped samples
/// (protocol §8: "ถ้า seq กระโดด → app บันทึก gap").
///
/// Stateless parsing would miss gaps that span batch boundaries, so the
/// realtime state holder keeps one of these and passes it to
/// [ImuPacketParser.parseBatchWithGaps].
class ImuSeqTracker {
  int _expectedNext = -1;
  int _totalGaps = 0;

  /// The seq we expect the next sample to have. `-1` before the first sample.
  int get expectedNext => _expectedNext;

  /// Cumulative number of missing samples seen so far across all batches.
  int get totalGaps => _totalGaps;

  /// Records [seq] and returns how many samples were skipped since the last
  /// expected seq. Returns 0 for the first sample, for contiguous samples,
  /// and for out-of-order / duplicate late samples (already-seen seq does not
  /// count as a forward gap).
  int gapCount(int seq) {
    if (_expectedNext < 0) {
      _expectedNext = (seq + 1) & 0xFFFFFFFF;
      return 0;
    }
    if (seq == _expectedNext) {
      _expectedNext = (seq + 1) & 0xFFFFFFFF;
      return 0;
    }
    // Forward gap: seq is strictly ahead of expected.
    // Compute wrapped distance so it works across the 2^32 boundary.
    final gap = (seq - _expectedNext) & 0xFFFFFFFF;
    if (gap > 0 && gap < 0x80000000) {
      _totalGaps += gap;
      _expectedNext = (seq + 1) & 0xFFFFFFFF;
      return gap;
    }
    // seq is behind expected (late / duplicate) — not a forward gap.
    return 0;
  }
}

/// Pure parser for the IMU Data characteristic notify payload (§2).
///
/// All methods are static and side-effect free so they can be unit-tested
/// without any BLE plumbing. The realtime state holder (subtask #6) wraps
/// these with a Riverpod notifier that feeds in the live notify stream.
class ImuPacketParser {
  const ImuPacketParser._(); // coverage:ignore-line

  /// Parses a batch packet `[uint8 count][sample_0]...[sample_{count-1}]`
  /// (§2.2) into a list of [ImuSample]s.
  ///
  /// Throws [ArgumentError] if the buffer is empty or shorter than the count
  /// byte promises. Throws [FormatException] if `count == 0` (firmware must
  /// always send at least one sample per notify).
  static List<ImuSample> parseBatch(List<int> bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError('IMU batch is empty', 'bytes');
    }
    final count = bytes[0];
    if (count == 0) {
      throw const FormatException(
        'IMU batch count is 0 (firmware must send ≥1 sample)',
      );
    }
    final expectedLen = 1 + count * BleUuids.imuSampleSize;
    if (bytes.length != expectedLen) {
      throw ArgumentError(
        'IMU batch length mismatch: count=$count expects $expectedLen bytes, '
            'got ${bytes.length}',
        'bytes',
      );
    }
    final payload = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    return List.generate(
      count,
      (i) => ImuSample.parse(payload, offset: 1 + i * BleUuids.imuSampleSize),
      growable: false,
    );
  }

  /// Parses a batch and updates [tracker] with each sample's seq, returning
  /// the samples plus the number of new gaps detected in this batch.
  static ParsedBatch parseBatchWithGaps(
    List<int> bytes,
    ImuSeqTracker tracker,
  ) {
    final samples = parseBatch(bytes);
    var newGaps = 0;
    for (final s in samples) {
      newGaps += tracker.gapCount(s.seq);
    }
    return ParsedBatch(samples: samples, newGaps: newGaps);
  }
}
