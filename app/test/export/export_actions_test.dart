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
  Future<void> shareTrial({required String topic, required int trialNumber}) async {
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
        writeFile: (_, _) async {},
      );
      expect(written, isEmpty);
    });

    test('session level writes one CSV file', () async {
      final actions = ExportActions(ops, storage);
      final writtenPaths = <String>[];
      final writtenContent = <String>[];
      final written = await actions.saveToDevice(
        level: ExportLevel.session,
        topic: 'sprint',
        trialNumber: 1,
        sessionId: 'abc',
        pickDirectory: () async => '/picked/dir',
        writeFile: (path, content) async {
          writtenPaths.add(path);
          writtenContent.add(content);
        },
      );
      expect(written.length, 1);
      expect(writtenPaths, ['/picked/dir/session_abc.csv']);
      // Content is a valid CSV with the sample.
      expect(writtenContent.first, CsvExporter.toCsvString(_samples()));
    });

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
      expect(written.length, 2);
      expect(writtenPaths.toSet(), {
        '/picked/dir/session_abc.csv',
        '/picked/dir/session_def.csv',
      });
    });

    test('topic level writes one file per session across all trials',
        () async {
      final actions = ExportActions(ops, storage);
      final written = await actions.saveToDevice(
        level: ExportLevel.topic,
        topic: 'sprint',
        pickDirectory: () async => '/picked/dir',
        writeFile: (_,_) async {},
      );
      // 2 sessions in trial 1 + 1 session in trial 2.
      expect(written.length, 3);
    });
  });
}
