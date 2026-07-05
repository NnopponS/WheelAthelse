/// Pure clock-sync math for the WheelAthlete app — no Flutter, no BLE I/O.
///
/// All functions here are host-testable. The Riverpod notifier
/// (`sync_providers.dart`) wraps these with live BLE streams.
///
/// References:
/// - `.project/architecture.md` §4 (Time Sync)
/// - `docs/ble-protocol.md` §4.2 (offset), §4.3 (drift), §3.2 (scheduled start)
library;

/// One `(t_device_us, t_app_us)` pair collected from a SYNC_PING round trip.
///
/// Used as input to [DriftFit.fit] to build the linear mapping from device
/// micros to phone microseconds (the common timeline). Both timestamps use
/// microsecond precision for sub-ms sync accuracy.
class SyncPoint {
  const SyncPoint({required this.tDeviceUs, required this.tAppUs});
  final int tDeviceUs;
  final int tAppUs;
}

/// Result of a single offset-estimation round trip (§4.2).
class OffsetEstimate {
  const OffsetEstimate({required this.rttMs, required this.offsetUs});

  /// Round-trip time in milliseconds (T3 − T1), with sub-ms precision.
  final double rttMs;

  /// Clock offset in microseconds: `offset = T2 − (T1 + RTT/2)`.
  ///
  /// Positive = device clock is ahead of phone clock. Add this to a phone
  /// timestamp to get the corresponding device timestamp, or subtract to go
  /// the other way.
  final int offsetUs;

  /// Computes offset from a SYNC_PING round trip (§4.2).
  ///
  /// Uses **microsecond-precision** T1/T3 for sub-ms offset accuracy.
  /// The protocol sends T1 to the device in milliseconds (uint32), but the
  /// phone records both T1 and T3 in microseconds locally so the RTT and
  /// offset calculations are not quantized to 1ms.
  ///
  /// - [t1AppUs]: phone time (µs since epoch) when SYNC_PING was sent (T1).
  /// - [t2DeviceUs]: device `micros()` when it received/responded (T2).
  /// - [t3AppUs]: phone time (µs since epoch) when the Sync response was
  ///   received (T3).
  ///
  /// `RTT = (T3 − T1) / 1000` (ms, float), `offset = T2 − (T1 + RTT_us/2)` (µs).
  factory OffsetEstimate.compute({
    required int t1AppUs,
    required int t2DeviceUs,
    required int t3AppUs,
  }) {
    final rttUs = t3AppUs - t1AppUs;
    final rttMs = rttUs / 1000.0;
    final offsetUs = t2DeviceUs - (t1AppUs + rttUs ~/ 2);
    return OffsetEstimate(rttMs: rttMs, offsetUs: offsetUs);
  }
}

/// Tracks the best (lowest-RTT) offset estimate across multiple pings.
///
/// The protocol (§4.2) says: "เก็บค่าที่ RTT ต่ำสุด (เช่น 10 ครั้ง เอา
/// min-RTT) เพื่อลด noise". Lower RTT means the midpoint assumption
/// (symmetric latency) is more accurate, so the offset estimate is less
/// noisy.
class MinRttTracker {
  OffsetEstimate? _best;
  int _count = 0;

  /// Number of pings recorded so far.
  int get count => _count;

  /// The estimate with the lowest RTT, or null if no pings yet.
  OffsetEstimate? get best => _best;

  /// Records [estimate] and keeps it if it has the lowest RTT so far.
  void add(OffsetEstimate estimate) {
    _count++;
    if (_best == null || estimate.rttMs < _best!.rttMs) {
      _best = estimate;
    }
  }

  /// Resets the tracker (e.g. when starting a new sync session).
  void clear() {
    _best = null;
    _count = 0;
  }
}

/// Linear fit `t_app_us = slope * t_device_us + interceptUs` from collected
/// [SyncPoint]s (§4.3). Used to map every IMU sample's `t_device_us` onto the
/// common phone timeline. Both axes are in microseconds for sub-ms accuracy.
class DriftFit {
  const DriftFit({
    required this.slope,
    required this.interceptUs,
    required this.residualRmsMs,
    required this.n,
  });

  /// Slope of the linear fit (should be ≈ 1.0 since both axes are in µs).
  /// Deviation from 1.0 indicates clock drift.
  final double slope;

  /// Intercept in microseconds.
  final double interceptUs;

