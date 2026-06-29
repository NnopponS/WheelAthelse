import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/browse_page.dart';

SessionMeta _meta({String id = 'abc123', int trial = 1}) => SessionMeta(
      sessionId: id,
      topic: 'sprint_test',
      trialNumber: trial,
      athleteName: 'athlete_A',
      sampleRateHz: 100,
      startTime: DateTime.fromMillisecondsSinceEpoch(1000000),
      durationMs: 5000,
      sampleCount: 2,
      markerCount: 1,
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
    ];

void main() {
  late InMemoryStorageRepository storage;
  late ProviderContainer container;

  setUp(() async {
    storage = InMemoryStorageRepository();
    container = ProviderContainer(
      overrides: [
        storageRepositoryProvider.overrideWith((ref) => storage),
      ],
    );
    addTearDown(container.dispose);
    await storage.createTopic('sprint_test');
    await storage.saveSession('sprint_test', _meta(), _samples());
    await storage.saveSession(
      'sprint_test',
      _meta(id: 'def456'),
      _samples(),
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const BrowsePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('BrowsePage', () {
    testWidgets('shows topic list on initial load', (tester) async {
      await pumpPage(tester);
      expect(find.text('Browse'), findsOneWidget);
      expect(find.text('sprint_test'), findsWidgets);
    });

    testWidgets('tapping a topic navigates to trial list', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();

      expect(find.text('trial_01'), findsWidgets);
    });

    testWidgets('tapping a trial navigates to session list', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Two sessions should be visible.
      expect(find.text('abc123'), findsOneWidget);
      expect(find.text('def456'), findsOneWidget);
    });

    testWidgets('session list shows sample count + marker count',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('2 samples'), findsWidgets);
      // SessionListItem shows marker count as a badge.
      expect(find.byIcon(Icons.flag_rounded), findsNWidgets(2));
    });

    testWidgets('session list has share buttons', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.ios_share_rounded), findsNWidgets(2));
    });

    testWidgets('back button returns to topic list from trial list',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();

      // Should be on trial list now.
      expect(find.text('trial_01'), findsWidgets);

      // Tap the custom back button (IconButton with arrow_back icon).
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // Back on topic list.
      expect(find.text('sprint_test'), findsWidgets);
    });

    testWidgets('shows empty state when no topics', (tester) async {
      // Create a fresh container with empty storage.
      final emptyStorage = InMemoryStorageRepository();
      final emptyContainer = ProviderContainer(
        overrides: [
          storageRepositoryProvider.overrideWith((ref) => emptyStorage),
        ],
      );
      addTearDown(emptyContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: emptyContainer,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const BrowsePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No topics'), findsOneWidget);
    });
  });

  group('BrowsePage — editing', () {
    testWidgets('topic overflow menu offers rename + edit description',
        (tester) async {
      await pumpPage(tester);
      // Topic row has a more-vert overflow menu.
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Edit description'), findsOneWidget);
    });

    testWidgets('rename topic dialog renames the folder', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Rename topic'), findsOneWidget);
      // Enter a new name and save.
      await tester.enterText(find.byType(TextField), 'renamed_topic');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Old name gone, new name visible.
      expect(find.text('renamed_topic'), findsWidgets);
      expect(find.text('sprint_test'), findsNothing);
      // The storage reflects the rename.
      final topics = await storage.listTopics();
      expect(topics.map((t) => t.name).toList(), ['renamed_topic']);
    });

    testWidgets('edit description dialog updates the topic description',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit description'));
      await tester.pumpAndSettle();

      expect(find.text('Edit description'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'a sprint session');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final topics = await storage.listTopics();
      expect(topics.first.description, 'a sprint session');
    });

    testWidgets('session overflow menu offers edit notes / video',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Each session row has a more-vert overflow menu.
      expect(find.byIcon(Icons.more_vert_rounded), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Edit notes / video'), findsOneWidget);
    });

    testWidgets('edit session meta updates notes + videoFile', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit notes / video'));
      await tester.pumpAndSettle();

      // First dialog: notes.
      expect(find.text('Edit notes'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'updated notes');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Second dialog: video filename.
      expect(find.text('Video filename'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'cam_01.mp4');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final meta = await storage.readSessionMeta('sprint_test', 1, 'abc123');
      expect(meta, isNotNull);
      expect(meta!.notes, 'updated notes');
      expect(meta.videoFileName, 'cam_01.mp4');
    });
  });
}
