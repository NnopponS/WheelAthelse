import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/model/analysis_contract.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/theme/theme.dart';

void same(Object? actual, Object? expected, [String path = 'root']) {
  if (expected is num) {
    expect(actual, isA<num>(), reason: path);
    expect(
      (actual as num).toDouble(),
      closeTo(expected.toDouble(), 1e-8),
      reason: path,
    );
  } else if (expected is Map) {
    expect(actual, isA<Map<dynamic, dynamic>>(), reason: path);
    final map = actual as Map<Object?, Object?>;
    expect(map.keys.toSet(), expected.keys.toSet(), reason: path);
    for (final key in expected.keys) {
      same(map[key], expected[key], '$path.$key');
    }
  } else if (expected is List) {
    expect(actual, isA<List<dynamic>>(), reason: path);
    final list = actual as List<Object?>;
    expect(list.length, expected.length, reason: path);
    for (var i = 0; i < expected.length; i++) {
      same(list[i], expected[i], '$path[$i]');
    }
  } else {
    expect(actual, expected, reason: path);
  }
}

List<BufferedSample> samples({
  int count = 300,
  bool gap = false,
  bool longGap = false,
  bool rollover = false,
}) {
  final rows = <BufferedSample>[];
  for (var i = 0; i < count; i++) {
    for (final side in [WheelSide.left, WheelSide.right]) {
      if (side == WheelSide.left &&
          ((gap && i == 100) || (longGap && i >= 100 && i < 110))) {
        continue;
      }
      rows.add(
        BufferedSample(
          reading: ImuReading(
            seq: rollover ? (0xFFFFFFFF - 100 + i) & 0xFFFFFFFF : i,
            tDeviceUs: i * 10000,
            ax: 1.0,
            ay: 0.0,
            az: 0.0,
            gx: 0.0,
            gy: 0.0,
            gz: side == WheelSide.left ? 180.0 : -180.0,
          ),
          wheel: side,
          timestampAppMs: i * 10 + 2000,
          timestampSyncedMs: 4000.0 + i * 10,
        ),
      );
    }
  }
  return rows;
}

void main() {
  final fixture =
      jsonDecode(
            File(
              '../../docs/model_analysis/fixtures/analysis_v1.json',
            ).readAsStringSync(),
          )
          as Map;
  for (final raw in fixture['cases'] as List) {
    final c = raw as Map;
    test('Python/Dart output and window parity: ${c['id']}', () {
      final input = c['input'] as Map;
      List<double>? numbers(Object? v) => v == null
          ? null
          : (v as List).map((n) => (n as num).toDouble()).toList();
      final result = buildKinematicAnalysis(
        times: numbers(input['times'])!,
        xy: (input['xy'] as List).map((p) => numbers(p)!).toList(),
        flags: (input['flags'] as List)
            .map((f) => (f as List).cast<String>())
            .toList(),
        signedSpeed: numbers(input['signed_speed']),
        yaw: numbers(input['yaw']),
        yawRate: numbers(input['yaw_rate']),
        metadata: Map<String, dynamic>.from(input['metadata'] as Map),
      );
      same(result.toJson(), c['expected']);
      final window = numbers(c['window'])!;
      same(
        result.windowStatistics(window[0], window[1]),
        c['window_statistics'],
      );
      same(
        KinematicAnalysis.fromJson(
          jsonDecode(jsonEncode(result.toJson())) as Map<String, dynamic>,
        ).toJson(),
        result.toJson(),
      );
      expect(() => result.samples.clear(), throwsUnsupportedError);
      expect(() => result.metadata['bad'] = 0, throwsUnsupportedError);
    });
  }
  test('preserves crop offset and final valid complete window', () {
    final r = prepareTrajectoryInput(samples(count: 303), sourceRateHz: 100);
    expect(r.timeSeconds.first, closeTo(4.02, 1e-9));
    expect(r.timeSeconds.last, closeTo(6.97, 1e-9));
    expect(r.modelStepCount, 60);
    expect(r.metadata['discarded_tail_samples'], 3);
  });
  test('small gaps are flagged and large gaps are rejected', () {
    final r = prepareTrajectoryInput(samples(gap: true), sourceRateHz: 100);
    expect(
      r.qualityFlags.any((f) => f.contains('small_gap_interpolated')),
      isTrue,
    );
    expect(
      () => prepareTrajectoryInput(samples(longGap: true), sourceRateHz: 100),
      throwsA(isA<TrajectoryModelException>()),
    );
  });
  test('sequence rollover and identical replay retain unique input', () {
    final r = samples(rollover: true);
    r.add(r[10]);
    final result = prepareTrajectoryInput(r, sourceRateHz: 100);
    expect(result.modelStepCount, 60);
    final sides = result.metadata['side_diagnostics'] as Map;
    expect((sides['L'] as Map)['duplicates'], 1);
    expect((sides['L'] as Map)['rollovers'], 1);
  });
  test('invalid saved clock is not replaced silently', () {
    final r = samples();
    r[100] = r[100].copyWith(timestampSyncedMs: double.nan);
    expect(
      () => prepareTrajectoryInput(r, sourceRateHz: 100),
      throwsA(isA<TrajectoryModelException>()),
    );
    final reversed = samples();
    reversed[100] = reversed[100].copyWith(timestampSyncedMs: 0);
    expect(
      () => prepareTrajectoryInput(reversed, sourceRateHz: 100),
      throwsA(isA<TrajectoryModelException>()),
    );
  });
  for (final bad in ['nan', 'missing', 'negative_speed', 'time', 'metadata']) {
    test('reject malformed contract: $bad', () {
      final c = (fixture['cases'] as List).first as Map;
      final value =
          jsonDecode(jsonEncode(c['expected'])) as Map<String, dynamic>;
      final rows = value['samples'] as List;
      if (bad == 'nan') (rows[5] as Map)['x_m'] = double.nan;
      if (bad == 'missing') (rows[5] as Map).remove('yaw_rad');
      if (bad == 'negative_speed') (rows[5] as Map)['speed_mps'] = -1.0;
      if (bad == 'time') (rows[5] as Map)['time_s'] = 0.0;
      if (bad == 'metadata') {
        (value['metadata'] as Map)['bad'] = double.infinity;
      }
      expect(() => KinematicAnalysis.fromJson(value), throwsFormatException);
    });
  }
}
