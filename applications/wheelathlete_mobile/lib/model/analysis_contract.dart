import 'dart:convert';
import 'dart:math' as math;

const analysisFields = <String>[
  'time_s',
  'x_m',
  'y_m',
  'signed_speed_mps',
  'speed_mps',
  'longitudinal_accel_mps2',
  'yaw_rad',
  'yaw_rate_radps',
  'lateral_accel_mps2',
  'speed_change_mps2',
];
const _invalidInputFlags = {
  'small_gap_interpolated',
  'sensor_clipping',
  'input_invalid',
};

double _number(Object? value, String name) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$name must be finite numeric data');
  }
  return value.toDouble();
}

Object? _freeze(Object? value) {
  if (value is num && !value.isFinite) {
    throw const FormatException('Non-finite metadata');
  }
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((k, v) {
        if (k is! String) {
          throw const FormatException('Metadata keys must be strings');
        }
        return MapEntry(k, _freeze(v));
      }),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw const FormatException('Metadata must be JSON-compatible');
}

class AnalysisSample {
  AnalysisSample._(this.values, this.qualityFlags);
  final Map<String, double?> values;
  final List<String> qualityFlags;
  double get timeS => values['time_s']!;
  double get xM => values['x_m']!;
  double get yM => values['y_m']!;
  double? operator [](String field) => values[field];
  bool get inputSupported => !qualityFlags.any(_invalidInputFlags.contains);

  factory AnalysisSample.fromJson(Map<String, dynamic> json) {
    final values = <String, double?>{};
    for (final field in analysisFields) {
      if (!json.containsKey(field)) throw FormatException('Missing $field');
      final v = json[field];
      values[field] = v == null && analysisFields.indexOf(field) >= 3
          ? null
          : _number(v, field);
    }
    if (values['time_s']! < 0 || (values['speed_mps'] ?? 0) < 0) {
      throw const FormatException('Negative time or speed magnitude');
    }
    final signed = values['signed_speed_mps'];
    final speed = values['speed_mps'];
    if (signed != null &&
        speed != null &&
        (signed.abs() - speed).abs() > 1e-6) {
      throw const FormatException('Signed speed and magnitude disagree');
    }
    final flags = json['quality_flags'];
    if (flags is! List || flags.any((f) => f is! String)) {
      throw const FormatException('Invalid quality flags');
    }
    return AnalysisSample._(
      Map.unmodifiable(values),
      List<String>.unmodifiable(flags.cast<String>()),
    );
  }

  Map<String, dynamic> toJson() => {
    ...values,
    'quality_flags': List<String>.of(qualityFlags),
  };
}

class KinematicAnalysis {
  KinematicAnalysis._(this.metadata, this.samples);
  final Map<String, dynamic> metadata;
  final List<AnalysisSample> samples;

