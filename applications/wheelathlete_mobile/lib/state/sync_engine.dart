/// Pure clock synchronization math shared by Live and Record.
///
/// This mirrors the Windows acquisition service's NTP-lite model:
/// - unwrap the device uint32 micros counter,
/// - timestamp each SYNC response at the phone round-trip midpoint,
/// - fit only the lowest-RTT half of observations,
/// - use one fitted model for both device->phone and phone->device mapping.
library;

import 'dart:math' as math;

const int _uint32Mask = 0xFFFFFFFF;
const int _uint32Half = 0x80000000;

/// Maps the firmware's wrapping uint32 `micros()` value onto an integer line.
/// Late events preserve their relative position without moving the cursor back.
class Uint32Unwrapper {
  int? _lastRaw;
  int? _lastUnwrapped;

  int unwrap(int rawValue) {
    final raw = rawValue & _uint32Mask;
    final lastRaw = _lastRaw;
    final lastUnwrapped = _lastUnwrapped;
    if (lastRaw == null || lastUnwrapped == null) {
      _lastRaw = raw;
      _lastUnwrapped = raw;
      return raw;
    }

    final forward = (raw - lastRaw) & _uint32Mask;
    if (forward < _uint32Half) {
      final value = lastUnwrapped + forward;
      _lastRaw = raw;
      _lastUnwrapped = value;
      return value;
    }

    final backward = (lastRaw - raw) & _uint32Mask;
    return lastUnwrapped - backward;
  }

  void reset() {
    _lastRaw = null;
    _lastUnwrapped = null;
  }
}

/// One `(device_us, phone_midpoint_us)` clock observation.
class SyncPoint {
  const SyncPoint({
    required this.tDeviceUs,
    required this.tAppUs,
    this.rttUs = 0,
  });

  final int tDeviceUs;
  final int tAppUs;
  final int rttUs;
}

/// Result of a single offset-estimation round trip.
class OffsetEstimate {
  const OffsetEstimate({required this.rttMs, required this.offsetUs});

  final double rttMs;
  final int offsetUs;

  factory OffsetEstimate.compute({
    required int t1AppUs,
    required int t2DeviceUs,
    required int t3AppUs,
  }) {
    final rttUs = math.max(0, t3AppUs - t1AppUs);
    final midpointUs = t1AppUs + rttUs ~/ 2;
    return OffsetEstimate(
      rttMs: rttUs / 1000.0,
      offsetUs: t2DeviceUs - midpointUs,
    );
  }
}

/// Canonical observation generated from one complete SYNC round trip.
class SyncObservation {
  const SyncObservation({
    required this.point,
    required this.offset,
    required this.rttUs,
  });

  final SyncPoint point;
  final OffsetEstimate offset;
  final int rttUs;

  factory SyncObservation.fromRoundTrip({
    required int t1AppUs,
    required int t2DeviceUs,
    required int t3AppUs,
  }) {
    final rttUs = math.max(0, t3AppUs - t1AppUs);
    final midpointUs = t1AppUs + rttUs ~/ 2;
    return SyncObservation(
      point: SyncPoint(tDeviceUs: t2DeviceUs, tAppUs: midpointUs, rttUs: rttUs),
      offset: OffsetEstimate.compute(
        t1AppUs: t1AppUs,
        t2DeviceUs: t2DeviceUs,
        t3AppUs: t3AppUs,
      ),
      rttUs: rttUs,
    );
  }
}

/// Tracks the minimum-RTT offset for compatibility with existing UI/QC fields.
class MinRttTracker {
  OffsetEstimate? _best;
  int _count = 0;

  int get count => _count;
  OffsetEstimate? get best => _best;

  void add(OffsetEstimate estimate) {
    _count++;
    if (_best == null || estimate.rttMs < _best!.rttMs) {
      _best = estimate;
    }
  }

  void clear() {
    _best = null;
    _count = 0;
  }
}

