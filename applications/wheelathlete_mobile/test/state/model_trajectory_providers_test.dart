import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/model/trajectory_model.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/state/model_trajectory_providers.dart';
import 'package:wheelathlete/state/preview_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

class _FakeModelClient implements TrajectoryModelClient {
  int calls = 0;
  TrajectoryPreprocessResult? input;

  @override
  Future<TrajectoryResult> infer({
    required SessionMeta meta,
    required TrajectoryPreprocessResult input,
  }) async {
    calls++;
    this.input = input;
    return const TrajectoryResult(
      modelLabel: 'Fake M4',
      points: [TrajectoryPoint(0, 0), TrajectoryPoint(1, 2)],
    );
  }
}

BufferedSample _sample(WheelSide side, int i) => BufferedSample(
  reading: ImuReading(
    seq: i,
    tDeviceUs: i * 10000,
    ax: side == WheelSide.left ? 1 : 2,
    ay: 0,
    az: 0,
    gx: 0,
    gy: 0,
    gz: 0,
  ),
  wheel: side,
  timestampAppMs: i * 10,
  timestampSyncedMs: i * 10.0,
);

void main() {
  test(
    'provider preprocesses full in-memory session and calls on-device model',
    () async {
      final samples = <BufferedSample>[];
      for (var i = 0; i < 250; i++) {
        samples
          ..add(_sample(WheelSide.left, i))
          ..add(_sample(WheelSide.right, i));
      }
      final meta = SessionMeta(
        sessionId: 'abc',
        topic: 'test',
        trialNumber: 1,
        sampleRateHz: 100,
        startTime: DateTime.utc(2026),
        durationMs: 2500,
        sampleCount: samples.length,
        markerCount: 0,
        recordedSides: const ['L', 'R'],
      );
      final source = InMemoryPreviewSource(meta: meta, samples: samples);
      final client = _FakeModelClient();
      final container = ProviderContainer(
        overrides: [trajectoryModelClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      await container
          .read(modelTrajectoryProvider(source).notifier)
          .generate(meta);

      final state = container.read(modelTrajectoryProvider(source));
      expect(state.error, isNull);
      expect(state.isRunning, isFalse);
      expect(state.result?.modelLabel, 'Fake M4');
      expect(state.preprocess?.modelStepCount, 50);
      expect(client.calls, 1);
      expect(client.input?.windows.first.first, hasLength(12));
    },
  );

  test('invalid recording fails before on-device model call', () async {
    final meta = SessionMeta(
      sessionId: 'abc',
      topic: 'test',
      trialNumber: 1,
      sampleRateHz: 100,
      startTime: DateTime.utc(2026),
      durationMs: 0,
      sampleCount: 0,
      markerCount: 0,
    );
    final source = InMemoryPreviewSource(meta: meta, samples: const []);
    final client = _FakeModelClient();
    final container = ProviderContainer(
      overrides: [trajectoryModelClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    await container
        .read(modelTrajectoryProvider(source).notifier)
        .generate(meta);

    expect(
      container.read(modelTrajectoryProvider(source)).error,
      contains('requires both left and right'),
    );
    expect(client.calls, 0);
  });
}
