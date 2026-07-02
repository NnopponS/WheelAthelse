import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/imu_packet.dart';
import 'package:wheelathlete/export/export_actions.dart';
import 'package:wheelathlete/export/export_providers.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/browse_page.dart';

/// Fake [ExportActions] that records the last share call instead of invoking
/// share_plus / file_picker.
class _RecordingExportActions extends ExportActions {
  _RecordingExportActions() : super(_NoopOps(), InMemoryStorageRepository());

  ExportLevel? lastLevel;
  String? lastTopic;
  int? lastTrial;
  String? lastSession;

  @override
  Future<void> share({
    required ExportLevel level,
    required String topic,
    int? trialNumber,
    String? sessionId,
  }) async {
    lastLevel = level;
    lastTopic = topic;
    lastTrial = trialNumber;
    lastSession = sessionId;
  }

  @override
  Future<List<String>> saveToDevice({
    required ExportLevel level,
    required String topic,
    int? trialNumber,
    String? sessionId,
    required DirectoryPicker pickDirectory,
    required FileSink writeFile,
  }) async {
    lastLevel = level;
    lastTopic = topic;
    return const [];
  }
}

class _NoopOps implements ExportOperations {
  @override
  Future<void> shareSession({
    required String topic,
    required int trialNumber,
    required String sessionId,
  }) async {}

  @override
  Future<void> shareTrial({required String topic, required int trialNumber}) async {}

