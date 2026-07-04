import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/session_stats.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Builds a [BufferedSample] with a given [ImuReading] and wheel side.
BufferedSample _sample(
  ImuReading reading, {
  WheelSide wheel = WheelSide.left,
  int timestampAppMs = 0,
  double timestampSyncedMs = 0,
}) {
  return BufferedSample(
    reading: reading,
    wheel: wheel,
    timestampAppMs: timestampAppMs,
    timestampSyncedMs: timestampSyncedMs,
  );
}

/// Minimal [SessionMeta] for tests, with overridable fields.
SessionMeta _meta({
  int durationMs = 10000,
  int sampleCount = 0,
  int markerCount = 0,
  double? driftLeft,
  double? driftRight,
}) {
  return SessionMeta(
    sessionId: 'deadbeef',
    topic: 'test',
    trialNumber: 1,
    sampleRateHz: 100,
    startTime: DateTime.utc(2024, 1, 1),
    durationMs: durationMs,
    sampleCount: sampleCount,
    markerCount: markerCount,
    driftResidualRmsMsLeft: driftLeft,
    driftResidualRmsMsRight: driftRight,
  );
}

void main() {
  group('SessionStats', () {
    test('fields are stored correctly', () {
      const stats = SessionStats(
        sampleCount: 42,
        durationMs: 10000,
        dropCount: 3,
        syncQualityMs: 1.5,
        meanAccelMagnitude: 1.0,
        peakAccelMagnitude: 2.0,
        meanGyroMagnitude: 10.0,
        peakGyroMagnitude: 20.0,
      );
      expect(stats.sampleCount, 42);
      expect(stats.durationMs, 10000);
      expect(stats.dropCount, 3);
      expect(stats.syncQualityMs, 1.5);
      expect(stats.meanAccelMagnitude, 1.0);
      expect(stats.peakAccelMagnitude, 2.0);
      expect(stats.meanGyroMagnitude, 10.0);
      expect(stats.peakGyroMagnitude, 20.0);
    });
  });

  group('SessionStatsCalculator.compute', () {
    test('empty samples -> zero stats, no NaN', () {
      final meta = _meta(durationMs: 5000);
      final stats = SessionStatsCalculator.compute(const [], meta);
      expect(stats.sampleCount, 0);
      expect(stats.durationMs, 5000);
      expect(stats.dropCount, 0);
      expect(stats.syncQualityMs, isNull);
      expect(stats.meanAccelMagnitude, 0.0);
      expect(stats.peakAccelMagnitude, 0.0);
      expect(stats.meanGyroMagnitude, 0.0);
      expect(stats.peakGyroMagnitude, 0.0);
      // Ensure no NaN.
      expect(stats.meanAccelMagnitude.isNaN, isFalse);
      expect(stats.peakAccelMagnitude.isNaN, isFalse);
      expect(stats.meanGyroMagnitude.isNaN, isFalse);
      expect(stats.peakGyroMagnitude.isNaN, isFalse);
    });

    test('single sample -> mean == peak == that sample magnitude', () {
      final reading = const ImuReading(
        seq: 0,
        tDeviceUs: 0,
        ax: 3.0,
        ay: 4.0,
        az: 0.0, // sqrt(9+16) = 5
        gx: 1.0,
        gy: 2.0,
        gz: 2.0, // sqrt(1+4+4) = 3
      );
      final samples = [_sample(reading)];
      final stats = SessionStatsCalculator.compute(samples, _meta());
      expect(stats.sampleCount, 1);
      expect(stats.meanAccelMagnitude, closeTo(5.0, 1e-9));
      expect(stats.peakAccelMagnitude, closeTo(5.0, 1e-9));
      expect(stats.meanGyroMagnitude, closeTo(3.0, 1e-9));
      expect(stats.peakGyroMagnitude, closeTo(3.0, 1e-9));
    });

    test('basic stats with known samples (mean + peak)', () {
      // Accel magnitudes: 5, 10, 13 -> mean = 28/3, peak = 13
      // Gyro magnitudes: 3, 6, 9  -> mean = 6, peak = 9
      final samples = [
        _sample(const ImuReading(
            seq: 0, tDeviceUs: 0, ax: 3, ay: 4, az: 0, gx: 1, gy: 2, gz: 2)),
        _sample(const ImuReading(
            seq: 1, tDeviceUs: 0, ax: 6, ay: 8, az: 0, gx: 2, gy: 4, gz: 4)),
        _sample(const ImuReading(
            seq: 2, tDeviceUs: 0, ax: 12, ay: 5, az: 0, gx: 3, gy: 6, gz: 6)),
      ];
      final stats = SessionStatsCalculator.compute(samples, _meta());
      expect(stats.sampleCount, 3);
      expect(stats.meanAccelMagnitude, closeTo(28 / 3, 1e-9));
      expect(stats.peakAccelMagnitude, closeTo(13.0, 1e-9));
      expect(stats.meanGyroMagnitude, closeTo(6.0, 1e-9));
      expect(stats.peakGyroMagnitude, closeTo(9.0, 1e-9));
    });

    test('both wheels mixed (left + right samples)', () {
      final samples = [
        _sample(
          const ImuReading(
              seq: 0, tDeviceUs: 0, ax: 3, ay: 4, az: 0, gx: 0, gy: 0, gz: 0),
          wheel: WheelSide.left,
        ),
        _sample(
          const ImuReading(
              seq: 1, tDeviceUs: 0, ax: 0, ay: 0, az: 5, gx: 0, gy: 0, gz: 0),
          wheel: WheelSide.right,
        ),
      ];
      // Accel magnitudes: 5, 5 -> mean 5, peak 5
      final stats = SessionStatsCalculator.compute(samples, _meta());
      expect(stats.sampleCount, 2);
      expect(stats.meanAccelMagnitude, closeTo(5.0, 1e-9));
      expect(stats.peakAccelMagnitude, closeTo(5.0, 1e-9));
      expect(stats.meanGyroMagnitude, 0.0);
      expect(stats.peakGyroMagnitude, 0.0);
    });

    test('large sample list computes correctly', () {
      // 1000 samples: accel magnitude = 1.0 each, gyro magnitude = 2.0 each.
      final samples = List.generate(
        1000,
        (i) => _sample(
          ImuReading(
            seq: i,
            tDeviceUs: 0,
            ax: 1,
            ay: 0,
            az: 0, // magnitude 1
            gx: 0,
            gy: 2,
            gz: 0, // magnitude 2
          ),
        ),
      );
      final stats = SessionStatsCalculator.compute(samples, _meta());
      expect(stats.sampleCount, 1000);
      expect(stats.meanAccelMagnitude, closeTo(1.0, 1e-9));
      expect(stats.peakAccelMagnitude, closeTo(1.0, 1e-9));
      expect(stats.meanGyroMagnitude, closeTo(2.0, 1e-9));
      expect(stats.peakGyroMagnitude, closeTo(2.0, 1e-9));
    });

    test('duration from meta', () {
      final samples = [
        _sample(const ImuReading(
            seq: 0, tDeviceUs: 0, ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0)),
      ];
      final stats =
          SessionStatsCalculator.compute(samples, _meta(durationMs: 4242));
      expect(stats.durationMs, 4242);
    });

    test('dropCount is 0 (not computable from meta alone)', () {
      final samples = [
        _sample(const ImuReading(
            seq: 0, tDeviceUs: 0, ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0)),
      ];
      final stats = SessionStatsCalculator.compute(samples, _meta());
      expect(stats.dropCount, 0);
    });
  });

  group('SessionStatsCalculator syncQualityMs', () {
    test('null when both drift fields null', () {
      final stats =
          SessionStatsCalculator.compute(const [], _meta());
      expect(stats.syncQualityMs, isNull);
    });

    test('returns left when right is null', () {
      final stats = SessionStatsCalculator.compute(
        const [],
        _meta(driftLeft: 1.5),
      );
      expect(stats.syncQualityMs, 1.5);
    });

    test('returns right when left is null', () {
      final stats = SessionStatsCalculator.compute(
        const [],
        _meta(driftRight: 2.5),
      );
      expect(stats.syncQualityMs, 2.5);
    });

    test('returns max of left and right when both set', () {
      final stats = SessionStatsCalculator.compute(
        const [],
        _meta(driftLeft: 1.5, driftRight: 3.2),
      );
      expect(stats.syncQualityMs, 3.2);

      final stats2 = SessionStatsCalculator.compute(
        const [],
        _meta(driftLeft: 5.0, driftRight: 2.0),
      );
      expect(stats2.syncQualityMs, 5.0);
    });

    test('sync quality computed even when samples empty', () {
      final stats = SessionStatsCalculator.compute(
        const [],
        _meta(driftLeft: 1.0, driftRight: 4.0),
      );
      expect(stats.syncQualityMs, 4.0);
    });
  });
}
