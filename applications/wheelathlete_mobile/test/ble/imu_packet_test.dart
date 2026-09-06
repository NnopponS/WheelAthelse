import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_uuids.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/ble/wheel_id.dart';

/// Builds a 20-byte IMU sample (protocol §2.1, little-endian) for tests.
Uint8List buildSample({
  required int seq,
  required int tDeviceUs,
  int ax = 0,
  int ay = 0,
  int az = 0,
  int gx = 0,
  int gy = 0,
  int gz = 0,
}) {
  final b = ByteData(BleUuids.imuSampleSize)
    ..setUint32(0, seq, Endian.little)
    ..setUint32(4, tDeviceUs, Endian.little)
    ..setInt16(8, ax, Endian.little)
    ..setInt16(10, ay, Endian.little)
    ..setInt16(12, az, Endian.little)
    ..setInt16(14, gx, Endian.little)
    ..setInt16(16, gy, Endian.little)
    ..setInt16(18, gz, Endian.little);
  return b.buffer.asUint8List();
}

/// Builds a batch packet `[uint8 count][sample_0]...[sample_{count-1}]` (§2.2).
Uint8List buildBatch(List<Uint8List> samples) {
  final body = BytesBuilder();
  for (final s in samples) {
    body.add(s);
  }
  final out = BytesBuilder()
    ..addByte(samples.length)
    ..add(body.toBytes());
  return out.toBytes();
}

DeviceInfo sampleInfo({
  double accelScale = 1 / 16384, // ±2g → 16384 LSB/g
  double gyroScale = 1 / 16.4, // ±2000 dps → 16.4 LSB/dps (protocol §2.3)
}) {
  return DeviceInfo(
    wheelId: WheelId.left,
    fwMajor: 1,
    fwMinor: 0,
    fwPatch: 0,
    accelRange: 0,
    gyroRange: 3,
    accelScale: accelScale,
    gyroScale: gyroScale,
  );
}

