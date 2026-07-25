import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/export/csv_exporter.dart';
import 'package:wheelathlete/export/export_actions.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/theme/theme.dart';

/// Records which share method was invoked + with what args.
class _FakeExportOperations implements ExportOperations {
  String? lastShare;
  String? lastTopic;
  int? lastTrial;
  String? lastSession;

  @override
  Future<void> shareSession({
    required String topic,
    required int trialNumber,
    required String sessionId,
  }) async {
    lastShare = 'session';
    lastTopic = topic;
    lastTrial = trialNumber;
    lastSession = sessionId;
  }

  @override
  Future<void> shareTrial({
    required String topic,
    required int trialNumber,
  }) async {
    lastShare = 'trial';
    lastTopic = topic;
    lastTrial = trialNumber;
  }

  @override
  Future<void> shareTopic({required String topic}) async {
    lastShare = 'topic';
    lastTopic = topic;
  }
}

SessionMeta _meta({String id = 'abc', int trial = 1}) => SessionMeta(
  sessionId: id,
  topic: 'sprint',
  trialNumber: trial,
  sampleRateHz: 100,
  startTime: DateTime.utc(2026, 6, 29),
  durationMs: 1000,
  sampleCount: 1,
  markerCount: 0,
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
    timestampAppMs: 0,
    timestampSyncedMs: 0,
  ),
];

void main() {
  late InMemoryStorageRepository storage;
  late _FakeExportOperations ops;

  setUp(() async {
    storage = InMemoryStorageRepository();
    ops = _FakeExportOperations();
    await storage.createTopic('sprint');
    await storage.saveSession('sprint', _meta(), _samples());
    await storage.saveSession('sprint', _meta(id: 'def'), _samples());
    await storage.saveSession('sprint', _meta(id: 'ghi', trial: 2), _samples());
  });

  group('ExportActions.share dispatch', () {
    test('session level calls shareSession', () async {
      final actions = ExportActions(ops, storage);
      await actions.share(
        level: ExportLevel.session,
        topic: 'sprint',
        trialNumber: 1,
        sessionId: 'abc',
      );
      expect(ops.lastShare, 'session');
      expect(ops.lastTopic, 'sprint');
      expect(ops.lastTrial, 1);
      expect(ops.lastSession, 'abc');
    });

    test('trial level calls shareTrial', () async {
      final actions = ExportActions(ops, storage);
      await actions.share(
        level: ExportLevel.trial,
        topic: 'sprint',
        trialNumber: 1,
      );
      expect(ops.lastShare, 'trial');
      expect(ops.lastTrial, 1);
    });

    test('topic level calls shareTopic', () async {
      final actions = ExportActions(ops, storage);
      await actions.share(level: ExportLevel.topic, topic: 'sprint');
      expect(ops.lastShare, 'topic');
      expect(ops.lastTopic, 'sprint');
    });
  });

  group('ExportActions.saveToDevice', () {
    test('null directory returns empty list (user cancelled)', () async {
      final actions = ExportActions(ops, storage);
      final written = await actions.saveToDevice(
        level: ExportLevel.session,
        topic: 'sprint',
        trialNumber: 1,
        sessionId: 'abc',
        pickDirectory: () async => null,
        writeFile: (path, bytes) async {},
      );
      expect(written, isEmpty);
    });

    test(
      'session level writes raw L/R, aligned training, and metadata',
      () async {
        final actions = ExportActions(ops, storage);
        final writtenPaths = <String>[];
        final writtenBytes = <List<int>>[];
        final written = await actions.saveToDevice(
          level: ExportLevel.session,
          topic: 'sprint',
          trialNumber: 1,
          sessionId: 'abc',
          pickDirectory: () async => '/picked/dir',
          writeFile: (path, bytes) async {
            writtenPaths.add(path);
            writtenBytes.add(bytes);
          },
        );
        expect(written.length, 4);
        expect(
          writtenPaths,
          containsAll([
            '/picked/dir/sprint_trial_01_2026-06-29_left_raw.csv',
            '/picked/dir/sprint_trial_01_2026-06-29_right_raw.csv',
            '/picked/dir/sprint_trial_01_2026-06-29_training.csv',
            '/picked/dir/sprint_trial_01_2026-06-29.metadata.json',
          ]),
        );
        expect(
          writtenBytes.map(String.fromCharCodes).join('\n'),
          allOf(
            contains(CsvExporter.rawHeader),
            contains(CsvExporter.trainingHeader),
          ),
        );
      },
    );

    test('trial level writes one file per session in the trial', () async {
      final actions = ExportActions(ops, storage);
      final writtenPaths = <String>[];
      final written = await actions.saveToDevice(
        level: ExportLevel.trial,
        topic: 'sprint',
        trialNumber: 1,
        pickDirectory: () async => '/picked/dir',
        writeFile: (path, _) async {
          writtenPaths.add(path);
        },
      );
      expect(written.length, 4);
      expect(
        writtenPaths,
        contains('/picked/dir/sprint_trial_01_2026-06-29_training.csv'),
      );
    });

    test('topic level writes one file per session across all trials', () async {
      final actions = ExportActions(ops, storage);
      final written = await actions.saveToDevice(
        level: ExportLevel.topic,
        topic: 'sprint',
        pickDirectory: () async => '/picked/dir',
        writeFile: (path, bytes) async {},
      );
      expect(written.length, 8);
    });
  });

  test(
    'export all writes a ZIP with trial data, metadata, and manifest',
    () async {
      String? path;
      List<int>? bytes;
      final result = await ExportActions(ops, storage).exportAllZip(
        pickDirectory: () async => '/picked/dir',
        writeFile: (p, b) async {
          path = p;
          bytes = b;
        },
      );
      expect(result, path);
      expect(path, endsWith('.zip'));
      final archive = ZipDecoder().decodeBytes(bytes!);
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, contains('manifest.json'));
      expect(names, contains('sprint/trial_01/left_raw.csv'));
      expect(names, contains('sprint/trial_01/right_raw.csv'));
      expect(names, contains('sprint/trial_01/training.csv'));
      expect(names, contains('sprint/trial_01/metadata.json'));
    },
  );

  test(
    'topic export creates one atomic named folder with trial files',
    () async {
      final writes = <String, List<int>>{};
      String? renamedFrom;
      String? renamedTo;
      final result = await ExportActions(ops, storage).exportTopicFolder(
        topic: 'sprint',
        pickDirectory: () async => '/picked',
        writeFile: (path, bytes) async => writes[path] = bytes,
        createDirectory: (_) async {},
        renameDirectory: (from, to) async {
          renamedFrom = from;
          renamedTo = to;
        },
        removeDirectory: (_) async {},
      );
      expect(result, isA<TopicExportSuccess>());
      expect(renamedFrom, contains('/picked/sprint.tmp_'));
      expect(renamedTo, '/picked/sprint');
      expect(
        writes.keys.any(
          (path) => path.endsWith('sprint_trial_01_2026-06-29_training.csv'),
        ),
        isTrue,
      );
      expect(writes.keys.any((path) => path.endsWith('manifest.json')), isTrue);
    },
  );
}
