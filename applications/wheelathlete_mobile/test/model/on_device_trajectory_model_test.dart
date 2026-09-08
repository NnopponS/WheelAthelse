import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/model/on_device_trajectory_model.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';

TrajectoryPreprocessResult fixtureInput() {
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
  // This is a declared synthetic clock, NOT reconstructed capture evidence.
  return TrajectoryPreprocessResult(
    windows: windows,
    rawAlignedSampleCount: windows.length * trajectoryGroupSize,
    durationSeconds:
        windows.length * trajectoryGroupSize / trajectoryTargetRawHz,
    timeSeconds: List.generate(windows.length, (i) => 4.02 + i * 0.05),
    qualityFlags: List.generate(windows.length, (_) => <String>[]),
    metadata: const {'time_basis': 'synthetic_fixture'},
  );
}

SessionMeta fixtureMeta() => SessionMeta(
  sessionId: 'offline-test',
  topic: 'model-test',
  trialNumber: 1,
  sampleRateHz: 100,
  startTime: DateTime.utc(2026),
  durationMs: 2000,
  sampleCount: 400,
  markerCount: 0,
  recordedSides: const ['L', 'R'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled ONNX runs offline and preserves experimental XY-only contract',
    () async {
      final input = fixtureInput();
      final meta = fixtureMeta();
      final client = OnDeviceTrajectoryModelClient();
      addTearDown(client.dispose);
      final pending = client.infer(meta: meta, input: input);
      await expectLater(
        client.infer(meta: meta, input: input),
        throwsA(isA<TrajectoryModelException>()),
      );
      final result = await pending;
      expect(result.modelLabel, biwheel3dMobileModelLabel);
      expect(result.points, hasLength(input.modelStepCount));
      expect(result.points.every((p) => p.x.isFinite && p.y.isFinite), isTrue);
      expect(result.points.first.x, closeTo(0, 1e-6));
      expect(result.points.first.y, closeTo(0, 1e-6));
      final analysis = result.analysis!;
      expect(analysis.samples.length, input.modelStepCount);
      expect(analysis.samples.first.timeS, 4.02);
      expect(analysis.samples.last.timeS, input.timeSeconds.last);
      expect(
        analysis.metadata['model_sha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        analysis.metadata['model_validation_status'],
        'not_independently_validated',
      );
      expect(analysis.metadata['physical_sync_verified'], isFalse);
      for (final sample in analysis.samples) {
        expect(sample['yaw_rad'], isNull);
        expect(sample['yaw_rate_radps'], isNull);
        expect(sample['signed_speed_mps'], isNull);
        expect(sample['longitudinal_accel_mps2'], isNull);
      }
      expect(
        analysis.samples[input.modelStepCount ~/ 2]['speed_mps'],
        isNotNull,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'disposed client rejects inference without opening native model',
    () async {
      final client = OnDeviceTrajectoryModelClient();
      await client.dispose();
      await expectLater(
        client.infer(meta: fixtureMeta(), input: fixtureInput()),
        throwsA(isA<TrajectoryModelException>()),
      );
    },
  );
}
