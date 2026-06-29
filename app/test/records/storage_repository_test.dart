import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';

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
