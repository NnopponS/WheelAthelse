import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/model/three_imu_trajectory_model.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/model_management_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

BufferedSample _makeSample({
  required WheelSide side,
  required int seq,
  required double tMs,
  double gzDeg = 0,
}) => BufferedSample(
  reading: ImuReading(
    seq: seq,
    tDeviceUs: seq * 10000,
    ax: 0,
    ay: 0,
    az: 1,
    gx: 0,
    gy: 0,
    gz: gzDeg,
  ),
  wheel: side,
  timestampAppMs: tMs.round(),
  timestampSyncedMs: tMs,
);

List<BufferedSample> _generateThreeImuSamples({
  required int sampleCount,
  required double gzLeftDeg,
  required double gzRightDeg,
  required double gzCenterDeg,
}) {
  final samples = <BufferedSample>[];
  for (var i = 0; i < sampleCount; i++) {
    final tMs = i * 10.0; // 100 Hz
    samples.add(_makeSample(
      side: WheelSide.left,
      seq: i,
      tMs: tMs,
      gzDeg: gzLeftDeg,
    ));
    samples.add(_makeSample(
      side: WheelSide.right,
      seq: i,
      tMs: tMs,
      gzDeg: gzRightDeg,
    ));
    samples.add(_makeSample(
      side: WheelSide.center,
      seq: i,
      tMs: tMs,
      gzDeg: gzCenterDeg,
    ));
  }
  return samples;
}

SessionMeta _testMeta({String id = 'test-session', int sampleCount = 250}) => SessionMeta(
  sessionId: id,
  topic: 'three_imu_sprint',
  trialNumber: 1,
  sampleRateHz: 100,
  startTime: DateTime.utc(2026, 3, 1),
  durationMs: (sampleCount * 10),
  sampleCount: sampleCount,
  markerCount: 0,
  recordedSides: const ['L', 'R', 'C'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThreeImuTrajectoryModelClient', () {
    test('produces straight line forward trajectory when both wheels roll forward equally', () async {
      // Forward rotation: Left gz is +300 deg/s, Right gz is -300 deg/s, Center is 0
      final samples = _generateThreeImuSamples(
        sampleCount: 150,
        gzLeftDeg: 300,
        gzRightDeg: -300,
        gzCenterDeg: 0,
      );
      final meta = _testMeta(sampleCount: 150);

      const client = ThreeImuTrajectoryModelClient();
      final result = await client.inferFromSamples(meta: meta, samples: samples);

      expect(result.modelLabel, threeImuV4ModelLabel);
      expect(result.points.length, equals(150));
      expect(result.pathLengthM, greaterThan(0.5));
      expect(result.endpointM, closeTo(result.pathLengthM, 0.05));

      final lastPoint = result.points.last;
      expect(lastPoint.x, greaterThan(0.5));
      expect(lastPoint.y.abs(), lessThan(0.05));
    });

    test('rejects sessions missing Center sensor cleanly', () async {
      final samples = <BufferedSample>[];
      for (var i = 0; i < 50; i++) {
        final tMs = i * 10.0;
        samples.add(_makeSample(side: WheelSide.left, seq: i, tMs: tMs));
        samples.add(_makeSample(side: WheelSide.right, seq: i, tMs: tMs));
      }
      final meta = _testMeta(sampleCount: 50);

      const client = ThreeImuTrajectoryModelClient();
      expect(
        () => client.inferFromSamples(meta: meta, samples: samples),
        throwsA(isA<TrajectoryModelException>()),
      );
    });

    test('is registered in availableModelsProvider as primary 3-IMU model', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final models = container.read(availableModelsProvider);
      final v4Model = models.firstWhere((m) => m.key == threeImuV4ModelKey);

      expect(v4Model.label, threeImuV4ModelLabel);
      expect(v4Model.requiredSensorRoles, equals(['L', 'R', 'C']));
      expect(v4Model.isBundled, isTrue);
      expect(v4Model.isExperimental, isFalse);
    });
  });
}
