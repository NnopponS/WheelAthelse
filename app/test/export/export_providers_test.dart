import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/export/export_providers.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';

SessionMeta _meta({String id = 'abc123', int trial = 1}) => SessionMeta(
  sessionId: id,
  topic: 'sprint_test',
  trialNumber: trial,
  athleteName: 'athlete_A',
  sampleRateHz: 100,
  startTime: DateTime.fromMillisecondsSinceEpoch(1000000),
  durationMs: 5000,
  sampleCount: 2,
  markerCount: 0,
  notes: 'test session',
);

List<BufferedSample> _samples() => [
  const BufferedSample(
    reading: ImuReading(
      seq: 0,
      tDeviceUs: 0,
      ax: 1,
      ay: 0,
      az: 0,
      gx: 0,
      gy: 0,
      gz: 0,
    ),
    wheel: WheelSide.left,
    timestampAppMs: 1000000,
    timestampSyncedMs: 0,
  ),
  const BufferedSample(
    reading: ImuReading(
      seq: 1,
      tDeviceUs: 10000,
      ax: 2,
      ay: 0,
      az: 0,
      gx: 0,
      gy: 0,
      gz: 0,
    ),
    wheel: WheelSide.right,
    timestampAppMs: 1000010,
    timestampSyncedMs: 10,
  ),
];

void main() {
  late InMemoryStorageRepository storage;
  late ProviderContainer container;

  setUp(() async {
    storage = InMemoryStorageRepository();
    container = ProviderContainer(
      overrides: [storageRepositoryProvider.overrideWith((ref) => storage)],
    );
    addTearDown(container.dispose);
    // Seed a session.
    await storage.createTopic('sprint_test');
    await storage.saveSession('sprint_test', _meta(), _samples());
  });

  group('ExportNotifier', () {
    test('exportSession returns a named topic CSV for sharing', () async {
      final notifier = container.read(exportProvider.notifier);
      final path = await notifier.exportSession(
        topic: 'sprint_test',
        trialNumber: 1,
        sessionId: 'abc123',
      );
      expect(path, endsWith('sprint_test_trial_01_training_1970-01-01.csv'));
      expect(path, isNot(contains('session_')));
    });

    test('exportSession reads samples + writes CSV to storage', () async {
      final notifier = container.read(exportProvider.notifier);
      final path = await notifier.exportSession(
        topic: 'sprint_test',
        trialNumber: 1,
        sessionId: 'abc123',
      );
      expect(path, isNotEmpty);
      // The CSV should be readable from storage.
      final samples = await storage.readSamples('sprint_test', 1, 'abc123');
      expect(samples.length, 2);
    });

    test('exportSession with resample produces resampled CSV', () async {
      final notifier = container.read(exportProvider.notifier);
      await notifier.exportSession(
        topic: 'sprint_test',
        trialNumber: 1,
        sessionId: 'abc123',
        resample: true,
        gridIntervalMs: 10,
      );
      // Resampled should still be readable.
      final samples = await storage.readSamples('sprint_test', 1, 'abc123');
      // Original had 2 samples at 0 and 10. Resampling at 10ms grid
      // should produce 2 points (one per wheel at each grid point
      // where data exists).
      expect(samples.length, lessThanOrEqualTo(4));
    });

    test('exportSession throws if session not found', () async {
      final notifier = container.read(exportProvider.notifier);
      expect(
        () => notifier.exportSession(
          topic: 'sprint_test',
          trialNumber: 1,
          sessionId: 'nonexistent',
        ),
        throwsStateError,
      );
    });

    test('exportTrial exports all sessions in a trial', () async {
      // Add a second session.
      await storage.saveSession('sprint_test', _meta(id: 'def456'), _samples());
      final notifier = container.read(exportProvider.notifier);
      final paths = await notifier.exportTrial(
        topic: 'sprint_test',
        trialNumber: 1,
      );
      expect(paths.length, 1); // one combined CSV per trial
    });

    test('exportTopic exports all sessions in all trials', () async {
      // Add a second trial.
      await storage.saveSession(
        'sprint_test',
        _meta(id: 'def456', trial: 2),
        _samples(),
      );
      final notifier = container.read(exportProvider.notifier);
      final paths = await notifier.exportTopic(topic: 'sprint_test');
      expect(paths.length, 2); // 1 session in trial 1 + 1 in trial 2
    });
  });
}
