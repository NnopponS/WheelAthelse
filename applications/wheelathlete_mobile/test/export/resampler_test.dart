import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/export/resampler.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

BufferedSample _s({
  required int seq,
  required double syncedMs,
  required WheelSide wheel,
  double ax = 0,
  double ay = 0,
  double az = 0,
  double gx = 0,
  double gy = 0,
  double gz = 0,
  int tDeviceUs = 0,
  int tAppMs = 0,
}) => BufferedSample(
  reading: ImuReading(
    seq: seq,
    tDeviceUs: tDeviceUs,
    ax: ax,
    ay: ay,
    az: az,
    gx: gx,
    gy: gy,
    gz: gz,
  ),
  wheel: wheel,
  timestampAppMs: tAppMs,
  timestampSyncedMs: syncedMs,
);

void main() {
  group('Resampler', () {
    test('empty input produces empty output', () {
      final result = Resampler.resample([], gridIntervalMs: 10);
      expect(result, isEmpty);
    });

    test('single wheel, perfect grid alignment → no interpolation needed', () {
      final samples = [
        _s(seq: 0, syncedMs: 0, wheel: WheelSide.left, ax: 1),
        _s(seq: 1, syncedMs: 10, wheel: WheelSide.left, ax: 2),
        _s(seq: 2, syncedMs: 20, wheel: WheelSide.left, ax: 3),
      ];
      final result = Resampler.resample(samples, gridIntervalMs: 10);
      expect(result.length, 3);
      expect(result[0].timestampSyncedMs, 0);
      expect(result[0].reading.ax, 1);
      expect(result[1].timestampSyncedMs, 10);
      expect(result[1].reading.ax, 2);
      expect(result[2].timestampSyncedMs, 20);
      expect(result[2].reading.ax, 3);
    });

    test('linear interpolation between two points', () {
      final samples = [
        _s(seq: 0, syncedMs: 0, wheel: WheelSide.left, ax: 0),
        _s(seq: 1, syncedMs: 20, wheel: WheelSide.left, ax: 10),
      ];
      final result = Resampler.resample(samples, gridIntervalMs: 10);
      // Grid: 0, 10, 20
      expect(result.length, 3);
      expect(result[0].reading.ax, 0); // exact
      expect(result[1].reading.ax, closeTo(5, 0.001)); // interpolated
      expect(result[2].reading.ax, 10); // exact
    });

    test('both wheels resampled to same grid', () {
      final samples = [
        _s(seq: 0, syncedMs: 0, wheel: WheelSide.left, ax: 1),
        _s(seq: 1, syncedMs: 10, wheel: WheelSide.left, ax: 2),
        _s(seq: 0, syncedMs: 0, wheel: WheelSide.right, ax: 10),
        _s(seq: 1, syncedMs: 10, wheel: WheelSide.right, ax: 20),
      ];
      final result = Resampler.resample(samples, gridIntervalMs: 10);
      // Grid: 0, 10
      // At 0: L=1 (exact), R=10 (exact)
      // At 10: L=2 (exact), R=20 (exact)
      expect(result.length, 4); // 2 grid points × 2 wheels
      final leftAt0 = result
          .where((s) => s.wheel == WheelSide.left && s.timestampSyncedMs == 0)
          .first;
      final rightAt0 = result
          .where((s) => s.wheel == WheelSide.right && s.timestampSyncedMs == 0)
          .first;
      expect(leftAt0.reading.ax, 1);
      expect(rightAt0.reading.ax, 10);
    });

    test('grid starts at first sample timestamp', () {
      final samples = [
        _s(seq: 0, syncedMs: 100, wheel: WheelSide.left, ax: 1),
        _s(seq: 1, syncedMs: 110, wheel: WheelSide.left, ax: 2),
      ];
      final result = Resampler.resample(samples, gridIntervalMs: 10);
      expect(result.first.timestampSyncedMs, 100);
      expect(result.last.timestampSyncedMs, 110);
    });

    test(
      'extrapolation not done — points before first/after last are skipped',
      () {
        final samples = [
          _s(seq: 0, syncedMs: 5, wheel: WheelSide.left, ax: 1),
          _s(seq: 1, syncedMs: 15, wheel: WheelSide.left, ax: 2),
        ];
        // Grid: 0, 10, 20 — but only 10 is within [5, 15]
        final result = Resampler.resample(samples, gridIntervalMs: 10);
        expect(result.length, 1);
        expect(result[0].timestampSyncedMs, 10);
        expect(result[0].reading.ax, closeTo(1.5, 0.001));
      },
    );

    test('interpolates all 6 axes', () {
      final samples = [
        _s(
          seq: 0,
          syncedMs: 0,
          wheel: WheelSide.left,
          ax: 1,
          ay: 2,
          az: 3,
          gx: 4,
          gy: 5,
          gz: 6,
        ),
        _s(
          seq: 1,
          syncedMs: 20,
          wheel: WheelSide.left,
          ax: 11,
          ay: 12,
          az: 13,
          gx: 14,
          gy: 15,
          gz: 16,
        ),
      ];
      final result = Resampler.resample(samples, gridIntervalMs: 10);
      final mid = result[1]; // at synced=10
      expect(mid.reading.ax, closeTo(6, 0.001));
      expect(mid.reading.ay, closeTo(7, 0.001));
      expect(mid.reading.az, closeTo(8, 0.001));
      expect(mid.reading.gx, closeTo(9, 0.001));
      expect(mid.reading.gy, closeTo(10, 0.001));
      expect(mid.reading.gz, closeTo(11, 0.001));
    });

    test(
      'marker flag preserved: any sample with marker in range sets marker',
      () {
        final samples = [
          _s(seq: 0, syncedMs: 0, wheel: WheelSide.left, ax: 1),
          _s(seq: 1, syncedMs: 10, wheel: WheelSide.left, ax: 2),
          _s(seq: 2, syncedMs: 20, wheel: WheelSide.left, ax: 3),
        ];
        // Mark the middle sample
        final marked = [
          ...samples.sublist(0, 1),
          BufferedSample(
            reading: samples[1].reading,
            wheel: WheelSide.left,
            timestampAppMs: 0,
            timestampSyncedMs: 10,
            marker: true,
          ),
          ...samples.sublist(2),
        ];
        final result = Resampler.resample(marked, gridIntervalMs: 10);
        // The grid point at 10 should have marker=true
        final at10 = result.where((s) => s.timestampSyncedMs == 10).first;
        expect(at10.marker, isTrue);
      },
    );

    test('resampled seq is synthetic (grid index)', () {
      final samples = [
        _s(seq: 100, syncedMs: 0, wheel: WheelSide.left, ax: 1),
        _s(seq: 200, syncedMs: 10, wheel: WheelSide.left, ax: 2),
      ];
      final result = Resampler.resample(samples, gridIntervalMs: 10);
      // Seq should be 0, 1 (grid indices, not original seqs)
      expect(result[0].reading.seq, 0);
      expect(result[1].reading.seq, 1);
    });

    test('handles non-uniform sample intervals', () {
      final samples = [
        _s(seq: 0, syncedMs: 0, wheel: WheelSide.left, ax: 0),
        _s(seq: 1, syncedMs: 7, wheel: WheelSide.left, ax: 7),
        _s(seq: 2, syncedMs: 18, wheel: WheelSide.left, ax: 18),
      ];
      final result = Resampler.resample(samples, gridIntervalMs: 10);
      // Grid: 0, 10
      // At 0: exact (ax=0)
      // At 10: interpolate between (7, ax=7) and (18, ax=18) → 7 + (10-7)/(18-7)*11 = 7+3 = 10
      expect(result.length, 2);
      expect(result[0].reading.ax, 0);
      expect(result[1].reading.ax, closeTo(10, 0.01));
    });
  });
}
