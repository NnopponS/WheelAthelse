import 'dart:typed_data';
import 'dart:math' as math;

import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

const double _gravity = 9.80665;
const double _degreesToRadians = math.pi / 180.0;
const int trajectoryTargetRawHz = 100;
const int trajectoryGroupSize = 5;
const int trajectoryMinimumModelSteps = 40;

class TrajectoryModelException implements Exception {
  const TrajectoryModelException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TrajectoryPoint {
  const TrajectoryPoint(this.x, this.y);
  final double x;
  final double y;
}

class TrajectoryResult {
  const TrajectoryResult({
    required this.points,
    this.modelLabel = 'Trajectory model',
    this.warnings = const [],
    double? pathLengthM,
    double? endpointM,
  }) : _pathLengthM = pathLengthM,
       _endpointM = endpointM;

  final List<TrajectoryPoint> points;
  final String modelLabel;
  final List<String> warnings;
  final double? _pathLengthM;
  final double? _endpointM;

  double get pathLengthM => _pathLengthM ?? _computePathLength(points);
  double get endpointM => _endpointM ?? _computeEndpoint(points);

  factory TrajectoryResult.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['xy'];
    if (rawPoints is! List || rawPoints.length < 2) {
      throw const TrajectoryModelException(
        'Model response must contain at least two XY points.',
      );
    }
    final points = <TrajectoryPoint>[];
    for (final raw in rawPoints) {
      if (raw is! List || raw.length < 2 || raw[0] is! num || raw[1] is! num) {
        throw const TrajectoryModelException(
          'Model response contains invalid XY data.',
        );
      }
      final x = (raw[0] as num).toDouble();
      final y = (raw[1] as num).toDouble();
      if (!x.isFinite || !y.isFinite) {
        throw const TrajectoryModelException(
          'Model response contains non-finite XY data.',
        );
      }
      points.add(TrajectoryPoint(x, y));
    }
    return TrajectoryResult(
      points: List.unmodifiable(points),
      modelLabel: (json['model_label'] as String?)?.trim().isNotEmpty == true
          ? (json['model_label'] as String).trim()
          : 'Trajectory model',
      warnings:
          (json['warnings'] as List?)
              ?.whereType<Object>()
              .map((item) => item.toString())
              .toList(growable: false) ??
          const [],
      pathLengthM: (json['path_length_m'] as num?)?.toDouble(),
      endpointM: (json['endpoint_m'] as num?)?.toDouble(),
    );
  }

  static double _computePathLength(List<TrajectoryPoint> points) {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += math.sqrt(
        math.pow(points[i].x - points[i - 1].x, 2) +
            math.pow(points[i].y - points[i - 1].y, 2),
      );
    }
    return total;
  }

  static double _computeEndpoint(List<TrajectoryPoint> points) {
    if (points.length < 2) return 0;
    final start = points.first;
    final end = points.last;
    return math.sqrt(
      math.pow(end.x - start.x, 2) + math.pow(end.y - start.y, 2),
    );
  }
}

class TrajectoryPreprocessResult {
  const TrajectoryPreprocessResult({
    required this.windows,
    required this.rawAlignedSampleCount,
    required this.durationSeconds,
    this.warnings = const [],
  });

  /// Model input grouped as `(T, 5, 12)`.
  /// Channel order per raw sample is:
  /// `L ax ay az gx gy gz, R ax ay az gx gy gz`.
  /// Acceleration is m/s2 and gyro is rad/s.
  final List<List<List<double>>> windows;
  final int rawAlignedSampleCount;
  final double durationSeconds;
  final List<String> warnings;

  int get modelStepCount => windows.length;
}

class _TimedReading {
  const _TimedReading(this.tSeconds, this.sample);
  final double tSeconds;
  final BufferedSample sample;
}