  factory KinematicAnalysis.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 ||
        json['metadata'] is! Map ||
        json['samples'] is! List) {
      throw const FormatException('Unsupported analysis schema');
    }
    final raw = json['samples'] as List;
    if (raw.length < 2) {
      throw const FormatException('Analysis needs at least two samples');
    }
    final samples = raw
        .map((row) {
          if (row is! Map) throw const FormatException('Invalid analysis row');
          return AnalysisSample.fromJson(Map<String, dynamic>.from(row));
        })
        .toList(growable: false);
    for (var i = 1; i < samples.length; i++) {
      if (samples[i].timeS <= samples[i - 1].timeS) {
        throw const FormatException('Analysis time must increase strictly');
      }
    }
    final metadata = _freeze(json['metadata']) as Map<String, dynamic>;
    return KinematicAnalysis._(metadata, List.unmodifiable(samples));
  }

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'metadata': jsonDecode(jsonEncode(metadata)),
    'samples': samples.map((v) => v.toJson()).toList(growable: false),
  };

  int nearestIndex(double timeS) {
    _number(timeS, 'cursor time');
    var lo = 0, hi = samples.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (samples[mid].timeS < timeS) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == 0) return 0;
    if (lo == samples.length) return lo - 1;
    return timeS - samples[lo - 1].timeS <= samples[lo].timeS - timeS + 1e-12
        ? lo - 1
        : lo;
  }

  Map<String, dynamic> windowStatistics(double start, double stop) {
    _number(start, 'window start');
    _number(stop, 'window stop');
    if (stop < start) throw const FormatException('Window stop precedes start');
    var lo = 0;
    while (lo < samples.length && samples[lo].timeS < start - 1e-12) {
      lo++;
    }
    var hi = lo;
    while (hi < samples.length && samples[hi].timeS <= stop + 1e-12) {
      hi++;
    }
    final chosen = samples.sublist(lo, hi);
    final metrics = <String, dynamic>{};
    for (final field in analysisFields.skip(3)) {
      final values = chosen.map((p) => p[field]).whereType<double>().toList();
      var total = 0.0, support = 0.0;
      for (var i = 1; i < chosen.length; i++) {
        final a = chosen[i - 1][field], b = chosen[i][field];
        final dt = chosen[i].timeS - chosen[i - 1].timeS;
        if (a != null && b != null && dt <= .075 + 1e-9) {
          total += .5 * (a + b) * dt;
          support += dt;
        }
      }
      metrics[field] = {
        'samples': values.length,
        'mean': support > 0 ? total / support : null,
        'min': values.isEmpty ? null : values.reduce(math.min),
        'max': values.isEmpty ? null : values.reduce(math.max),
        'supported_duration_s': support,
      };
    }
    var distance = 0.0;
    for (var i = 1; i < chosen.length; i++) {
      final dx = chosen[i].xM - chosen[i - 1].xM,
          dy = chosen[i].yM - chosen[i - 1].yM;
      distance += math.sqrt(dx * dx + dy * dy);
    }
    double? netYaw;
    if (chosen.length > 1) {
      final a = chosen.first['yaw_rad'], b = chosen.last['yaw_rad'];
      if (a != null && b != null) netYaw = b - a;
    }
    final flags = chosen.expand((p) => p.qualityFlags).toSet().toList()..sort();
    return {
      'start_index': lo,
      'stop_index_exclusive': hi,
      'samples': chosen.length,
      'duration_s': chosen.length > 1
          ? chosen.last.timeS - chosen.first.timeS
          : 0.0,
      'path_length_m': distance,
      'net_yaw_rad': netYaw,
      'metrics': metrics,
      'quality_flags': flags,
      'interpretation':
          'descriptive experimental estimates; time-weighted means; no independent accuracy claim',
    };
  }
}

/// Same seven-sample local-linear derivative as the Python offline contract.
List<double?> analysisDerivative(
  List<double> times,
  List<double?> values, [
  List<bool>? invalid,
]) {
  if (values.length != times.length ||
      (invalid != null && invalid.length != times.length)) {
    throw const FormatException('Derivative lengths differ');
  }
  for (var i = 0; i < times.length; i++) {
    _number(times[i], 'derivative time');
    if (i > 0 && times[i] <= times[i - 1]) {
      throw const FormatException('Nonmonotonic derivative time');
    }
    if (values[i] != null) _number(values[i], 'derivative value');
  }
  final output = List<double?>.filled(times.length, null);
  for (var i = 3; i < times.length - 3; i++) {
    final segment = values.sublist(i - 3, i + 4);
    if (segment.any((v) => v == null) ||
        (invalid?.sublist(i - 3, i + 4).any((v) => v) ?? false)) {
      continue;
    }
    final t = times.sublist(i - 3, i + 4).map((v) => v - times[i]).toList();
    var gap = false;
    for (var j = 1; j < t.length; j++) {
      if (t[j] - t[j - 1] > .075 + 1e-9) gap = true;
    }
    if (gap) continue;
    final tm = t.reduce((a, b) => a + b) / 7;
    final vm = segment.whereType<double>().reduce((a, b) => a + b) / 7;
    var num = 0.0, den = 0.0;
    for (var j = 0; j < 7; j++) {
      num += (t[j] - tm) * (segment[j]! - vm);
      den += (t[j] - tm) * (t[j] - tm);
    }
    output[i] = num / den;
  }
  return output;
}