void main() {
  group('ImuSample.parse', () {
    test('parses all 7 fields at the exact byte offsets from §2.1', () {
      final bytes = buildSample(
        seq: 0x11223344,
        tDeviceUs: 0x55667788,
        ax: 100,
        ay: -200,
        az: 16384,
        gx: 1000,
        gy: -1000,
        gz: 0,
      );
      final s = ImuSample.parse(bytes);

      expect(s.seq, 0x11223344);
      expect(s.tDeviceUs, 0x55667788);
      expect(s.ax, 100);
      expect(s.ay, -200);
      expect(s.az, 16384);
      expect(s.gx, 1000);
      expect(s.gy, -1000);
      expect(s.gz, 0);
    });

    test('parses from a non-zero offset (used inside batch parsing)', () {
      final sample = buildSample(seq: 42, tDeviceUs: 999, ax: 5);
      // Prepend a 1-byte count prefix to verify offset handling.
      final bytes = Uint8List.fromList([1, ...sample]);
      final s = ImuSample.parse(bytes, offset: 1);

      expect(s.seq, 42);
      expect(s.tDeviceUs, 999);
      expect(s.ax, 5);
    });

    test('throws ArgumentError when buffer is shorter than 20 bytes', () {
      expect(() => ImuSample.parse(Uint8List(19)), throwsArgumentError);
    });

    test('throws ArgumentError when offset + 20 exceeds buffer length', () {
      final sample = buildSample(seq: 1, tDeviceUs: 1);
      expect(() => ImuSample.parse(sample, offset: 1), throwsArgumentError);
    });

    test('handles uint32 seq wrap (2^32 - 1) without overflow', () {
      final bytes = buildSample(seq: 0xFFFFFFFF, tDeviceUs: 0);
      expect(ImuSample.parse(bytes).seq, 0xFFFFFFFF);
    });

    test('handles negative int16 raw values (two-complement)', () {
      final bytes = buildSample(
        seq: 0,
        tDeviceUs: 0,
        ax: -32768,
        ay: 32767,
        az: -1,
      );
      final s = ImuSample.parse(bytes);
      expect(s.ax, -32768);
      expect(s.ay, 32767);
      expect(s.az, -1);
    });
  });

  group('ImuSample.toReading', () {
    test('converts raw → g and dps using DeviceInfo scales (§2.3)', () {
      final info = sampleInfo(
        accelScale: 1 / 16384, // ±2g
        gyroScale: 1 / 16.4, // ±2000 dps
      );
      final s = ImuSample.parse(
        buildSample(seq: 7, tDeviceUs: 123456, ax: 16384, gx: 164),
      );
      final r = s.toReading(info);

      expect(r.seq, 7);
      expect(r.tDeviceUs, 123456);
      // 16384 * 1/16384 = 1.0 g
      expect(r.ax, closeTo(1.0, 1e-9));
      expect(r.ay, 0);
      expect(r.az, 0);
      // 164 * 1/16.4 = 10 dps
      expect(r.gx, closeTo(10.0, 1e-9));
      expect(r.gy, 0);
      expect(r.gz, 0);
    });

    test('preserves sign of raw values through scaling', () {
      final info = sampleInfo();
      final s = ImuSample.parse(
        buildSample(seq: 0, tDeviceUs: 0, ax: -16384, gx: -164),
      );
      final r = s.toReading(info);
      expect(r.ax, closeTo(-1.0, 1e-9));
      expect(r.gx, closeTo(-10.0, 1e-9));
    });

    test('works with different range scales (±4g, ±500dps)', () {
      final info = sampleInfo(
        accelScale: 1 / 8192, // ±4g → 8192 LSB/g
        gyroScale: 1 / 65.5, // ±500 dps → 65.5 LSB/dps (MPU6886 datasheet)
      );
      final s = ImuSample.parse(
        buildSample(seq: 0, tDeviceUs: 0, ax: 8192, gx: 655),
      );
      final r = s.toReading(info);
      // 8192 * 1/8192 = 1.0 g
      expect(r.ax, closeTo(1.0, 1e-9));
      // 655 * 1/65.5 = 10 dps
      expect(r.gx, closeTo(10.0, 1e-9));
    });
  });

  group('ImuPacketParser.parseBatch', () {
    test('parses a single-sample batch (count=1)', () {
      final batch = buildBatch([buildSample(seq: 0, tDeviceUs: 100, ax: 1)]);
      final samples = ImuPacketParser.parseBatch(batch);

      expect(samples, hasLength(1));
      expect(samples.first.seq, 0);
      expect(samples.first.tDeviceUs, 100);
      expect(samples.first.ax, 1);
    });

    test('parses a 3-sample batch with sequential seq', () {
      final batch = buildBatch([
        buildSample(seq: 10, tDeviceUs: 1000),
        buildSample(seq: 11, tDeviceUs: 1100),
        buildSample(seq: 12, tDeviceUs: 1200),
      ]);
      final samples = ImuPacketParser.parseBatch(batch);

      expect(samples.map((s) => s.seq), [10, 11, 12]);
      expect(samples.map((s) => s.tDeviceUs), [1000, 1100, 1200]);
    });

    test('parses max batch at MTU 247 (count=12, §2.2)', () {
      final samples = List.generate(
        12,
        (i) => buildSample(seq: i, tDeviceUs: i * 10),
      );
      final batch = buildBatch(samples);
      // 1 byte count + 12 * 20 = 241 bytes (≤ MTU-3 = 244)
      expect(batch.length, 1 + 12 * 20);

      final parsed = ImuPacketParser.parseBatch(batch);
      expect(parsed, hasLength(12));
      expect(parsed.last.seq, 11);
    });

    test('throws FormatException when count byte is 0 (empty batch)', () {
      expect(
        () => ImuPacketParser.parseBatch(Uint8List.fromList([0])),
        throwsFormatException,
      );
    });

    test(
      'throws ArgumentError when buffer has only count byte (no samples)',
      () {
        expect(
          () => ImuPacketParser.parseBatch(Uint8List.fromList([1])),
          throwsArgumentError,
        );
      },
    );

    test('throws ArgumentError when buffer is empty', () {
      expect(
        () => ImuPacketParser.parseBatch(Uint8List(0)),
        throwsArgumentError,
      );
    });

    test(
      'throws ArgumentError when count claims more samples than buffer holds '
      '(truncated batch)',
      () {
        // count=3 but only 1 sample present
        final truncated = Uint8List.fromList([
          3,
          ...buildSample(seq: 0, tDeviceUs: 0),
        ]);
        expect(
          () => ImuPacketParser.parseBatch(truncated),
          throwsArgumentError,
        );
      },
    );

    test(
      'throws ArgumentError when count claims fewer samples than buffer holds '
      '(trailing bytes)',
      () {
        // count=1 but 2 samples present — trailing bytes are not allowed.
        final trailing = Uint8List.fromList([
          1,
          ...buildSample(seq: 0, tDeviceUs: 0),
          ...buildSample(seq: 1, tDeviceUs: 1),
        ]);
        expect(() => ImuPacketParser.parseBatch(trailing), throwsArgumentError);
      },
    );
  });

  group('ImuSeqTracker', () {
    test('first sample seeds expected next seq (no gap)', () {
      final tracker = ImuSeqTracker();
      expect(tracker.gapCount(5), 0);
      expect(tracker.expectedNext, 6);
    });

    test('detects a gap of 3 between seq 5 and seq 9', () {
      final tracker = ImuSeqTracker()..gapCount(5); // expectedNext = 6
      expect(tracker.gapCount(9), 3); // 6,7,8 missing
      expect(tracker.expectedNext, 10);
    });

    test('returns 0 when seq equals expected (no gap)', () {
      final tracker = ImuSeqTracker()..gapCount(5);
      expect(tracker.gapCount(6), 0);
      expect(tracker.expectedNext, 7);
    });

    test('handles seq wrap (2^32 - 1 → 0)', () {
      final tracker = ImuSeqTracker()
        ..gapCount(0xFFFFFFFE); // expectedNext = 0xFFFFFFFF
      expect(tracker.gapCount(0xFFFFFFFF), 0);
      // wrap: expectedNext = 0
      expect(tracker.gapCount(0), 0);
      expect(tracker.expectedNext, 1);
    });

    test(
      'returns 0 for out-of-order but already-seen seq (no negative gap)',
      () {
        final tracker = ImuSeqTracker()..gapCount(10);
        // Late/duplicate sample with seq 9 — already past, not a forward gap.
        expect(tracker.gapCount(9), 0);
        expect(tracker.expectedNext, 11);
      },
    );

    test('cumulative gap count accumulates across multiple gaps', () {
      final tracker = ImuSeqTracker();
      tracker.gapCount(0); // seed
      tracker.gapCount(5); // gap 4
      tracker.gapCount(10); // gap 4
      expect(tracker.totalGaps, 8);
    });
  });

  group('ImuPacketParser.parseBatchWithGaps', () {
    test('returns samples and zero gaps when seq is contiguous', () {
      final batch = buildBatch([
        buildSample(seq: 0, tDeviceUs: 0),
        buildSample(seq: 1, tDeviceUs: 10),
        buildSample(seq: 2, tDeviceUs: 20),
      ]);
      final result = ImuPacketParser.parseBatchWithGaps(batch, ImuSeqTracker());

      expect(result.samples, hasLength(3));
      expect(result.newGaps, 0);
    });

    test('reports gaps when seq jumps inside a batch', () {
      final batch = buildBatch([
        buildSample(seq: 0, tDeviceUs: 0),
        buildSample(seq: 5, tDeviceUs: 50), // gap 4
        buildSample(seq: 6, tDeviceUs: 60),
      ]);
      final tracker = ImuSeqTracker();
      final result = ImuPacketParser.parseBatchWithGaps(batch, tracker);

      expect(result.samples, hasLength(3));
      expect(result.newGaps, 4);
      expect(tracker.totalGaps, 4);
    });

    test('tracker persists across batches (cumulative gaps)', () {
      final tracker = ImuSeqTracker();
      ImuPacketParser.parseBatchWithGaps(
        buildBatch([buildSample(seq: 0, tDeviceUs: 0)]),
        tracker,
      );
      final result = ImuPacketParser.parseBatchWithGaps(
        buildBatch([buildSample(seq: 10, tDeviceUs: 100)]), // gap 9
        tracker,
      );
      expect(result.newGaps, 9);
      expect(tracker.totalGaps, 9);
    });
  });
}