TrajectoryPreprocessResult prepareTrajectoryInput(
  List<BufferedSample> samples, {
  required int sourceRateHz,
}) {
  if (sourceRateHz <= 0) {
    throw const TrajectoryModelException('Session sample rate is invalid.');
  }
  final left = _timeline(samples, WheelSide.left, sourceRateHz);
  final right = _timeline(samples, WheelSide.right, sourceRateHz);
  if (left.length < 2 || right.length < 2) {
    throw const TrajectoryModelException(
      'Trajectory inference requires both left and right wheel recordings.',
    );
  }

  final overlapStart = math.max(left.first.tSeconds, right.first.tSeconds);
  final overlapEnd = math.min(left.last.tSeconds, right.last.tSeconds);
  if (overlapEnd <= overlapStart) {
    throw const TrajectoryModelException(
      'Left and right wheel timelines do not overlap.',
    );
  }

  const step = 1.0 / trajectoryTargetRawHz;
  final rawCount = (((overlapEnd - overlapStart) / step).floor() + 1);
  final usableRawCount = rawCount - (rawCount % trajectoryGroupSize);
  final modelSteps = usableRawCount ~/ trajectoryGroupSize;
  if (modelSteps < trajectoryMinimumModelSteps) {
    throw const TrajectoryModelException(
      'Trajectory inference needs at least '
      '${trajectoryMinimumModelSteps * trajectoryGroupSize / trajectoryTargetRawHz} '
      'seconds of overlapping dual-wheel data.',
    );
  }

  final warnings = <String>[];
  if (sourceRateHz != trajectoryTargetRawHz) {
    warnings.add(
      'Session was recorded at $sourceRateHz Hz and resampled to '
      '$trajectoryTargetRawHz Hz for the model.',
    );
  }

  final rows = <List<double>>[];
  var li = 0;
  var ri = 0;
  for (var index = 0; index < usableRawCount; index++) {
    final t = overlapStart + index * step;
    final leftInterp = _interpolate(left, t, li);
    li = leftInterp.$2;
    final rightInterp = _interpolate(right, t, ri);
    ri = rightInterp.$2;
    rows.add([...leftInterp.$1, ...rightInterp.$1]);
  }

  final windows = <List<List<double>>>[];
  for (var index = 0; index < rows.length; index += trajectoryGroupSize) {
    windows.add(
      List.unmodifiable(
        rows
            .sublist(index, index + trajectoryGroupSize)
            .map(List<double>.unmodifiable),
      ),
    );
  }

  return TrajectoryPreprocessResult(
    windows: List.unmodifiable(windows),
    rawAlignedSampleCount: usableRawCount,
    durationSeconds: usableRawCount / trajectoryTargetRawHz,
    warnings: List.unmodifiable(warnings),
  );
}

List<_TimedReading> _timeline(
  List<BufferedSample> samples,
  WheelSide side,
  int sourceRateHz,
) {
  final selected = samples.where((sample) => sample.wheel == side).toList()
    ..sort((a, b) {
      final synced = a.timestampSyncedMs.compareTo(b.timestampSyncedMs);
      return synced != 0 ? synced : a.reading.seq.compareTo(b.reading.seq);
    });
  if (selected.isEmpty) return const [];

  // The saved synchronized timestamp is the authoritative shared timeline.
  // When legacy sessions have repeated/invalid synced times, fall back to the
  // sequence cadence anchored at the first valid synchronized time.
  final first = selected.first;
  final originSeconds = first.timestampSyncedMs / 1000.0;
  final firstSeq = first.reading.seq;
  var lastT = double.negativeInfinity;
  final result = <_TimedReading>[];
  for (final sample in selected) {
    var t = sample.timestampSyncedMs / 1000.0;
    if (!t.isFinite || t <= lastT) {
      final deltaSeq = (sample.reading.seq - firstSeq) & 0xFFFFFFFF;
      t = originSeconds + deltaSeq / sourceRateHz;
    }
    if (t <= lastT) continue;
    result.add(_TimedReading(t, sample));
    lastT = t;
  }
  return result;
}

