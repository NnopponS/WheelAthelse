import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/records/protocol_repository.dart';
import 'package:wheelathlete/records/protocol_template.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/experiment_tracker_providers.dart';
import 'package:wheelathlete/state/protocol_providers.dart';

void main() {
  SessionMeta makeMeta({
    required String topic,
    required int trial,
    required DateTime start,
    String? templateId,
  }) => SessionMeta(
    sessionId: '${topic}_${start.millisecondsSinceEpoch.toRadixString(16)}',
    topic: topic,
    trialNumber: trial,
    sampleRateHz: 100,
    startTime: start,
    durationMs: 1000,
    sampleCount: 100,
    markerCount: 0,
    protocolTemplateId: templateId,
  );

  ProtocolTemplate makeTemplate({
    required String id,
    required String name,
    required String topic,
    required int target,
  }) => ProtocolTemplate(
    id: id,
    name: name,
    topicName: topic,
    targetTrialCount: target,
    createdAt: DateTime(2026, 1, 1),
  );

  group('computeExperimentProgress', () {
    test('empty when no templates', () {
      final result = computeExperimentProgress([], []);
      expect(result, isEmpty);
    });

    test('template with no sessions has zero count and null date', () {
      final t = makeTemplate(
        id: 't1',
        name: 'Sprint',
        topic: 'sprint',
        target: 5,
      );
      final result = computeExperimentProgress([t], []);
      expect(result.length, 1);
      expect(result.first.template.id, 't1');
      expect(result.first.sessionCount, 0);
      expect(result.first.lastSessionDate, isNull);
      expect(result.first.progress, 0.0);
      expect(result.first.isComplete, isFalse);
    });

    test('counts sessions per template by protocolTemplateId', () {
      final t = makeTemplate(
        id: 't1',
        name: 'Sprint',
        topic: 'sprint',
        target: 5,
      );
      final sessions = [
        makeMeta(
          topic: 'sprint',
          trial: 1,
          start: DateTime(2026, 6, 1),
          templateId: 't1',
        ),
        makeMeta(
          topic: 'sprint',
          trial: 1,
          start: DateTime(2026, 6, 2),
          templateId: 't1',
        ),
        makeMeta(
          topic: 'other',
          trial: 1,
          start: DateTime(2026, 6, 3),
          templateId: 't2',
        ),
      ];
      final result = computeExperimentProgress([t], sessions);
      expect(result.first.sessionCount, 2);
    });

    test(
      'falls back to topicName matching when protocolTemplateId is null',
      () {
        final t = makeTemplate(
          id: 't1',
          name: 'Sprint',
          topic: 'sprint',
          target: 5,
        );
        final sessions = [
          makeMeta(topic: 'sprint', trial: 1, start: DateTime(2026, 6, 1)),
          makeMeta(topic: 'sprint', trial: 2, start: DateTime(2026, 6, 2)),
          makeMeta(topic: 'other', trial: 1, start: DateTime(2026, 6, 3)),
        ];
        final result = computeExperimentProgress([t], sessions);
        expect(result.first.sessionCount, 2);
      },
    );

    test('computes progress fraction clamped to 1.0', () {
      final t = makeTemplate(
        id: 't1',
        name: 'Sprint',
        topic: 'sprint',
        target: 5,
      );
      final sessions = [
        makeMeta(
          topic: 'sprint',
          trial: 1,
          start: DateTime(2026, 6, 1),
          templateId: 't1',
        ),
        makeMeta(
          topic: 'sprint',
          trial: 2,
          start: DateTime(2026, 6, 2),
          templateId: 't1',
        ),
        makeMeta(
          topic: 'sprint',
          trial: 3,
          start: DateTime(2026, 6, 3),
          templateId: 't1',
        ),
      ];
      final result = computeExperimentProgress([t], sessions);
      // 3/5 = 0.6
      expect(result.first.progress, closeTo(0.6, 1e-9));
      expect(result.first.isComplete, isFalse);
    });

    test('clamps progress to 1.0 when sessions exceed target', () {
      final t = makeTemplate(
        id: 't1',
        name: 'Sprint',
        topic: 'sprint',
        target: 2,
      );
      final sessions = [
        makeMeta(
          topic: 'sprint',
          trial: 1,
          start: DateTime(2026, 6, 1),
          templateId: 't1',
        ),
        makeMeta(
          topic: 'sprint',
          trial: 2,
          start: DateTime(2026, 6, 2),
          templateId: 't1',
        ),
        makeMeta(
          topic: 'sprint',
          trial: 3,
          start: DateTime(2026, 6, 3),
          templateId: 't1',
        ),
      ];
      final result = computeExperimentProgress([t], sessions);
      expect(result.first.progress, 1.0);
      expect(result.first.isComplete, isTrue);
    });

    test('lastSessionDate is the most recent session start', () {
      final t = makeTemplate(
        id: 't1',
        name: 'Sprint',
        topic: 'sprint',
        target: 5,
      );
      final sessions = [
        makeMeta(
          topic: 'sprint',
          trial: 1,
          start: DateTime(2026, 6, 3),
          templateId: 't1',
        ),
        makeMeta(
          topic: 'sprint',
          trial: 2,
          start: DateTime(2026, 6, 1),
          templateId: 't1',
        ),
        makeMeta(
          topic: 'sprint',
          trial: 3,
          start: DateTime(2026, 6, 2),
          templateId: 't1',
        ),
      ];
      final result = computeExperimentProgress([t], sessions);
      expect(result.first.lastSessionDate, DateTime(2026, 6, 3));
    });

    test('result is sorted by template name', () {
      final t1 = makeTemplate(id: 'a', name: 'Zebra', topic: 'z', target: 1);
      final t2 = makeTemplate(id: 'b', name: 'Alpha', topic: 'a', target: 1);
      final result = computeExperimentProgress([t1, t2], []);
      expect(result.map((p) => p.template.name).toList(), ['Alpha', 'Zebra']);
    });

    test('sessions with unknown template id are ignored', () {
      final t = makeTemplate(
        id: 't1',
        name: 'Sprint',
        topic: 'sprint',
        target: 5,
      );
      final sessions = [
        makeMeta(
          topic: 'sprint',
          trial: 1,
          start: DateTime(2026, 6, 1),
          templateId: 'unknown',
        ),
      ];
      final result = computeExperimentProgress([t], sessions);
      expect(result.first.sessionCount, 0);
    });
  });

  group('experimentProgressProvider', () {
    late InMemoryProtocolRepository protocolRepo;
    late InMemoryStorageRepository storageRepo;
    late ProviderContainer container;

    setUp(() {
      protocolRepo = InMemoryProtocolRepository();
      storageRepo = InMemoryStorageRepository();
      container = ProviderContainer(
        overrides: [
          protocolRepositoryProvider.overrideWith((ref) => protocolRepo),
          storageRepositoryProvider.overrideWith((ref) => storageRepo),
        ],
      );
      addTearDown(container.dispose);
    });

    test('loads empty when no templates', () async {
      final result = await container.read(experimentProgressProvider.future);
      expect(result, isEmpty);
    });

    test('counts sessions per template via provider', () async {
      final t = await protocolRepo.createTemplate(
        name: 'Sprint',
        topicName: 'sprint',
        targetTrialCount: 5,
      );
      await storageRepo.saveSession(
        'sprint',
        makeMeta(
          topic: 'sprint',
          trial: 1,
          start: DateTime(2026, 6, 1),
          templateId: t.id,
        ),
        const [],
      );
      await storageRepo.saveSession(
        'sprint',
        makeMeta(
          topic: 'sprint',
          trial: 2,
          start: DateTime(2026, 6, 2),
          templateId: t.id,
        ),
        const [],
      );
      final result = await container.read(experimentProgressProvider.future);
      expect(result.length, 1);
      expect(result.first.sessionCount, 2);
      expect(result.first.progress, closeTo(0.4, 1e-9));
    });

    test('falls back to topicName via provider', () async {
      await protocolRepo.createTemplate(
        name: 'Sprint',
        topicName: 'sprint',
        targetTrialCount: 5,
      );
      // Sessions with no protocolTemplateId — should match by topic.
      await storageRepo.saveSession(
        'sprint',
        makeMeta(topic: 'sprint', trial: 1, start: DateTime(2026, 6, 1)),
        const [],
      );
      final result = await container.read(experimentProgressProvider.future);
      expect(result.first.sessionCount, 1);
    });
  });
}
