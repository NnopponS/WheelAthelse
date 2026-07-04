import 'dart:math' as math;

import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';

/// Summary statistics for a recording session (or a chunk of it).
///
/// Computed by [SessionStatsCalculator.compute] from a list of [BufferedSample]
/// and the session's [SessionMeta]. This is pure logic — no Flutter, no I/O,
/// no async — so it can be unit-tested in isolation and reused by both the
/// preview page (full-session stats) and the browse list (quick summary).
///
/// Fields:
/// - [sampleCount]: number of samples in the input list.
/// - [durationMs]: session duration from [SessionMeta.durationMs].
/// - [dropCount]: dropped-sample count. Not currently stored in [SessionMeta],
///   so this is `0` until a drop-count field is added.
/// - [syncQualityMs]: the worse (max) of the left/right drift residual RMS in
///   milliseconds from [SessionMeta]. `null` when both wheels have no value.
/// - [meanAccelMagnitude] / [peakAccelMagnitude]: mean and peak of
///   `sqrt(ax² + ay² + az²)` across the samples.
/// - [meanGyroMagnitude] / [peakGyroMagnitude]: mean and peak of
///   `sqrt(gx² + gy² + gz²)` across the samples.
class SessionStats {
  const SessionStats({
    required this.sampleCount,
    required this.durationMs,
    required this.dropCount,
    required this.syncQualityMs,
    required this.meanAccelMagnitude,
    required this.peakAccelMagnitude,
    required this.meanGyroMagnitude,
    required this.peakGyroMagnitude,
  });

  /// Number of samples in the input list used to compute these stats.
  final int sampleCount;

  /// Session duration in milliseconds (from [SessionMeta.durationMs]).
  final int durationMs;

  /// Number of dropped samples. `0` until [SessionMeta] exposes a drop count.
  final int dropCount;

  /// Worse (max) of the left/right drift residual RMS in ms, or `null` when
  /// neither wheel has a value.
  final double? syncQualityMs;

  /// Mean of `sqrt(ax² + ay² + az²)` across samples (g). `0.0` when empty.
  final double meanAccelMagnitude;

  /// Peak (max) of `sqrt(ax² + ay² + az²)` across samples (g). `0.0` when empty.
  final double peakAccelMagnitude;

  /// Mean of `sqrt(gx² + gy² + gz²)` across samples (dps). `0.0` when empty.
  final double meanGyroMagnitude;

  /// Peak (max) of `sqrt(gx² + gy² + gz²)` across samples (dps). `0.0` when empty.
  final double peakGyroMagnitude;
}

/// Pure-logic calculator that derives [SessionStats] from a list of
/// [BufferedSample] and the session's [SessionMeta].
///
/// Usage:
/// ```dart
/// final stats = SessionStatsCalculator.compute(samples, meta);
/// ```
///
/// The calculator is stateless and side-effect free; all methods are static.
class SessionStatsCalculator {
  const SessionStatsCalculator._();

  /// Computes [SessionStats] from [samples] and [meta].
  ///
  /// For an empty sample list, all magnitude stats are `0.0` (never NaN) and
  /// [sampleCount] is `0`; [durationMs] and [syncQualityMs] still come from
  /// [meta]. [dropCount] is always `0` because [SessionMeta] does not yet
  /// carry a drop count.
  static SessionStats compute(List<BufferedSample> samples, SessionMeta meta) {
    if (samples.isEmpty) {
      return SessionStats(
        sampleCount: 0,
        durationMs: meta.durationMs,
        dropCount: 0,
        syncQualityMs: _maxDrift(meta),
        meanAccelMagnitude: 0.0,
        peakAccelMagnitude: 0.0,
        meanGyroMagnitude: 0.0,
        peakGyroMagnitude: 0.0,
      );
    }

    var sumAccel = 0.0;
    var peakAccel = 0.0;
    var sumGyro = 0.0;
    var peakGyro = 0.0;

    for (final s in samples) {
      final r = s.reading;
      final accelMag = math.sqrt(r.ax * r.ax + r.ay * r.ay + r.az * r.az);
      final gyroMag = math.sqrt(r.gx * r.gx + r.gy * r.gy + r.gz * r.gz);
      sumAccel += accelMag;
      if (accelMag > peakAccel) peakAccel = accelMag;
      sumGyro += gyroMag;
      if (gyroMag > peakGyro) peakGyro = gyroMag;
    }

    final count = samples.length;
    return SessionStats(
      sampleCount: count,
      durationMs: meta.durationMs,
      dropCount: 0,
      syncQualityMs: _maxDrift(meta),
      meanAccelMagnitude: sumAccel / count,
      peakAccelMagnitude: peakAccel,
      meanGyroMagnitude: sumGyro / count,
      peakGyroMagnitude: peakGyro,
    );
  }

  /// Returns the worse (max) of the left/right drift residual RMS in ms.
  ///
  /// - Both `null` → `null`.
  /// - One `null` → the other value.
  /// - Both set → `max(left, right)`.
  static double? _maxDrift(SessionMeta meta) {
    final left = meta.driftResidualRmsMsLeft;
    final right = meta.driftResidualRmsMsRight;
    if (left == null && right == null) return null;
    if (left == null) return right;
    if (right == null) return left;
    return math.max(left, right);
  }
}