(List<double>, int) _interpolate(
  List<_TimedReading> input,
  double t,
  int hint,
) {
  var i = hint.clamp(0, input.length - 2);
  while (i + 1 < input.length - 1 && input[i + 1].tSeconds < t) {
    i++;
  }
  while (i > 0 && input[i].tSeconds > t) {
    i--;
  }
  final a = input[i];
  final b = input[math.min(i + 1, input.length - 1)];
  final span = b.tSeconds - a.tSeconds;
  final alpha = span <= 0 ? 0.0 : ((t - a.tSeconds) / span).clamp(0.0, 1.0);
  double lerp(double av, double bv) => av + (bv - av) * alpha;
  final ar = a.sample.reading;
  final br = b.sample.reading;
  return (
    [
      lerp(ar.ax, br.ax) * _gravity,
      lerp(ar.ay, br.ay) * _gravity,
      lerp(ar.az, br.az) * _gravity,
      lerp(ar.gx, br.gx) * _degreesToRadians,
      lerp(ar.gy, br.gy) * _degreesToRadians,
      lerp(ar.gz, br.gz) * _degreesToRadians,
    ],
    i,
  );
}

const int biwheel3dFeatureDim = 90;

/// Exact Dart port of BiWheel3D `imu_window_features` protocol v10b.
///
/// Input is the already aligned `(T, 5, 12)` SI-unit tensor produced by
/// [prepareTrajectoryInput]. Output is a row-major Float32 tensor `(T, 90)`.
Float32List extractBiwheel3dFeatures(TrajectoryPreprocessResult input) {
  final windows = input.windows;
  final steps = windows.length;
  if (steps < trajectoryMinimumModelSteps) {
    throw const TrajectoryModelException(
      'Not enough model steps for inference.',
    );
  }

  // Canonicalize the mirrored right hub exactly like BiWheel3D imu_frame.py.
  final w = List.generate(
    steps,
    (t) => List.generate(trajectoryGroupSize, (sample) {
      final row = List<double>.of(windows[t][sample]);
      if (row.length != 12) {
        throw const TrajectoryModelException(
          'Trajectory model input must contain 12 channels per raw sample.',
        );
      }
      row[11] = -row[11]; // RIGHT_GZ_SIGN = -1.0
      return row;
    }, growable: false),
    growable: false,
  );

  final mu = List.generate(steps, (_) => List<double>.filled(12, 0));
  for (var t = 0; t < steps; t++) {
    for (var sample = 0; sample < trajectoryGroupSize; sample++) {
      for (var c = 0; c < 12; c++) {
        mu[t][c] += w[t][sample][c] / trajectoryGroupSize;
      }
    }
  }

  const dt = 0.05;
  const radiusM = 0.30;
  const wheelbaseM = 0.52;
  const g = 9.80665;
  final lgz = List.generate(steps, (i) => mu[i][5], growable: false);
  final rgz = List.generate(steps, (i) => mu[i][11], growable: false);

  final leftDemod = _demodRimAccel(
    List.generate(steps, (i) => mu[i][0], growable: false),
    List.generate(steps, (i) => mu[i][1], growable: false),
    lgz,
    dt: dt,
  );
  final rightDemod = _demodRimAccel(
    List.generate(steps, (i) => mu[i][6], growable: false),
    List.generate(steps, (i) => mu[i][7], growable: false),
    rgz,
    dt: dt,
  );
  final lf = leftDemod.$1;
  final ll = leftDemod.$2;
  final rf = rightDemod.$1;
  final rl = rightDemod.$2;
  final fwd = List.generate(steps, (i) => 0.5 * (lf[i] + rf[i]));
  final lat = List.generate(steps, (i) => 0.5 * (ll[i] + rl[i]));
  final azBase = List.generate(
    steps,
    (i) => 0.5 * (mu[i][2] + mu[i][8]),
    growable: false,
  );
  final azLp = _movingAverageSame(azBase, 11);

  final out = Float32List(steps * biwheel3dFeatureDim);
  for (var t = 0; t < steps; t++) {
    final features = <double>[];
    // flat60
    for (var sample = 0; sample < trajectoryGroupSize; sample++) {
      features.addAll(w[t][sample]);
    }
    // mean12
    features.addAll(mu[t]);
    // kin6
    features.addAll([
      0.5 * (lgz[t] - rgz[t]) * dt,
      0.5 * (lgz[t] + rgz[t]) * dt,
      (radiusM / wheelbaseM) * (rgz[t] - lgz[t]) * dt,
      (radiusM / wheelbaseM) * (lgz[t] - rgz[t]) * dt,
      lgz[t].abs() * dt,
      rgz[t].abs() * dt,
    ]);
    // grav12
    final phiR = math.asin((rf[t] / g).clamp(-1.0, 1.0));
    final phiL = math.asin((lf[t] / g).clamp(-1.0, 1.0));
    final phiMean = math.asin((fwd[t] / g).clamp(-1.0, 1.0));
    final pitch = math.atan2(-fwd[t], math.max(azLp[t].abs(), 1.0));
    features.addAll([
      lf[t],
      ll[t],
      rf[t],
      rl[t],
      fwd[t],
      lat[t],
      azLp[t],
      phiR,
      phiL,
      phiMean,
      phiMean.abs(),
      pitch,
    ]);
    if (features.length != biwheel3dFeatureDim) {
      throw StateError(
        'BiWheel3D feature extraction produced ${features.length} values.',
      );
    }
    out.setRange(
      t * biwheel3dFeatureDim,
      (t + 1) * biwheel3dFeatureDim,
      Float32List.fromList(features),
    );
  }
  return out;
}