  /// RMS of fit residuals in milliseconds — measures sync quality. Stored
  /// in `session_*_meta.json` as `residual_ms_rms`.
  final double residualRmsMs;

  /// Number of points used in the fit.
  final int n;

  /// Fits a line through [points] using ordinary least squares.
  ///
  /// Throws [ArgumentError] if fewer than 2 points are provided (a line
  /// cannot be defined from a single point).
  factory DriftFit.fit(List<SyncPoint> points) {
    if (points.length < 2) {
      throw ArgumentError(
        'DriftFit needs ≥2 points, got ${points.length}',
        'points',
      );
    }
    final n = points.length;
    // Linear regression: y = a*x + b
    // a = (n*Σxy − Σx*Σy) / (n*Σx² − (Σx)²)
    // b = (Σy − a*Σx) / n
    var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
    for (final p in points) {
      final x = p.tDeviceUs.toDouble();
      final y = p.tAppUs.toDouble();
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }
    final denom = n * sumX2 - sumX * sumX;
    final slope = denom != 0 ? (n * sumXY - sumX * sumY) / denom : 0.0;
    final intercept = (sumY - slope * sumX) / n;

    // Residual RMS (reported in ms for human-readable sync quality)
    var ssRes = 0.0;
    for (final p in points) {
      final predicted = slope * p.tDeviceUs + intercept;
      final resid = p.tAppUs - predicted;
      ssRes += resid * resid;
    }
    final residualRmsUs = (ssRes / n).abs() > 0 ? (ssRes / n).sqrt() : 0.0;
    final residualRmsMs = residualRmsUs / 1000.0;

    return DriftFit(
      slope: slope,
      interceptUs: intercept,
      residualRmsMs: residualRmsMs,
      n: n,
    );
  }

  /// Converts a device timestamp (µs) to the common phone timeline (µs).
  double toSyncedUs(int tDeviceUs) => slope * tDeviceUs + interceptUs;

  /// Converts a device timestamp (µs) to the common phone timeline (ms).
  double toSyncedMs(int tDeviceUs) => toSyncedUs(tDeviceUs) / 1000.0;
}

/// Scheduled synchronized start math (§3.2).
///
/// Given a target start time on the phone clock and the current offset
/// estimate, computes the `target_start_us` to send to the firmware so both
/// wheels start at the same instant on the phone timeline.
class ScheduledStart {
  const ScheduledStart._(); // coverage:ignore-line

  /// Converts [tStartPhoneMs] to device-local micros.
  ///
  /// Formula (§3.2):
  /// ```
  /// target_start_us = (T_start_phone - t_app_ref_ms) * 1000
  ///                   + offset_us + t_device_ref_us
  /// ```
  static int compute({
    required int tStartPhoneMs,
    required int tAppRefMs,
    required int offsetUs,
    required int tDeviceRefUs,
  }) {
    return (tStartPhoneMs - tAppRefMs) * 1000 + offsetUs + tDeviceRefUs;
  }
}

/// Computes the UTC start instant (epoch ms) for a scheduled start, used to
/// stamp session meta for camera alignment (Phase 2 §4 / subtask #16).
///
/// The phone clock's "now" (`nowPhoneMs`) and the UTC epoch "now"
/// (`utcEpochNowMs`) are both captured at the same instant. The scheduled
/// start is at `tStartPhoneMs` on the phone clock. The corresponding UTC
/// instant is:
///
/// ```
/// utc_start_ms = utc_epoch_now + (T_start - now_phone)
/// ```
///
/// This is independent of the firmware — the app computes it from its own
/// UTC clock so the session meta carries a real-world instant even if the
/// board's RTC is not set.
int computeUtcStartMs({
  required int utcEpochNowMs,
  required int nowPhoneMs,
  required int tStartPhoneMs,
}) {
  return utcEpochNowMs + (tStartPhoneMs - nowPhoneMs);
}

/// Extension to expose `sqrt()` on `num` without importing `dart:math`.
extension _Sqrt on num {
  double sqrt() => _sqrt(this);
}

// Newton's method — avoids dart:math dependency for a single function.
double _sqrt(num x) {
  if (x < 0) return double.nan;
  if (x == 0) return 0.0;
  var z = x.toDouble() / 2;
  for (var i = 0; i < 20; i++) {
    z = (z + x.toDouble() / z) / 2;
  }
  return z;
}
