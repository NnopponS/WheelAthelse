import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/theme/theme.dart';

BufferedSample _sample({
  required WheelSide side,
  required int seq,
  required double tMs,
  double ax = 1,
  double ay = 0,
  double az = 0,
  double gx = 180,
  double gy = 0,
  double gz = 0,
}) => BufferedSample(
  reading: ImuReading(
    seq: seq,
    tDeviceUs: seq * 10000,
    ax: ax,
    ay: ay,
    az: az,
    gx: gx,
    gy: gy,
    gz: gz,
  ),
  wheel: side,
  timestampAppMs: tMs.round(),
  timestampSyncedMs: tMs,
);

List<BufferedSample> _dualWheel({int count = 250, int rateHz = 100}) {
  final samples = <BufferedSample>[];
  for (var i = 0; i < count; i++) {
    final tMs = i * 1000.0 / rateHz;
    samples
      ..add(_sample(side: WheelSide.left, seq: i, tMs: tMs))
      ..add(_sample(side: WheelSide.right, seq: i, tMs: tMs, ax: 2, gx: 90));
  }
  return samples;
}

void main() {
  test('preprocess matches PC 100 Hz SI-unit 5x12 contract', () {
    final result = prepareTrajectoryInput(_dualWheel(), sourceRateHz: 100);

    expect(result.rawAlignedSampleCount, 250);
    expect(result.modelStepCount, 50);
    expect(result.windows, hasLength(50));
    expect(result.windows.first, hasLength(5));
    expect(result.windows.first.first, hasLength(12));
    final row = result.windows.first.first;
    expect(row[0], closeTo(9.80665, 1e-6));
    expect(row[3], closeTo(math.pi, 1e-9));
    expect(row[6], closeTo(19.6133, 1e-6));
    expect(row[9], closeTo(math.pi / 2, 1e-9));
    expect(
      result.warnings.any((w) => w.contains('not independently validated')),
      isTrue,
    );
  });

  test('optional center IMU is not inserted into legacy L/R model tensor', () {
    final lr = _dualWheel(count: 250);
    final withCenter = <BufferedSample>[...lr];
    for (var i = 0; i < 250; i++) {
      final tMs = i * 10.0;
      withCenter.add(
        _sample(
          side: WheelSide.center,
          seq: i,
          tMs: tMs,
          ax: 9999,
          ay: -8888,
          az: 7777,
          gx: 6666,
          gy: -5555,
          gz: 4444,
        ),
      );
    }
    final a = prepareTrajectoryInput(lr, sourceRateHz: 100);
    final b = prepareTrajectoryInput(withCenter, sourceRateHz: 100);
    expect(b.windows, equals(a.windows));
    expect(b.timeSeconds, equals(a.timeSeconds));
    expect(b.modelStepCount, a.modelStepCount);
  });

  test('non-100 Hz source is resampled and surfaced as warning', () {
    final result = prepareTrajectoryInput(
      _dualWheel(count: 500, rateHz: 200),
      sourceRateHz: 200,
    );

    expect(result.modelStepCount, 50);
    expect(
      result.warnings.any((w) => w.contains('resampled to 100 Hz')),
      isTrue,
    );
  });

  test('requires both wheels', () {
    final leftOnly = _dualWheel()
        .where((sample) => sample.wheel == WheelSide.left)
        .toList();
    expect(
      () => prepareTrajectoryInput(leftOnly, sourceRateHz: 100),
      throwsA(isA<TrajectoryModelException>()),
    );
  });

  test('requires at least two seconds of overlapping dual-wheel data', () {
    expect(
      () => prepareTrajectoryInput(_dualWheel(count: 150), sourceRateHz: 100),
      throwsA(isA<TrajectoryModelException>()),
    );
  });

  test('trajectory response validates XY and computes metrics', () {
    final result = TrajectoryResult.fromJson({
      'xy': [
        [0, 0],
        [3, 4],
        [6, 4],
      ],
      'model_label': 'M4',
      'warnings': ['example'],
    });

    expect(result.modelLabel, 'M4');
    expect(result.points, hasLength(3));
    expect(result.pathLengthM, closeTo(8, 1e-9));
    expect(result.endpointM, closeTo(math.sqrt(52), 1e-9));
    expect(result.warnings, ['example']);
  });

  test('trajectory response rejects non-finite values', () {
    expect(
      () => TrajectoryResult.fromJson({
        'xy': [
          [0, 0],
          [double.nan, 1],
        ],
      }),
      throwsA(isA<TrajectoryModelException>()),
    );
  });
  test('BiWheel3D feature extractor matches Python reference fixture', () {
    final fixture =
        jsonDecode(
              File(
                '../../docs/model_analysis/fixtures/features_v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final windows = (fixture['windows'] as List)
        .map(
          (step) => (step as List)
              .map(
                (sample) => (sample as List)
                    .map((value) => (value as num).toDouble())
                    .toList(growable: false),
              )
              .toList(growable: false),
        )
        .toList(growable: false);
    final expected = (fixture['features'] as List)
        .expand((row) => row as List)
        .map((value) => (value as num).toDouble())
        .toList(growable: false);
    final input = TrajectoryPreprocessResult(
      windows: windows,
      rawAlignedSampleCount: windows.length * trajectoryGroupSize,
      durationSeconds:
          windows.length * trajectoryGroupSize / trajectoryTargetRawHz,
    );

    final actual = extractBiwheel3dFeatures(input);
    expect(actual, hasLength(expected.length));
    var maxError = 0.0;
    for (var i = 0; i < actual.length; i++) {
      maxError = math.max(maxError, (actual[i] - expected[i]).abs());
    }
    expect(maxError, lessThan(2e-5));
  });

  test('BiWheel3D XY alignment rotates initial travel onto +X', () {
    final aligned = alignBiwheel3dTrajectory(const [
      TrajectoryPoint(10, 20),
      TrajectoryPoint(10, 20.2),
      TrajectoryPoint(10, 20.4),
      TrajectoryPoint(10, 20.8),
    ]);

    expect(aligned.first.x, closeTo(0, 1e-9));
    expect(aligned.first.y, closeTo(0, 1e-9));
    expect(aligned[2].x, closeTo(0.4, 1e-9));
    expect(aligned[2].y, closeTo(0, 1e-9));
    expect(aligned.last.x, greaterThan(0.79));
  });
}