(List<double>, List<double>) _demodRimAccel(
  List<double> x,
  List<double> y,
  List<double> gz, {
  required double dt,
}) {
  final n = x.length;
  final fwd = List<double>.filled(n, 0);
  final lat = List<double>.filled(n, 0);
  var theta = 0.0;
  var theta0 = 0.0;
  for (var i = 0; i < n; i++) {
    theta += gz[i] * dt;
    if (i == 0) theta0 = theta;
    final angle = -(theta - theta0);
    final c = math.cos(angle);
    final s = math.sin(angle);
    fwd[i] = x[i] * c - y[i] * s;
    lat[i] = x[i] * s + y[i] * c;
  }
  return (_movingAverageSame(fwd, 21), _movingAverageSame(lat, 21));
}

/// NumPy `np.convolve(x, ones(win)/win, mode="same")` for input >= win.
/// Edge values intentionally divide by the full window (zero padding).
List<double> _movingAverageSame(List<double> input, int win) {
  if (input.length < win) {
    throw TrajectoryModelException(
      'BiWheel3D smoothing requires at least $win model steps.',
    );
  }
  final half = win ~/ 2;
  return List.generate(input.length, (i) {
    var sum = 0.0;
    final start = math.max(0, i - half);
    final end = math.min(input.length - 1, i + half);
    for (var j = start; j <= end; j++) {
      sum += input[j];
    }
    return sum / win;
  }, growable: false);
}

/// Matches BiWheel3D `align_first_travel_xy`: origin reset, then rotate the
/// first 0.30 m of planar travel onto +X for stable visualization.
List<TrajectoryPoint> alignBiwheel3dTrajectory(
  List<TrajectoryPoint> raw, {
  double alignDistanceM = 0.30,
}) {
  if (raw.length < 2) {
    throw const TrajectoryModelException(
      'On-device model must return at least two XY points.',
    );
  }
  final ox = raw.first.x;
  final oy = raw.first.y;
  final shifted = raw
      .map((p) => TrajectoryPoint(p.x - ox, p.y - oy))
      .toList(growable: false);

  var cumulative = 0.0;
  var j = 1;
  for (var i = 1; i < shifted.length; i++) {
    cumulative += math.sqrt(
      math.pow(shifted[i].x - shifted[i - 1].x, 2) +
          math.pow(shifted[i].y - shifted[i - 1].y, 2),
    );
    j = i;
    if (cumulative >= alignDistanceM) break;
  }
  var tx = shifted[j].x;
  var ty = shifted[j].y;
  if (math.sqrt(tx * tx + ty * ty) < 0.05) {
    final fallback = shifted[math.min(20, shifted.length - 1)];
    tx = fallback.x;
    ty = fallback.y;
  }
  final yaw = math.atan2(ty, tx);
  final c = math.cos(yaw);
  final sn = math.sin(yaw);
  return List.unmodifiable(
    shifted.map(
      (p) => TrajectoryPoint(c * p.x + sn * p.y, -sn * p.x + c * p.y),
    ),
  );
}

abstract interface class TrajectoryModelClient {
  Future<TrajectoryResult> infer({
    required SessionMeta meta,
    required TrajectoryPreprocessResult input,
  });
}
