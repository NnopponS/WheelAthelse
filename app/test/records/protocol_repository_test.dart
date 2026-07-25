import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/records/protocol_repository.dart';
import 'package:wheelathlete/records/protocol_template.dart';

void main() {
  late InMemoryProtocolRepository repo;

  setUp(() {
    repo = InMemoryProtocolRepository();
  });

  group('ProtocolRepository — list', () {
    test('listTemplates returns empty list initially', () async {
      expect(await repo.listTemplates(), isEmpty);
    });

    test('listTemplates returns sorted by name', () async {
      await repo.createTemplate(
        name: 'Zebra',
        topicName: 'z',
        targetTrialCount: 1,
      );
      await repo.createTemplate(
        name: 'Alpha',
        topicName: 'a',
        targetTrialCount: 1,
      );
      await repo.createTemplate(
        name: 'Mid',
        topicName: 'm',
        targetTrialCount: 1,
      );
      final templates = await repo.listTemplates();
      expect(templates.map((t) => t.name).toList(), ['Alpha', 'Mid', 'Zebra']);
    });
  });

  group('ProtocolRepository — create', () {
    test(
      'createTemplate returns template with generated id + fields',
      () async {
        final template = await repo.createTemplate(
          name: '20m Sprint Test',
          description: 'From standing start, 20m max effort',
          topicName: 'sprint_20m',
          targetTrialCount: 5,
          sampleRateHz: 200,
        );
        expect(template.id, isNotEmpty);
        expect(template.name, '20m Sprint Test');
        expect(template.description, 'From standing start, 20m max effort');
        expect(template.topicName, 'sprint_20m');
        expect(template.targetTrialCount, 5);
        expect(template.sampleRateHz, 200);
      },
    );

    test('createTemplate defaults sampleRateHz to 100', () async {
      final template = await repo.createTemplate(
        name: 'Test',
        topicName: 't',
        targetTrialCount: 1,
      );
      expect(template.sampleRateHz, 100);
    });

    test('createTemplate appears in listTemplates', () async {
      await repo.createTemplate(
        name: 'Sprint',
        topicName: 'sprint',
        targetTrialCount: 5,
      );
      final templates = await repo.listTemplates();
      expect(templates.length, 1);
      expect(templates.first.name, 'Sprint');
    });
  });

  group('ProtocolRepository — get', () {
    test('getTemplate returns the template by id', () async {
      final created = await repo.createTemplate(
        name: 'Sprint',
        topicName: 'sprint',
        targetTrialCount: 5,
      );
      final fetched = await repo.getTemplate(created.id);
      expect(fetched, isNotNull);
      expect(fetched!.id, created.id);
      expect(fetched.name, 'Sprint');
    });

    test('getTemplate returns null for unknown id', () async {
      expect(await repo.getTemplate('nonexistent'), isNull);
    });
  });

  group('ProtocolRepository — update', () {
    test('updateTemplate replaces fields', () async {
      final created = await repo.createTemplate(
        name: 'Sprint',
        topicName: 'sprint',
        targetTrialCount: 5,
      );
      await repo.updateTemplate(
        created.copyWith(name: '30m Sprint', targetTrialCount: 10),
      );
      final fetched = await repo.getTemplate(created.id);
      expect(fetched!.name, '30m Sprint');
      expect(fetched.targetTrialCount, 10);
      expect(fetched.topicName, 'sprint'); // unchanged
    });

    test('updateTemplate throws for unknown id', () async {
      final created = await repo.createTemplate(
        name: 'Temp',
        topicName: 't',
        targetTrialCount: 1,
      );
      // Build a template with an id that doesn't exist in the repo.
      final unknown = ProtocolTemplate(
        id: 'nonexistent',
        name: created.name,
        topicName: created.topicName,
        targetTrialCount: created.targetTrialCount,
        createdAt: created.createdAt,
      );
      expect(() => repo.updateTemplate(unknown), throwsStateError);
    });
  });

  group('ProtocolRepository — delete', () {
    test('deleteTemplate removes the template', () async {
      final created = await repo.createTemplate(
        name: 'Sprint',
        topicName: 'sprint',
        targetTrialCount: 5,
      );
      await repo.deleteTemplate(created.id);
      expect(await repo.getTemplate(created.id), isNull);
      expect(await repo.listTemplates(), isEmpty);
    });

    test('deleteTemplate is a no-op for unknown id', () async {
      // Should not throw.
      await repo.deleteTemplate('nonexistent');
    });
  });
}