/// Linear clock model `phone_us = slope * device_us + interceptUs`.
class DriftFit {
  const DriftFit({
    required this.slope,
    required this.interceptUs,
    required this.residualRmsMs,
    required this.n,
    this.fitPointCount = 0,
    this.bestRttUs = 0,
    this.medianRttUs = 0,
  });

  final double slope;
  final double interceptUs;
  final double residualRmsMs;

  /// Total observations retained for this model.
  final int n;

  /// Number of low-RTT observations actually used for regression.
  final int fitPointCount;
  final int bestRttUs;
  final int medianRttUs;

  double get driftPpm => (slope - 1.0) * 1000000.0;

  factory DriftFit.fit(List<SyncPoint> points) {
    if (points.length < 2) {
      throw ArgumentError(
        'DriftFit needs >=2 points, got ${points.length}',
        'points',
      );
    }

    final rtts = points.map((point) => point.rttUs).toList()..sort();
    final hasMeasuredRtt = rtts.any((value) => value > 0);
    final ordered = List<SyncPoint>.of(points);
    if (hasMeasuredRtt) {
      ordered.sort((a, b) => a.rttUs.compareTo(b.rttUs));
    }
    final keepCount = hasMeasuredRtt
        ? math.max(2, (ordered.length + 1) ~/ 2)
        : ordered.length;
    final kept = ordered.take(keepCount).toList(growable: false);

    final nFit = kept.length;
    var sumX = 0.0;
    var sumY = 0.0;
    for (final point in kept) {
      sumX += point.tDeviceUs.toDouble();
      sumY += point.tAppUs.toDouble();
    }
    final xMean = sumX / nFit;
    final yMean = sumY / nFit;
    var variance = 0.0;
    var covariance = 0.0;
    for (final point in kept) {
      final dx = point.tDeviceUs - xMean;
      final dy = point.tAppUs - yMean;
      variance += dx * dx;
      covariance += dx * dy;
    }

    final slope = variance <= 0 ? 1.0 : covariance / variance;
    final intercept = yMean - slope * xMean;
    var squaredResiduals = 0.0;
    for (final point in kept) {
      final predicted = slope * point.tDeviceUs + intercept;
      final residual = point.tAppUs - predicted;
      squaredResiduals += residual * residual;
    }
    final residualRmsUs = math.sqrt(squaredResiduals / nFit);

    final medianRttUs = rtts.isEmpty
        ? 0
        : rtts.length.isOdd
        ? rtts[rtts.length ~/ 2]
        : ((rtts[rtts.length ~/ 2 - 1] + rtts[rtts.length ~/ 2]) / 2).round();

    return DriftFit(
      slope: slope,
      interceptUs: intercept,
      residualRmsMs: residualRmsUs / 1000.0,
      n: points.length,
      fitPointCount: nFit,
      bestRttUs: rtts.isEmpty ? 0 : rtts.first,
      medianRttUs: medianRttUs,
    );
  }

  double toSyncedUs(int tDeviceUs) => slope * tDeviceUs + interceptUs;
  double toSyncedMs(int tDeviceUs) => toSyncedUs(tDeviceUs) / 1000.0;

  /// Inverse mapping used to derive an absolute device START target from one
  /// common phone monotonic T0.
  int toDeviceUs(num tAppUs) {
    if (slope == 0) throw StateError('Clock model slope is zero');
    return ((tAppUs.toDouble() - interceptUs) / slope).round();
  }
}

/// Legacy offset-based conversion retained for old tests/session code.
class ScheduledStart {
  const ScheduledStart._();

  static int compute({
    required int tStartPhoneMs,
    required int tAppRefMs,
    required int offsetUs,
    required int tDeviceRefUs,
  }) {
    return (tStartPhoneMs - tAppRefMs) * 1000 + offsetUs + tDeviceRefUs;
  }
}

int computeUtcStartMs({
  required int utcEpochNowMs,
  required int nowPhoneMs,
  required int tStartPhoneMs,
}) {
  return utcEpochNowMs + (tStartPhoneMs - nowPhoneMs);
}
