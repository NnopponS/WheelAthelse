import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/model/on_device_trajectory_model.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';

TrajectoryPreprocessResult input({bool complete = true}) {
  final fixture =
      jsonDecode(
            File('test/fixtures/biwheel3d_features.json').readAsStringSync(),
          )
          as Map;
  final windows = (fixture['windows'] as List)
      .map(
        (step) => (step as List)
            .map(
              (sample) =>
                  (sample as List).map((v) => (v as num).toDouble()).toList(),
            )
            .toList(),
      )
      .toList();
  return TrajectoryPreprocessResult(
    windows: windows,
    rawAlignedSampleCount: windows.length * 5,
    durationSeconds: windows.length * 0.05,
    timeSeconds: List.generate(windows.length, (i) => 4.02 + i * 0.05),
    qualityFlags: complete
        ? List.generate(windows.length, (_) => <String>[])
        : const [],
    metadata: {
      'time_basis': 'synthetic_declared_recording_relative',
      'fixture': true,
    },
    warnings: const [
      'Synthetic native inference test; not athlete or Android-device validation.',
    ],
  );
}

SessionMeta meta() => SessionMeta(
  sessionId: 'native-contract-test',
  topic: 'synthetic',
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
    'native bundled ONNX preserves provided time and null chair-orientation fields',
    () async {
      final client = OnDeviceTrajectoryModelClient();
      addTearDown(client.dispose);
      final prepared = input();
      final result = await client.infer(meta: meta(), input: prepared);
      final a = result.analysis!;
      expect(a.samples.length, result.points.length);
      expect(a.samples.first.timeS, 4.02);
      expect(a.samples.last.timeS, prepared.timeSeconds.last);
      expect(a.metadata['model_sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        a.samples.every(
          (p) =>
              p['yaw_rad'] == null &&
              p['yaw_rate_radps'] == null &&
              p['signed_speed_mps'] == null &&
              p['longitudinal_accel_mps2'] == null,
        ),
        isTrue,
      );
      expect(a.samples[0].xM, result.points[0].x);
      expect(a.samples[0].yM, result.points[0].y);
      expect(a.metadata['physical_sync_verified'], isFalse);
      expect(
        a.metadata['model_validation_status'],
        'not_independently_validated',
      );
    },
  );
  test(
    'partially provided time contract fails instead of fabricating missing QC',
    () async {
      final client = OnDeviceTrajectoryModelClient();
      addTearDown(client.dispose);
      await expectLater(
        client.infer(meta: meta(), input: input(complete: false)),
        throwsA(isA<TrajectoryModelException>()),
      );
    },
  );
  test(
    'dispose during outstanding preparation rejects result and blocks reuse',
    () async {
      final client = OnDeviceTrajectoryModelClient();
      final run = client.infer(meta: meta(), input: input());
      final rejected = expectLater(
        run,
        throwsA(isA<TrajectoryModelException>()),
      );
      final dispose = client.dispose();
      await rejected;
      await dispose;
      await expectLater(
        client.infer(meta: meta(), input: input()),
        throwsA(isA<TrajectoryModelException>()),
      );
    },
  );
}
