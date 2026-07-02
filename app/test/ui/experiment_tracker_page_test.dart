import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/records/protocol_repository.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/protocol_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/experiment_tracker_page.dart';
import 'package:wheelathlete/widgets/protocol_template_card.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  Future<void> pumpTracker(
    WidgetTester tester, {
    required InMemoryProtocolRepository protocolRepo,
    required InMemoryStorageRepository storageRepo,
    required ValueChanged<String> onOpenTopic,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          protocolRepositoryProvider.overrideWith((ref) => protocolRepo),
          storageRepositoryProvider.overrideWith((ref) => storageRepo),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: ExperimentTrackerPage(onOpenTopic: onOpenTopic),
        ),
      ),
    );
    // Let the FutureProvider resolve.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  SessionMeta makeMeta({
    required String topic,
    required int trial,
    required DateTime start,
    String? templateId,
  }) =>
      SessionMeta(
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

  testWidgets('shows empty state when no templates', (tester) async {
    await pumpTracker(
      tester,
      protocolRepo: InMemoryProtocolRepository(),
      storageRepo: InMemoryStorageRepository(),
      onOpenTopic: (_) {},
    );
    expect(
      find.text('Create a protocol template to start tracking experiments'),
      findsOneWidget,
    );
  });

  testWidgets('shows cards when templates exist', (tester) async {
    final protocolRepo = InMemoryProtocolRepository();
    final storageRepo = InMemoryStorageRepository();
    final t = await protocolRepo.createTemplate(
      name: 'Sprint',
      description: 'Max effort',
      topicName: 'sprint',
      targetTrialCount: 5,
    );
    await storageRepo.saveSession(
      'sprint',
      makeMeta(
          topic: 'sprint',
          trial: 1,
          start: DateTime(2026, 6, 1),
          templateId: t.id),
      const [],
    );
    await pumpTracker(
      tester,
      protocolRepo: protocolRepo,
      storageRepo: storageRepo,
      onOpenTopic: (_) {},
    );
    expect(find.byType(ProtocolTemplateCard), findsOneWidget);
    expect(find.text('Sprint'), findsOneWidget);
    expect(find.text('1 / 5 trials'), findsOneWidget);
  });

  testWidgets('tapping a card calls onOpenTopic with the topic name',
      (tester) async {
    final protocolRepo = InMemoryProtocolRepository();
    final storageRepo = InMemoryStorageRepository();
    await protocolRepo.createTemplate(
      name: 'Sprint',
      topicName: 'sprint_20m',
      targetTrialCount: 5,
    );
    String? opened;
    await pumpTracker(
      tester,
      protocolRepo: protocolRepo,
      storageRepo: storageRepo,
      onOpenTopic: (topic) => opened = topic,
    );
    await tester.tap(find.byType(ProtocolTemplateCard));
    await tester.pump();
    expect(opened, 'sprint_20m');
  });

  testWidgets('New Template FAB opens create dialog', (tester) async {
    final protocolRepo = InMemoryProtocolRepository();
    final storageRepo = InMemoryStorageRepository();
    await pumpTracker(
      tester,
      protocolRepo: protocolRepo,
      storageRepo: storageRepo,
      onOpenTopic: (_) {},
    );
    await tester.tap(find.text('New Template'));
    await tester.pumpAndSettle();
    expect(find.text('New Protocol Template'), findsOneWidget);
    expect(find.text('Name *'), findsOneWidget);
    expect(find.text('Topic name *'), findsOneWidget);
  });

  testWidgets('create dialog saves a template and refreshes the list',
      (tester) async {
    final protocolRepo = InMemoryProtocolRepository();
    final storageRepo = InMemoryStorageRepository();
    await pumpTracker(
      tester,
      protocolRepo: protocolRepo,
      storageRepo: storageRepo,
      onOpenTopic: (_) {},
    );
    await tester.tap(find.text('New Template'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Name *'), 'Balance');
    await tester.enterText(
        find.widgetWithText(TextField, 'Topic name *'), 'balance');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // After saving, the dialog closes and the new card appears.
    expect(find.text('New Protocol Template'), findsNothing);
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text('0 / 5 trials'), findsOneWidget);
  });
}