KinematicAnalysis buildKinematicAnalysis({
  required List<double> times,
  required List<List<double>> xy,
  required List<List<String>> flags,
  List<double>? signedSpeed,
  List<double>? yaw,
  List<double>? yawRate,
  Map<String, dynamic> metadata = const {},
}) {
  final n = times.length;
  if (n < 2 ||
      xy.length != n ||
      flags.length != n ||
      xy.any((p) => p.length != 2)) {
    throw const FormatException('Analysis arrays have incompatible lengths');
  }
  for (final a in [signedSpeed, yaw, yawRate]) {
    if (a != null && a.length != n) {
      throw const FormatException('Kinematics length mismatch');
    }
  }
  final bad = flags.map((f) => f.any(_invalidInputFlags.contains)).toList();
  final List<double?> speed;
  final List<double?> accel;
  if (signedSpeed == null) {
    final dx = analysisDerivative(times, xy.map((p) => p[0]).toList(), bad);
    final dy = analysisDerivative(times, xy.map((p) => p[1]).toList(), bad);
    speed = List.generate(n, (i) {
      final x = dx[i], y = dy[i];
      return x == null || y == null ? null : math.sqrt(x * x + y * y);
    });
    accel = List.filled(n, null);
  } else {
    speed = signedSpeed.map((v) => v.abs()).toList();
    accel = analysisDerivative(times, signedSpeed, bad);
  }
  final speedChange = analysisDerivative(times, speed, bad);
  final rows = List.generate(n, (i) {
    final f = {
      ...flags[i],
      if (signedSpeed == null) 'xy_only_model',
      if (signedSpeed != null && accel[i] == null)
        'derivative_support_unavailable',
    }.toList()..sort();
    final values = <double?>[
      times[i],
      xy[i][0],
      xy[i][1],
      signedSpeed?[i],
      speed[i],
      accel[i],
      yaw?[i],
      yawRate?[i],
      null,
      speedChange[i],
    ];
    return <String, dynamic>{
      ...Map.fromIterables(analysisFields, values),
      'quality_flags': f,
    };
  });
  return KinematicAnalysis.fromJson({
    'schema_version': 1,
    'metadata': {
      ...metadata,
      'schema_version': 1,
      'algorithm_contract': 'wheelathlete.offline_kinematics.v1',
      'mode': 'offline',
      'sample_rate_hz': 20.0,
      'sample_semantics':
          'five-input-sample window center; one full-session pose state',
      'model_validation_status': 'not_independently_validated',
      'physical_sync_verified': false,
      'derivative': {
        'method': 'centered_local_linear_7',
        'half_window_samples': 3,
        'nominal_support_span_s': .30,
        'edge_policy': 'null',
        'gap_or_clipping_support': 'null',
      },
      'live_latency': 'undefined_offline_whole_session',
      'lateral_accel_reason': 'not exposed without validated no-slip support',
      'signed_speed_reason': signedSpeed != null
          ? 'estimator output'
          : 'unavailable from XY-only output',
      'speed_reason': signedSpeed != null
          ? 'absolute estimator signed speed'
          : 'XY local-linear derivative magnitude; not signed chair speed',
      'yaw_reason': yaw != null
          ? 'estimator orientation, unwrapped'
          : 'unavailable; trajectory tangent is not chair orientation',
      'coverage': {
        'samples': n,
        'input_unflagged_samples': bad.where((v) => !v).length,
        'longitudinal_accel_samples': accel.whereType<double>().length,
        'speed_samples': speed.whereType<double>().length,
      },
    },
    'samples': rows,
  });
}
