import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/theme/wheel_side.dart';

void main() {
  late InMemoryStorageRepository storage;

  setUp(() {
    storage = InMemoryStorageRepository();
  });

  group('StorageRepository — topics', () {
    test('listTopics returns empty list initially', () async {
      final topics = await storage.listTopics();
      expect(topics, isEmpty);
    });

    test('createTopic adds a topic and it appears in listTopics', () async {
      await storage.createTopic('sprint_test', description: 'Sprint tests');
      final topics = await storage.listTopics();
      expect(topics.length, 1);
      expect(topics.first.name, 'sprint_test');
      expect(topics.first.description, 'Sprint tests');
    });

    test('createTopic throws if topic already exists', () async {
      await storage.createTopic('sprint_test');
      expect(
        () => storage.createTopic('sprint_test'),
        throwsStateError,
      );
    });

    test('listTopics returns sorted by name', () async {
      await storage.createTopic('zebra');
      await storage.createTopic('alpha');
      await storage.createTopic('mid');
      final topics = await storage.listTopics();
      expect(topics.map((t) => t.name).toList(), ['alpha', 'mid', 'zebra']);
    });
  });

  group('StorageRepository — trials', () {
    test('nextTrialNumber returns 1 for a new topic', () async {
      await storage.createTopic('test');
      expect(await storage.nextTrialNumber('test'), 1);
    });

    test('nextTrialNumber increments after saving a session', () async {
      await storage.createTopic('test');
      final meta = _makeMeta(sessionId: 's1', trialNumber: 1);
      await storage.saveSession('test', meta, <BufferedSample>[]);
      expect(await storage.nextTrialNumber('test'), 2);
    });

    test('nextTrialNumber accounts for multiple saved sessions', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's2', trialNumber: 2), []);
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's3', trialNumber: 5), []);
      expect(await storage.nextTrialNumber('test'), 6);
    });
  });

  group('StorageRepository — save + read sessions', () {
    test('saveSession writes meta + samples, readSessionMeta reads it back',
        () async {
      await storage.createTopic('test');
      final meta = _makeMeta(sessionId: 'abc', trialNumber: 1);
      await storage.saveSession('test', meta, []);

      final read = await storage.readSessionMeta('test', 1, 'abc');
      expect(read, isNotNull);
      expect(read!.sessionId, 'abc');
      expect(read.topic, 'test');
      expect(read.trialNumber, 1);
    });

    test('readSessionMeta returns null for non-existent session', () async {
      await storage.createTopic('test');
      final read = await storage.readSessionMeta('test', 99, 'nope');
      expect(read, isNull);
    });

    test('listSessions returns all sessions for a topic/trial', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's2', trialNumber: 1), []);
      final sessions = await storage.listSessions('test', 1);
      expect(sessions.length, 2);
      expect(sessions.map((m) => m.sessionId).toSet(), {'s1', 's2'});
    });

    test('listSessions returns empty for a trial with no sessions', () async {
      await storage.createTopic('test');
      final sessions = await storage.listSessions('test', 1);
      expect(sessions, isEmpty);
    });
  });

  group('StorageRepository — delete', () {
    test('deleteSession removes the session', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.deleteSession('test', 1, 's1');
      final read = await storage.readSessionMeta('test', 1, 's1');
      expect(read, isNull);
    });

    test('deleteTopic removes the topic and all its sessions', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.deleteTopic('test');
      expect(await storage.listTopics(), isEmpty);
      expect(await storage.listSessions('test', 1), isEmpty);
    });

    test('deleteTrial removes the trial folder and all sessions inside',
        () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's2', trialNumber: 1), []);
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's3', trialNumber: 2), []);

      await storage.deleteTrial('test', 1);

      // Trial 1 sessions gone.
      expect(await storage.listSessions('test', 1), isEmpty);
      // Trial 1 no longer listed.
      expect(await storage.listTrials('test'), [2]);
      // Trial 2 sessions untouched.
      final remaining = await storage.listSessions('test', 2);
      expect(remaining.map((m) => m.sessionId).toList(), ['s3']);
    });

    test('deleteTrial throws if the trial does not exist', () async {
      await storage.createTopic('test');
      expect(
        () => storage.deleteTrial('test', 99),
        throwsStateError,
      );
    });

    test('deleteTrial throws if the topic does not exist', () async {
      expect(
        () => storage.deleteTrial('missing', 1),
        throwsStateError,
      );
    });
  });

  group('StorageRepository — rename topic', () {
    test('renameTopic moves the folder to the new name', () async {
      await storage.createTopic('old_name', description: 'desc');
      await storage.saveSession(
          'old_name', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.renameTopic('old_name', 'new_name');

      final topics = await storage.listTopics();
      expect(topics.map((t) => t.name).toList(), ['new_name']);
      expect(topics.first.description, 'desc');
      // Sessions move with the topic.
      final sessions = await storage.listSessions('new_name', 1);
      expect(sessions.length, 1);
      expect(sessions.first.sessionId, 's1');
      // Old name no longer exists.
      expect(await storage.listSessions('old_name', 1), isEmpty);
    });

    test('renameTopic throws if old name does not exist', () async {
      expect(
        () => storage.renameTopic('missing', 'whatever'),
        throwsStateError,
      );
    });

    test('renameTopic throws if new name already exists', () async {
      await storage.createTopic('a');
      await storage.createTopic('b');
      expect(() => storage.renameTopic('a', 'b'), throwsStateError);
    });

    test('renameTopic with same name is a no-op', () async {
      await storage.createTopic('same');
      await storage.renameTopic('same', 'same');
      final topics = await storage.listTopics();
      expect(topics.map((t) => t.name).toList(), ['same']);
    });
  });

  group('StorageRepository — update topic description', () {
    test('updateTopicDescription sets the description on an existing topic',
        () async {
      await storage.createTopic('test', description: 'old');
      await storage.updateTopicDescription('test', 'new desc');
      final topics = await storage.listTopics();
      expect(topics.first.description, 'new desc');
    });

    test('updateTopicDescription can clear the description', () async {
      await storage.createTopic('test', description: 'old');
      await storage.updateTopicDescription('test', null);
      final topics = await storage.listTopics();
      expect(topics.first.description, isNull);
    });

    test('updateTopicDescription throws if topic does not exist', () async {
      expect(
        () => storage.updateTopicDescription('missing', 'x'),
        throwsStateError,
      );
    });
  });

  group('StorageRepository — update session meta', () {
    test('updateSessionMeta updates notes + videoFile', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.updateSessionMeta(
        'test',
        1,
        's1',
        notes: 'new notes',
        videoFile: 'clip.mp4',
      );
      final meta = await storage.readSessionMeta('test', 1, 's1');
      expect(meta, isNotNull);
      expect(meta!.notes, 'new notes');
      expect(meta.videoFileName, 'clip.mp4');
    });

    test('updateSessionMeta preserves other fields', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.updateSessionMeta('test', 1, 's1', notes: 'only notes');
      final meta = await storage.readSessionMeta('test', 1, 's1');
      expect(meta, isNotNull);
      expect(meta!.notes, 'only notes');
      expect(meta.sampleRateHz, 100);
      expect(meta.durationMs, 1000);
    });

    test('updateSessionMeta throws if session does not exist', () async {
      await storage.createTopic('test');
      expect(
        () => storage.updateSessionMeta('test', 1, 'nope', notes: 'x'),
        throwsStateError,
      );
    });
  });

  group('StorageRepository — session tags', () {
    test('updateSessionTags sets tags on a session', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.updateSessionTags('test', 1, 's1', ['good', 'athlete-A']);
      final meta = await storage.readSessionMeta('test', 1, 's1');
      expect(meta, isNotNull);
      expect(meta!.tags, ['good', 'athlete-A']);
    });

    test('updateSessionTags overwrites existing tags', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.updateSessionTags('test', 1, 's1', ['a', 'b']);
      await storage.updateSessionTags('test', 1, 's1', ['c']);
      final meta = await storage.readSessionMeta('test', 1, 's1');
      expect(meta, isNotNull);
      expect(meta!.tags, ['c']);
    });

    test('updateSessionTags can clear tags with empty list', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.updateSessionTags('test', 1, 's1', ['a']);
      await storage.updateSessionTags('test', 1, 's1', []);
      final meta = await storage.readSessionMeta('test', 1, 's1');
      expect(meta, isNotNull);
      expect(meta!.tags, isEmpty);
    });

    test('updateSessionTags preserves other fields', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      await storage.updateSessionTags('test', 1, 's1', ['tag1']);
      final meta = await storage.readSessionMeta('test', 1, 's1');
      expect(meta, isNotNull);
      expect(meta!.sampleRateHz, 100);
      expect(meta.durationMs, 1000);
      expect(meta.sessionId, 's1');
    });

    test('updateSessionTags throws if session does not exist', () async {
      await storage.createTopic('test');
      expect(
        () => storage.updateSessionTags('test', 1, 'nope', ['x']),
        throwsStateError,
      );
    });
  });

  group('StorageRepository — listAllSessions', () {
    test('returns empty list when no sessions exist', () async {
      final all = await storage.listAllSessions();
      expect(all, isEmpty);
    });

    test('returns flat list across all topics and trials', () async {
      await storage.createTopic('topicA');
      await storage.createTopic('topicB');
      await storage.saveSession(
          'topicA', _makeMeta(sessionId: 'a1', trialNumber: 1), []);
      await storage.saveSession(
          'topicA', _makeMeta(sessionId: 'a2', trialNumber: 2), []);
      await storage.saveSession(
          'topicB', _makeMeta(sessionId: 'b1', trialNumber: 1), []);
      final all = await storage.listAllSessions();
      expect(all.length, 3);
      final ids = all.map((m) => m.sessionId).toSet();
      expect(ids, {'a1', 'a2', 'b1'});
    });

    test('returns sessions with their trialNumber intact', () async {
      await storage.createTopic('topicA');
      await storage.saveSession(
          'topicA', _makeMeta(sessionId: 'a1', trialNumber: 3), []);
      final all = await storage.listAllSessions();
      expect(all.length, 1);
      expect(all.first.trialNumber, 3);
    });

    test('does not include sessions from deleted topics', () async {
      await storage.createTopic('topicA');
      await storage.createTopic('topicB');
      await storage.saveSession(
          'topicA', _makeMeta(sessionId: 'a1', trialNumber: 1), []);
      await storage.saveSession(
          'topicB', _makeMeta(sessionId: 'b1', trialNumber: 1), []);
      await storage.deleteTopic('topicA');
      final all = await storage.listAllSessions();
      expect(all.length, 1);
      expect(all.first.sessionId, 'b1');
    });
  });

  group('StorageRepository — readSampleChunk', () {
    test('chunk from middle of session returns correct slice', () async {
      await storage.createTopic('test');
      final samples = List.generate(10, _makeSample);
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), samples);
      final chunk = await storage.readSampleChunk(
        'test',
        1,
        's1',
        offset: 3,
        count: 4,
      );
      expect(chunk.length, 4);
      // Samples 3..6 (seq values 3..6).
      expect(chunk.map((s) => s.reading.seq).toList(), [3, 4, 5, 6]);
    });

    test('chunk at end returns partial count when fewer samples remain',
        () async {
      await storage.createTopic('test');
      final samples = List.generate(10, _makeSample);
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), samples);
      final chunk = await storage.readSampleChunk(
        'test',
        1,
        's1',
        offset: 8,
        count: 10,
      );
      expect(chunk.length, 2);
      expect(chunk.map((s) => s.reading.seq).toList(), [8, 9]);
    });

    test('offset beyond sample count returns empty list', () async {
      await storage.createTopic('test');
      final samples = List.generate(10, _makeSample);
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), samples);
      final chunk = await storage.readSampleChunk(
        'test',
        1,
        's1',
        offset: 100,
        count: 5,
      );
      expect(chunk, isEmpty);
    });

    test('negative offset throws ArgumentError', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      expect(
        () => storage.readSampleChunk('test', 1, 's1', offset: -1, count: 5),
        throwsArgumentError,
      );
    });

    test('zero count throws ArgumentError', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      expect(
        () => storage.readSampleChunk('test', 1, 's1', offset: 0, count: 0),
        throwsArgumentError,
      );
    });

    test('negative count throws ArgumentError', () async {
      await storage.createTopic('test');
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), []);
      expect(
        () => storage.readSampleChunk('test', 1, 's1', offset: 0, count: -3),
        throwsArgumentError,
      );
    });

    test('full session as single chunk returns all samples', () async {
      await storage.createTopic('test');
      final samples = List.generate(10, _makeSample);
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), samples);
      final chunk = await storage.readSampleChunk(
        'test',
        1,
        's1',
        offset: 0,
        count: 100,
      );
      expect(chunk.length, 10);
      expect(chunk.map((s) => s.reading.seq).toList(),
          List.generate(10, (i) => i));
    });

    test('chunk from session that does not exist returns empty list',
        () async {
      await storage.createTopic('test');
      final chunk = await storage.readSampleChunk(
        'test',
        1,
        'nope',
        offset: 0,
        count: 5,
      );
      expect(chunk, isEmpty);
    });

    test('chunk from offset zero returns from the start', () async {
      await storage.createTopic('test');
      final samples = List.generate(5, _makeSample);
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), samples);
      final chunk = await storage.readSampleChunk(
        'test',
        1,
        's1',
        offset: 0,
        count: 3,
      );
      expect(chunk.length, 3);
      expect(chunk.map((s) => s.reading.seq).toList(), [0, 1, 2]);
    });
  });

  group('StorageRepository — real file CSV round-trip', () {
    late Directory tempDir;
    late PathProviderStorageRepository storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wa_storage_test_');
      storage = PathProviderStorageRepository(rootDir: tempDir);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saveSession then readSamples round-trips mixed L/R samples through '
        'the real CSV file (regression: the in-memory fake bypasses CSV '
        'serialization, so a writer/reader schema mismatch would go '
        'undetected)', () async {
      await storage.createTopic('test');
      final samples = [
        const BufferedSample(
          reading: ImuReading(
              seq: 0, tDeviceUs: 0, ax: 1, ay: 2, az: 3, gx: 4, gy: 5, gz: 6),
          wheel: WheelSide.left,
          timestampAppMs: 100,
          timestampSyncedMs: 0.0,
          marker: false,
        ),
        const BufferedSample(
          reading: ImuReading(
              seq: 1, tDeviceUs: 1000, ax: 7, ay: 8, az: 9, gx: 10, gy: 11, gz: 12),
          wheel: WheelSide.left,
          timestampAppMs: 110,
          timestampSyncedMs: 10.0,
          marker: true,
        ),
        const BufferedSample(
          reading: ImuReading(
              seq: 0, tDeviceUs: 0, ax: 13, ay: 14, az: 15, gx: 16, gy: 17, gz: 18),
          wheel: WheelSide.right,
          timestampAppMs: 105,
          timestampSyncedMs: 5.0,
          marker: false,
        ),
      ];
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), samples);

      final read = await storage.readSamples('test', 1, 's1');
      expect(read.length, 3);
      // Chronologically merged: L@0, R@5, L@10.
      expect(read.map((s) => s.timestampSyncedMs).toList(), [0.0, 5.0, 10.0]);
      expect(read.map((s) => s.wheel).toList(),
          [WheelSide.left, WheelSide.right, WheelSide.left]);
      // IMU values survive the round-trip.
      expect(read[0].reading.ax, 1);
      expect(read[2].reading.ax, 7);
      expect(read[2].marker, isTrue);
    });

    test('readSampleChunk on a real file returns chronological slices '
        '(offset N = Nth sample in the merged timeline, not Nth data line '
        'in file order)', () async {
      await storage.createTopic('test');
      // Interleaved L/R so the merged order differs from file order (file
      // stores all L then all R).
      final samples = [
        const BufferedSample(
          reading: ImuReading(
              seq: 0, tDeviceUs: 0, ax: 0, ay: 0, az: 0, gx: 0, gy: 0, gz: 0),
          wheel: WheelSide.left,
          timestampAppMs: 0,
          timestampSyncedMs: 0.0,
        ),
        const BufferedSample(
          reading: ImuReading(
              seq: 0, tDeviceUs: 0, ax: 1, ay: 0, az: 0, gx: 0, gy: 0, gz: 0),
          wheel: WheelSide.right,
          timestampAppMs: 5,
          timestampSyncedMs: 5.0,
        ),
        const BufferedSample(
          reading: ImuReading(
              seq: 1, tDeviceUs: 1000, ax: 2, ay: 0, az: 0, gx: 0, gy: 0, gz: 0),
          wheel: WheelSide.left,
          timestampAppMs: 10,
          timestampSyncedMs: 10.0,
        ),
        const BufferedSample(
          reading: ImuReading(
              seq: 1, tDeviceUs: 1000, ax: 3, ay: 0, az: 0, gx: 0, gy: 0, gz: 0),
          wheel: WheelSide.right,
          timestampAppMs: 15,
          timestampSyncedMs: 15.0,
        ),
      ];
      await storage.saveSession(
          'test', _makeMeta(sessionId: 's1', trialNumber: 1), samples);

      // offset 1, count 2 → merged timeline positions 1,2 = R@5, L@10.
      final chunk = await storage.readSampleChunk(
        'test', 1, 's1',
        offset: 1, count: 2,
      );
      expect(chunk.length, 2);
      expect(chunk.map((s) => s.timestampSyncedMs).toList(), [5.0, 10.0]);
      expect(chunk.map((s) => s.wheel).toList(),
          [WheelSide.right, WheelSide.left]);
    });
  });
}

SessionMeta _makeMeta({
  required String sessionId,
  required int trialNumber,
}) =>
    SessionMeta(
      sessionId: sessionId,
      topic: 'test',
      trialNumber: trialNumber,
      sampleRateHz: 100,
      startTime: DateTime.utc(2026, 6, 29),
      durationMs: 1000,
      sampleCount: 100,
      markerCount: 0,
    );

BufferedSample _makeSample(int i) => BufferedSample(
      reading: ImuReading(
        seq: i,
        tDeviceUs: i * 1000,
        ax: i.toDouble(),
        ay: 0,
        az: 0,
        gx: 0,
        gy: 0,
        gz: 0,
      ),
      wheel: WheelSide.left,
      timestampAppMs: i * 10,
      timestampSyncedMs: i * 10.0,
      marker: false,
    );
