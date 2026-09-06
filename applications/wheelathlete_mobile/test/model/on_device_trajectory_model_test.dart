import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/model/on_device_trajectory_model.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled ONNX model runs offline with dynamic sequence length',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/biwheel3d_features.json',
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
      final input = TrajectoryPreprocessResult(
        windows: windows,
        rawAlignedSampleCount: windows.length * trajectoryGroupSize,
        durationSeconds:
            windows.length * trajectoryGroupSize / trajectoryTargetRawHz,
      );
      final meta = SessionMeta(
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
      final client = OnDeviceTrajectoryModelClient();
      addTearDown(client.dispose);

      final result = await client.infer(meta: meta, input: input);

      expect(result.modelLabel, biwheel3dMobileModelLabel);
      expect(result.points, hasLength(windows.length));
      expect(result.points.every((p) => p.x.isFinite && p.y.isFinite), isTrue);
      expect(result.points.first.x, closeTo(0, 1e-6));
      expect(result.points.first.y, closeTo(0, 1e-6));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
