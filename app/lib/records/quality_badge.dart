import 'dart:ui';

import 'package:wheelathlete/records/session_model.dart';

/// Sync quality level for a recorded session, derived from the drift
/// residual RMS (milliseconds) of the time-sync engine.
///
/// Used by the Browse session list badge (§7) and the preview summary.
enum SyncQuality { good, fair, poor, unknown }

/// Pure logic for mapping drift residual RMS values to a [SyncQuality]
/// level and an associated badge color.
///
/// Thresholds (decision D25):
///   good    = drift RMS < 2 ms   (green)
///   fair    = drift RMS 2-5 ms   (amber)
///   poor    = drift RMS > 5 ms   (red)
///   unknown = null               (grey) — legacy sessions without sync data
class QualityBadge {
  const QualityBadge._();

  /// Returns the quality level for a single drift residual RMS value (ms).
  ///
  /// A negative value is treated as "better than good" and maps to [good].
  static SyncQuality fromDriftRms(double? driftRmsMs) {
    if (driftRmsMs == null) return SyncQuality.unknown;
    if (driftRmsMs < 0) return SyncQuality.good;
    if (driftRmsMs < 2) return SyncQuality.good;
    if (driftRmsMs <= 5) return SyncQuality.fair;
    return SyncQuality.poor;
  }

  /// Returns the quality level for a session by taking the max of the left
  /// and right wheel drift residual RMS. If both are null, returns
  /// [SyncQuality.unknown].
  static SyncQuality fromMeta(SessionMeta meta) {
    final left = meta.driftResidualRmsMsLeft;
    final right = meta.driftResidualRmsMsRight;
    if (left == null && right == null) return SyncQuality.unknown;
    final max = [left, right]
        .whereType<double>()
        .fold<double?>(null, (a, b) => a == null ? b : (a > b ? a : b));
    return fromDriftRms(max);
  }

  /// Returns the badge color for a [SyncQuality] level.
  static Color color(SyncQuality quality) {
    return switch (quality) {
      SyncQuality.good => const Color(0xFF4CAF50), // green
      SyncQuality.fair => const Color(0xFFFFC107), // amber
      SyncQuality.poor => const Color(0xFFF44336), // red
      SyncQuality.unknown => const Color(0xFF9E9E9E), // grey
    };
  }
}
