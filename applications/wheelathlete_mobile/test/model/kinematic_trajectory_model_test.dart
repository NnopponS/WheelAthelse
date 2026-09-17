import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/model/kinematic_trajectory_model.dart';
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

List<BufferedSample> _generateDualWheelSamples({
  required int sampleCount,
  required double gzLeftDeg,
  required double gzRightDeg,
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
  }
  return samples;
}

SessionMeta _testMeta({String id = 'test-session', int sampleCount = 250}) => SessionMeta(
  sessionId: id,
  topic: 'sprint',
  trialNumber: 1,
  sampleRateHz: 100,
  startTime: DateTime.utc(2026, 3, 1),
  durationMs: (sampleCount * 10),
  sampleCount: sampleCount,
  markerCount: 0,
  recordedSides: const ['L', 'R'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KinematicTrajectoryModelClient', () {
    test('produces straight line forward trajectory when both wheels spin forward equally', () async {
      // 50 model steps = 250 raw samples at 100 Hz
      // Forward rotation: Left gz is +300 deg/s, Right gz is -300 deg/s
      final samples = _generateDualWheelSamples(
        sampleCount: 250,
        gzLeftDeg: 300,
        gzRightDeg: -300,
      );
      final meta = _testMeta(sampleCount: 250);
      final input = prepareTrajectoryInput(samples, sourceRateHz: 100, meta: meta);

      expect(input.modelStepCount, 50);

      const client = KinematicTrajectoryModelClient();
      final result = await client.infer(meta: meta, input: input);

      expect(result.modelLabel, kinematicModelLabel);
      expect(result.points.length, equals(50));
      expect(result.pathLengthM, greaterThan(0.5));

      // Straight line forward: endpoint is close to total path length
      expect(result.endpointM, closeTo(result.pathLengthM, 0.05));

      // Points should advance along the positive X direction
      final lastPoint = result.points.last;
      expect(lastPoint.x, greaterThan(0.5));
      expect(lastPoint.y.abs(), lessThan(0.1));

      // Analysis should be populated with kinematic channels
      final analysis = result.analysis;
      expect(analysis, isNotNull);
      expect(analysis!.samples.length, equals(50));

      final firstSample = analysis.samples.first;
      expect(firstSample['time_s'], isNotNull);
      expect(firstSample['x_m'], closeTo(0.0, 1e-6));
      expect(firstSample['y_m'], closeTo(0.0, 1e-6));

      // Check net yaw is close to zero for symmetric straight roll
      final summary = analysis.summary;
      expect((summary['net_yaw_deg'] as num).toDouble().abs(), lessThan(1.0));
      expect((summary['distance_m'] as num).toDouble(), greaterThan(0.5));
      expect((summary['mean_speed_mps'] as num).toDouble(), greaterThan(0.1));
    });

    test('produces curved trajectory and heading deflection when right wheel spins faster', () async {
      // Right wheel spins significantly faster -> turns left (positive heading change)
      final samples = _generateDualWheelSamples(
        sampleCount: 250,
        gzLeftDeg: 100,
        gzRightDeg: -500, // Canonicalized to +500
      );
      final meta = _testMeta(sampleCount: 250);
      final input = prepareTrajectoryInput(samples, sourceRateHz: 100, meta: meta);

      const client = KinematicTrajectoryModelClient(align: false);
      final result = await client.infer(meta: meta, input: input);

      expect(result.points.length, equals(50));
      final analysis = result.analysis;
      expect(analysis, isNotNull);

      // Turning produces nonzero net yaw and yaw rate
      final summary = analysis!.summary;
      expect((summary['net_yaw_deg'] as num).toDouble().abs(), greaterThan(5.0));
      expect((summary['max_yaw_rate_degps'] as num).toDouble(), greaterThan(5.0));
    });

    test('throws TrajectoryModelException when input has fewer than 40 steps', () async {
      // 30 model steps = 150 raw samples (below trajectoryMinimumModelSteps = 40)
      final samples = _generateDualWheelSamples(
        sampleCount: 150,
        gzLeftDeg: 200,
        gzRightDeg: -200,
      );
      final meta = _testMeta(sampleCount: 150);

      expect(
        () => prepareTrajectoryInput(samples, sourceRateHz: 100, meta: meta),
        throwsA(isA<TrajectoryModelException>()),
      );
    });
  });

  group('Model Management Providers', () {
    test('availableModelsProvider registers both kinematic and ONNX models', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final models = container.read(availableModelsProvider);
      expect(models.length, greaterThanOrEqualTo(2));

      final kinematic = models.firstWhere((m) => m.key == kinematicModelKey);
      expect(kinematic.kind, 'recipe');
      expect(kinematic.hasYaw, isTrue);
      expect(kinematic.hasSpeed, isTrue);
      expect(kinematic.requiredSensorRoles, containsAll(['L', 'R']));

      final onnx = models.firstWhere((m) => m.kind == 'onnx');
      expect(onnx.key, 'biwheel3d:m4_onnx');
      expect(onnx.hasYaw, isFalse);

      final activeModel = container.read(activeModelSpecProvider);
      expect(activeModel.key, kinematicModelKey);
    });

    test('selectedModelKeyProvider can switch active model', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(selectedModelKeyProvider.notifier).state = 'biwheel3d:m4_onnx';
      final active = container.read(activeModelSpecProvider);
      expect(active.key, 'biwheel3d:m4_onnx');
      expect(active.kind, 'onnx');
    });
  });
}