  @override
  Future<void> shareTopic({required String topic}) async {}
}

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

      // 2 session rows + 1 share-trial AppBar button.
      expect(find.byIcon(Icons.ios_share_rounded), findsNWidgets(3));
      // Save-to-device buttons too.
      expect(find.byIcon(Icons.save_alt_rounded), findsNWidgets(3));
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
      // Enter a new name and save — target the dialog's TextField (not the
      // search bar) by finding it as a descendant of the AlertDialog.
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'renamed_topic',
      );
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
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'a sprint session',
      );
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
      expect(find.text('Edit tags'), findsOneWidget);
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
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'updated notes',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Second dialog: video filename.
      expect(find.text('Video filename'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'cam_01.mp4',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final meta = await storage.readSessionMeta('sprint_test', 1, 'abc123');
      expect(meta, isNotNull);
      expect(meta!.notes, 'updated notes');
      expect(meta.videoFileName, 'cam_01.mp4');
    });

    testWidgets('edit tags opens TagEditorDialog and saves tags', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit tags'));
      await tester.pumpAndSettle();

      // Tag editor dialog is open — find the TextField inside the dialog
      // (not the search bar that lives on the session list underneath).
      final dialogTextField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(dialogTextField, findsOneWidget);
      await tester.enterText(dialogTextField, 'good-take');
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final meta = await storage.readSessionMeta('sprint_test', 1, 'abc123');
      expect(meta, isNotNull);
      expect(meta!.tags, contains('good-take'));
    });
  });

  group('BrowsePage — share/export wiring', () {
    testWidgets('tapping a session share button invokes ExportActions.share',
        (tester) async {
      final fakeActions = _RecordingExportActions();
      final container2 = ProviderContainer(
        overrides: [
          storageRepositoryProvider.overrideWith((ref) => storage),
          exportActionsProvider.overrideWith((ref) => fakeActions),
        ],
      );
      addTearDown(container2.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container2,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const BrowsePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Session-row share buttons have tooltip 'Share' (AppBar uses 'Share
      // trial'). Tap the first one — corresponds to the first session row.
      await tester.tap(find.byTooltip('Share').first);
      await tester.pumpAndSettle();

      expect(fakeActions.lastLevel, ExportLevel.session);
      expect(fakeActions.lastTopic, 'sprint_test');
      expect(fakeActions.lastTrial, 1);
      // First session in the list is abc123.
      expect(fakeActions.lastSession, 'abc123');
    });

    testWidgets('tapping the trial AppBar share button invokes trial share',
        (tester) async {
      final fakeActions = _RecordingExportActions();
      final container2 = ProviderContainer(
        overrides: [
          storageRepositoryProvider.overrideWith((ref) => storage),
          exportActionsProvider.overrideWith((ref) => fakeActions),
        ],
      );
      addTearDown(container2.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container2,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const BrowsePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Share trial'));
      await tester.pumpAndSettle();

      expect(fakeActions.lastLevel, ExportLevel.trial);
      expect(fakeActions.lastTopic, 'sprint_test');
      expect(fakeActions.lastTrial, 1);
    });

    testWidgets('tapping the topic AppBar share button invokes topic share',
        (tester) async {
      final fakeActions = _RecordingExportActions();
      final container2 = ProviderContainer(
        overrides: [
          storageRepositoryProvider.overrideWith((ref) => storage),
          exportActionsProvider.overrideWith((ref) => fakeActions),
        ],
      );
      addTearDown(container2.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container2,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const BrowsePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Share topic'));
      await tester.pumpAndSettle();

      expect(fakeActions.lastLevel, ExportLevel.topic);
      expect(fakeActions.lastTopic, 'sprint_test');
    });
  });

  group('BrowsePage — delete', () {
    testWidgets('topic overflow menu offers Delete', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets(
        'topic delete confirmation shows trial + session count and deletes on confirm',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirmation dialog shows the topic name + counts.
      expect(find.textContaining('Delete topic'), findsOneWidget);
      expect(find.textContaining('sprint_test'), findsWidgets);
      // 1 trial, 2 sessions.
      expect(find.textContaining('1 trial'), findsOneWidget);
      expect(find.textContaining('2 sessions'), findsOneWidget);

      // Confirm the delete.
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Topic gone from the list.
      expect(find.text('sprint_test'), findsNothing);
      final topics = await storage.listTopics();
      expect(topics, isEmpty);
    });

    testWidgets('topic delete confirmation cancels without deleting',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Topic still present.
      expect(find.text('sprint_test'), findsWidgets);
      final topics = await storage.listTopics();
      expect(topics.map((t) => t.name).toList(), ['sprint_test']);
    });

    testWidgets('trial list has a popup menu with Delete', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();

      // Trial row has a more-vert overflow menu.
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets(
        'trial delete confirmation shows session count and deletes on confirm',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirmation dialog shows trial name + session count.
      expect(find.textContaining('Delete trial'), findsOneWidget);
      expect(find.textContaining('trial_01'), findsWidgets);
      expect(find.textContaining('2 sessions'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Trial gone from the list.
      expect(find.text('trial_01'), findsNothing);
      expect(await storage.listTrials('sprint_test'), isEmpty);
    });

    testWidgets('session list has a delete button per row', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Two session rows → two delete icons.
      expect(find.byIcon(Icons.delete_outline_rounded), findsNWidgets(2));
    });

    testWidgets(
        'session delete confirmation deletes the session and refreshes the list',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();

      // Confirmation dialog shows session id.
      expect(find.textContaining('Delete session'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // One session gone — only one delete icon remains.
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      final sessions = await storage.listSessions('sprint_test', 1);
      expect(sessions.length, 1);
    });
  });

  group('BrowsePage — search/filter', () {
    /// Builds a [SessionMeta] with explicit tags + notes for search/filter tests.
    SessionMeta searchMeta({
      required String id,
      String notes = 'test session',
      List<String> tags = const [],
    }) =>
        SessionMeta(
          sessionId: id,
          topic: 'sprint_test',
          trialNumber: 1,
          athleteName: 'athlete_A',
          sampleRateHz: 100,
          startTime: DateTime.fromMillisecondsSinceEpoch(1000000),
          durationMs: 5000,
          sampleCount: 2,
          markerCount: 1,
          notes: notes,
          tags: tags,
        );

    /// Storage with two topics + three tagged sessions in one trial.
    Future<InMemoryStorageRepository> searchStorage() async {
      final s = InMemoryStorageRepository();
      await s.createTopic('sprint_test');
      await s.createTopic('balance_test');
      await s.saveSession(
        'sprint_test',
        searchMeta(id: 'aaa111', notes: 'good run', tags: ['good', 'morning']),
        _samples(),
      );
      await s.saveSession(
        'sprint_test',
        searchMeta(id: 'bbb222', notes: 'bad take', tags: ['bad-take']),
        _samples(),
      );
      await s.saveSession(
        'sprint_test',
        searchMeta(id: 'ccc333', notes: 'athlete A morning', tags: ['morning']),
        _samples(),
      );
      return s;
    }

    Future<void> pumpSearchPage(
      WidgetTester tester,
      ProviderContainer c,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const BrowsePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('topic search bar filters topics by name (case-insensitive)',
        (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      // Both topics visible initially.
      expect(find.text('sprint_test'), findsOneWidget);
      expect(find.text('balance_test'), findsOneWidget);

      // Type "SPRINT" (uppercase) — only sprint_test should match.
      await tester.enterText(find.byType(TextField), 'SPRINT');
      await tester.pumpAndSettle();
      expect(find.text('sprint_test'), findsOneWidget);
      expect(find.text('balance_test'), findsNothing);
    });

    testWidgets('empty search shows all topics', (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      // Enter then clear the search field.
      await tester.enterText(find.byType(TextField), 'sprint');
      await tester.pumpAndSettle();
      expect(find.text('balance_test'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('sprint_test'), findsOneWidget);
      expect(find.text('balance_test'), findsOneWidget);
    });

    testWidgets('topic search shows no-results state', (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      await tester.enterText(find.byType(TextField), 'zzz_nomatch');
      await tester.pumpAndSettle();
      expect(find.textContaining('No results'), findsOneWidget);
    });

    testWidgets('session search bar filters by session ID', (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      // Navigate to session list.
      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Three sessions visible initially.
      expect(find.text('aaa111'), findsOneWidget);
      expect(find.text('bbb222'), findsOneWidget);
      expect(find.text('ccc333'), findsOneWidget);

      // Search by session ID.
      await tester.enterText(find.byType(TextField), 'bbb');
      await tester.pumpAndSettle();
      expect(find.text('bbb222'), findsOneWidget);
      expect(find.text('aaa111'), findsNothing);
      expect(find.text('ccc333'), findsNothing);
    });

    testWidgets('session search filters by notes', (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Search by a word in the notes.
      await tester.enterText(find.byType(TextField), 'good run');
      await tester.pumpAndSettle();
      expect(find.text('aaa111'), findsOneWidget);
      expect(find.text('bbb222'), findsNothing);
      expect(find.text('ccc333'), findsNothing);
    });

    testWidgets('session search filters by tags', (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Search by a tag value — "bad-take" is a tag on bbb222.
      await tester.enterText(find.byType(TextField), 'bad-take');
      await tester.pumpAndSettle();
      expect(find.text('bbb222'), findsOneWidget);
      expect(find.text('aaa111'), findsNothing);
      expect(find.text('ccc333'), findsNothing);
    });

    testWidgets('tag filter chips appear with unique tags', (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Unique tags across the 3 sessions: good, morning, bad-take.
      expect(find.byType(FilterChip), findsNWidgets(3));
      expect(find.widgetWithText(FilterChip, 'good'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'morning'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'bad-take'), findsOneWidget);
    });

    testWidgets('tapping a tag chip filters sessions', (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Tap the "morning" chip — aaa111 + ccc333 have it.
      await tester.tap(find.widgetWithText(FilterChip, 'morning'));
      await tester.pumpAndSettle();
      expect(find.text('aaa111'), findsOneWidget);
      expect(find.text('ccc333'), findsOneWidget);
      expect(find.text('bbb222'), findsNothing);
    });

    testWidgets('tapping a tag chip again clears the filter', (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Select then deselect the "morning" chip.
      await tester.tap(find.widgetWithText(FilterChip, 'morning'));
      await tester.pumpAndSettle();
      expect(find.text('bbb222'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'morning'));
      await tester.pumpAndSettle();
      expect(find.text('aaa111'), findsOneWidget);
      expect(find.text('bbb222'), findsOneWidget);
      expect(find.text('ccc333'), findsOneWidget);
    });

    testWidgets('search + tag filter work together (AND logic)',
        (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      // Tag filter: morning → aaa111 + ccc333.
      await tester.tap(find.widgetWithText(FilterChip, 'morning'));
      await tester.pumpAndSettle();

      // Search: "athlete" → only ccc333 notes contain "athlete".
      await tester.enterText(find.byType(TextField), 'athlete');
      await tester.pumpAndSettle();

      expect(find.text('ccc333'), findsOneWidget);
      expect(find.text('aaa111'), findsNothing);
      expect(find.text('bbb222'), findsNothing);
    });

    testWidgets('session search shows no-results state', (tester) async {
      final s = await searchStorage();
      final c = ProviderContainer(
        overrides: [storageRepositoryProvider.overrideWith((ref) => s)],
      );
      addTearDown(c.dispose);
      await pumpSearchPage(tester, c);

      await tester.tap(find.text('sprint_test').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('trial_01').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz_nomatch');
      await tester.pumpAndSettle();
      expect(find.textContaining('No results'), findsOneWidget);
    });
  });
}
