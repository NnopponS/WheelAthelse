import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/recording_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/record_page.dart';

const _leftInfo = DeviceInfo(
  wheelId: WheelId.left,
  fwMajor: 1,
  fwMinor: 0,
  fwPatch: 0,
  accelRange: 0,
  gyroRange: 3,
  accelScale: 1 / 16384,
  gyroScale: 1 / 16.4,
);

const _rightInfo = DeviceInfo(
  wheelId: WheelId.right,
  fwMajor: 1,
  fwMinor: 0,
  fwPatch: 0,
  accelRange: 0,
  gyroRange: 3,
  accelScale: 1 / 16384,
  gyroScale: 1 / 16.4,
);

void main() {
  late FakeBleRepository ble;
  late InMemoryStorageRepository storage;
  late ProviderContainer container;

  setUp(() async {
    storage = InMemoryStorageRepository();
    ble = FakeBleRepository(
      devices: [
        const FakeDevice(id: 'L1', name: 'WheelAthlete-L', rssi: -42),
        const FakeDevice(id: 'R1', name: 'WheelAthlete-R', rssi: -55),
      ],
      infoFor: const {'L1': _leftInfo, 'R1': _rightInfo},
    );
    container = ProviderContainer(
      overrides: [
        bleRepositoryProvider.overrideWith((ref) => ble),
        storageRepositoryProvider.overrideWith((ref) => storage),
        rssiPollIntervalProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);
    // Connect both wheels.
    await container.read(connectionManagerProvider.notifier).connect('L1');
    await container.read(connectionManagerProvider.notifier).connect('R1');
    // Seed a topic.
    await storage.createTopic('sprint_test', description: 'Sprint tests');
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const RecordPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('RecordPage', () {
    testWidgets('shows topic picker + start button when idle', (tester) async {
      await pumpPage(tester);
      expect(find.text('Record'), findsOneWidget);
      expect(find.text('Start Recording'), findsOneWidget);
      expect(find.text('sprint_test'), findsOneWidget);
    });

    testWidgets('tapping start button starts recording', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Start Recording'));
      await tester.pumpAndSettle();

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.recording);
    });

    testWidgets('shows stop button + mark event button while recording',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Start Recording'));
      await tester.pumpAndSettle();

      expect(find.text('Stop Recording'), findsOneWidget);
      expect(find.text('MARK'), findsOneWidget);
    });

    testWidgets('tapping mark event increments marker count', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Start Recording'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('MARK'));
      await tester.pumpAndSettle();

      expect(find.text('1 marker'), findsOneWidget);
    });

    testWidgets('tapping stop button stops recording + shows saved message',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Start Recording'));
      await tester.pumpAndSettle();

      // Stop directly via the notifier. Use runAsync because stopRecording
      // awaits on async storage I/O which needs the real event loop.
      await tester.runAsync(
        () => container.read(recordingProvider.notifier).stopRecording(),
      );
      await tester.pumpAndSettle();

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.stopped);
      expect(state.savedSessionId, isNotNull);
      expect(find.text('Session saved'), findsOneWidget);
    });

    testWidgets('shows new topic button + dialog to create topic',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byIcon(Icons.create_new_folder_rounded));
      await tester.pumpAndSettle();

      expect(find.text('New Topic'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('shows sample count while recording', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Start Recording'));
      await tester.pumpAndSettle();

      // Initially 0 samples.
      expect(find.text('0 samples'), findsOneWidget);
    });

    testWidgets('shows trial number for selected topic', (tester) async {
      await pumpPage(tester);
      // The topic 'sprint_test' has no sessions yet → trial 01.
      expect(find.text('trial_01'), findsOneWidget);
    });

    testWidgets('new record button appears after stop', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Start Recording'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => container.read(recordingProvider.notifier).stopRecording(),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Recording'), findsOneWidget);
    });

    testWidgets('tapping new recording resets to idle', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Start Recording'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => container.read(recordingProvider.notifier).stopRecording(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Recording'));
      await tester.pumpAndSettle();

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.idle);
    });
  });
}
