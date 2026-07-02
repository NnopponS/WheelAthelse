import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/records/protocol_repository.dart';
import 'package:wheelathlete/state/protocol_providers.dart';

void main() {
  late InMemoryProtocolRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = InMemoryProtocolRepository();
    container = ProviderContainer(
      overrides: [
        protocolRepositoryProvider.overrideWith((ref) => repo),
      ],
    );
    addTearDown(container.dispose);
  });

  group('protocolTemplatesProvider', () {
    test('loads empty list initially', () async {
      // `.future` on the provider returns a Future<T> that resolves with the
      // loaded value.
      final templates = await container.read(protocolTemplatesProvider.future);
      expect(templates, isEmpty);
    });

    test('loads templates from the repository', () async {
      await repo.createTemplate(
        name: 'Sprint',
        topicName: 'sprint',
        targetTrialCount: 5,
      );
      await repo.createTemplate(
        name: 'Balance',
        topicName: 'balance',
        targetTrialCount: 3,
      );
      final templates =
          await container.read(protocolTemplatesProvider.future);
      expect(templates.map((t) => t.name).toList(), ['Balance', 'Sprint']);
    });
  });

  group('protocolTemplateNotifierProvider', () {
    test('initial build loads templates', () async {
      await repo.createTemplate(
        name: 'Sprint',
        topicName: 'sprint',
        targetTrialCount: 5,
      );
      // Reading the notifier triggers build() which kicks off _load().
      container.read(protocolTemplateNotifierProvider.notifier);
      // Pump microtasks until the async load completes.
      await Future<void>.delayed(Duration.zero);
      final state = container.read(protocolTemplateNotifierProvider);
      expect(state.templates.length, 1);
      expect(state.templates.first.name, 'Sprint');
      expect(state.loading, false);
      expect(state.error, isNull);
    });

    test('createTemplate adds to the list and refreshes', () async {
      final notifier = container.read(protocolTemplateNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final created = await notifier.createTemplate(
        name: '20m Sprint',
        description: 'Max effort',
        topicName: 'sprint_20m',
        targetTrialCount: 5,
        sampleRateHz: 200,
      );
      expect(created.id, isNotEmpty);

      final state = container.read(protocolTemplateNotifierProvider);
      expect(state.templates.length, 1);
      expect(state.templates.first.id, created.id);
      expect(state.error, isNull);
    });

    test('updateTemplate updates the list', () async {
      final notifier = container.read(protocolTemplateNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final created = await notifier.createTemplate(
        name: 'Sprint',
        topicName: 'sprint',
        targetTrialCount: 5,
      );
      await notifier.updateTemplate(
        created.copyWith(name: '30m Sprint', targetTrialCount: 10),
      );

      final state = container.read(protocolTemplateNotifierProvider);
      expect(state.templates.first.name, '30m Sprint');
      expect(state.templates.first.targetTrialCount, 10);
    });

    test('deleteTemplate removes from the list', () async {
      final notifier = container.read(protocolTemplateNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final created = await notifier.createTemplate(
        name: 'Sprint',
        topicName: 'sprint',
        targetTrialCount: 5,
      );
      await notifier.deleteTemplate(created.id);

      final state = container.read(protocolTemplateNotifierProvider);
      expect(state.templates, isEmpty);
    });

    test('refresh reloads from repository', () async {
      final notifier = container.read(protocolTemplateNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      // Mutate the repo directly (bypassing the notifier).
      await repo.createTemplate(
        name: 'External',
        topicName: 'ext',
        targetTrialCount: 1,
      );
      // Notifier list is still empty.
      expect(
        container.read(protocolTemplateNotifierProvider).templates,
        isEmpty,
      );

      await notifier.refresh();
      final state = container.read(protocolTemplateNotifierProvider);
      expect(state.templates.length, 1);
      expect(state.templates.first.name, 'External');
    });
  });
}
