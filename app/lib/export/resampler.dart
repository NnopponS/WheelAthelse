import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Resamples IMU samples from both wheels onto a common time grid using
/// linear interpolation (architecture.md §4.6).
///
/// Given samples from both wheels at their own (non-aligned) timestamps,
/// this produces a set of [BufferedSample]s at fixed intervals (e.g. every
/// 10ms) where each grid point has interpolated L and R values. This is
/// useful for training models that need L/R pairs at the same timestep.
///
/// - No extrapolation: grid points outside the sample range for a wheel are
///   skipped for that wheel.
/// - Linear interpolation is applied independently to each axis (ax, ay, az,
///   gx, gy, gz).
/// - The `marker` flag is set on a grid point if any sample in the
///   interpolation window has `marker=true`.
/// - The `seq` field of resampled samples is a synthetic grid index (0, 1, 2,
///   ...) rather than the original device sequence number.
class Resampler {
  const Resampler._();

  /// Resamples [samples] onto a grid with [gridIntervalMs] spacing.
  ///
  /// The grid starts at the first sample's `timestampSyncedMs` (rounded down
  /// to the nearest grid point) and ends at the last sample's timestamp.
  static List<BufferedSample> resample(
    List<BufferedSample> samples, {
    required double gridIntervalMs,
  }) {
    if (samples.isEmpty) return [];

    // Split by wheel side.
    final bySide = <WheelSide, List<BufferedSample>>{};
    for (final s in samples) {
      bySide.putIfAbsent(s.wheel, () => []).add(s);
    }
    for (final list in bySide.values) {
      list.sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));
    }

    // Compute grid range from the overall min/max synced timestamps.
    final allSorted = samples.toList()
      ..sort((a, b) => a.timestampSyncedMs.compareTo(b.timestampSyncedMs));
    final minTs = allSorted.first.timestampSyncedMs;
    final maxTs = allSorted.last.timestampSyncedMs;

    // Align grid start to the nearest grid point at or before minTs.
    final gridStart = (minTs / gridIntervalMs).floor() * gridIntervalMs;

    final result = <BufferedSample>[];
    var gridIdx = 0;
    for (var t = gridStart; t <= maxTs; t += gridIntervalMs, gridIdx++) {
      for (final side in bySide.keys) {
        final sideSamples = bySide[side]!;
        final interp = _interpolateAt(sideSamples, t);
        if (interp == null) continue; // outside range for this side
        result.add(BufferedSample(
          reading: ImuReading(
            seq: gridIdx,
            tDeviceUs: interp.tDeviceUs,
            ax: interp.ax,
            ay: interp.ay,
            az: interp.az,
            gx: interp.gx,
            gy: interp.gy,
            gz: interp.gz,
          ),
          wheel: side,
          timestampAppMs: interp.timestampAppMs,
          timestampSyncedMs: t,
          marker: interp.marker,
        ));
      }
    }
    return result;
  }

  /// Linearly interpolates the sample values at timestamp [tMs] within the
  /// sorted [samples] list. Returns null if [tMs] is outside the range.
  static _InterpResult? _interpolateAt(
    List<BufferedSample> samples,
    double tMs,
  ) {
    if (samples.isEmpty) return null;
    if (tMs < samples.first.timestampSyncedMs) return null;
    if (tMs > samples.last.timestampSyncedMs) return null;

    // Find the bracketing pair.
    int lo = 0;
    int hi = samples.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) ~/ 2;
      if (samples[mid].timestampSyncedMs <= tMs) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    final a = samples[lo];
    final b = samples[hi];
    final ta = a.timestampSyncedMs;
    final tb = b.timestampSyncedMs;

    if (ta == tb) {
      // Exact match (both points at same timestamp).
      return _InterpResult(
        ax: a.reading.ax,
        ay: a.reading.ay,
        az: a.reading.az,
        gx: a.reading.gx,
        gy: a.reading.gy,
        gz: a.reading.gz,
        tDeviceUs: a.reading.tDeviceUs,
        timestampAppMs: a.timestampAppMs,
        marker: a.marker || b.marker,
      );
    }

    final frac = (tMs - ta) / (tb - ta);
    double lerp(double va, double vb) => va + frac * (vb - va);

    return _InterpResult(
      ax: lerp(a.reading.ax, b.reading.ax),
      ay: lerp(a.reading.ay, b.reading.ay),
      az: lerp(a.reading.az, b.reading.az),
      gx: lerp(a.reading.gx, b.reading.gx),
      gy: lerp(a.reading.gy, b.reading.gy),
      gz: lerp(a.reading.gz, b.reading.gz),
      tDeviceUs: lerpInt(a.reading.tDeviceUs, b.reading.tDeviceUs, frac),
      timestampAppMs: lerpInt(a.timestampAppMs, b.timestampAppMs, frac),
      marker: a.marker || b.marker,
    );
  }

  static int lerpInt(int a, int b, double frac) =>
      (a + frac * (b - a)).round();
}

class _InterpResult {
  final double ax, ay, az, gx, gy, gz;
  final int tDeviceUs;
  final int timestampAppMs;
  final bool marker;

  _InterpResult({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.tDeviceUs,
    required this.timestampAppMs,
    required this.marker,
  });
}
