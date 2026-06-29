import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/record_countdown_providers.dart';
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

/// Builds a START_FIRED Sync notify payload: [0x30][uint32 t_device_us].
Uint8List _startFiredEvent(int tDeviceUs) {
  final inner = ByteData(4)..setUint32(0, tDeviceUs, Endian.little);
  return Uint8List.fromList([0x30, ...inner.buffer.asUint8List()]);
}

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
        countdownDurationProvider.overrideWith(
          (ref) => const Duration(milliseconds: 200),
        ),
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

    testWidgets('shows trial number for selected topic', (tester) async {
      await pumpPage(tester);
      // The topic 'sprint_test' has no sessions yet → trial 01.
      expect(find.text('trial_01'), findsOneWidget);
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

    testWidgets('tapping start shows syncing then countdown', (tester) async {
      await pumpPage(tester);
      // Drive the countdown via the notifier inside runAsync so the real
      // timers (sync burst delays + display timer) run on the real event loop.
      await tester.runAsync(() async {
        const config = SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        );
        await container.read(recordCountdownProvider.notifier).start(config);
      });
      await tester.pump();

      // After start() completes, the counting view is shown.
      expect(find.text('Starting in'), findsOneWidget);
      // The countdown number is rendered (200ms duration → "1").
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Clean up the display timer so the test framework doesn't see pending
      // timers at teardown.
      await tester.runAsync(
        () => container.read(recordCountdownProvider.notifier).cancel(),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('countdown transitions to recording on START_FIRED',
        (tester) async {
      await pumpPage(tester);
      // Drive the countdown + START_FIRED inside runAsync (real event loop).
      await tester.runAsync(() async {
        const config = SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        );
        await container.read(recordCountdownProvider.notifier).start(config);
        // Inject START_FIRED from both wheels to trigger recording.
        ble.syncController('L1')?.add(_startFiredEvent(1000000));
        ble.syncController('R1')?.add(_startFiredEvent(1000500));
        // Allow the stream listeners + recording start to process.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.recording);
      expect(find.text('Stop Recording'), findsOneWidget);
    });

    testWidgets('cancel during countdown returns to idle', (tester) async {
      await pumpPage(tester);
      await tester.runAsync(() async {
        const config = SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        );
        await container.read(recordCountdownProvider.notifier).start(config);
      });
      await tester.pump();

      await tester.runAsync(
        () => container.read(recordCountdownProvider.notifier).cancel(),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(recordCountdownProvider).status,
        RecordCountdownStatus.idle,
      );
      // Back to the idle view with the Start button.
      expect(find.text('Start Recording'), findsOneWidget);
    });

    // The following tests exercise the recording-state UI by driving the
    // RecordingNotifier directly (bypassing the countdown) so the UI under
    // test is stable without real timers.
    testWidgets('shows stop button + mark event button while recording',
        (tester) async {
      await pumpPage(tester);
      await tester.runAsync(() async {
        const config = SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        );
        await container.read(recordingProvider.notifier).startRecording(config);
      });
      await tester.pumpAndSettle();

      expect(find.text('Stop Recording'), findsOneWidget);
      expect(find.text('MARK'), findsOneWidget);
    });

    testWidgets('tapping mark event increments marker count', (tester) async {
      await pumpPage(tester);
      await tester.runAsync(() async {
        const config = SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        );
        await container.read(recordingProvider.notifier).startRecording(config);
      });
      await tester.pumpAndSettle();

      await tester.tap(find.text('MARK'));
      await tester.pumpAndSettle();

      expect(find.text('1 marker'), findsOneWidget);
    });

    testWidgets('tapping stop button stops recording + shows saved message',
        (tester) async {
      await pumpPage(tester);
      await tester.runAsync(() async {
        const config = SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        );
        await container.read(recordingProvider.notifier).startRecording(config);
      });
      await tester.pumpAndSettle();

      await tester.runAsync(
        () => container.read(recordingProvider.notifier).stopRecording(),
      );
      await tester.pumpAndSettle();

      final state = container.read(recordingProvider);
      expect(state.status, RecordingStatus.stopped);
      expect(state.savedSessionId, isNotNull);
      expect(find.text('Session saved'), findsOneWidget);
    });

    testWidgets('shows sample count while recording', (tester) async {
      await pumpPage(tester);
      await tester.runAsync(() async {
        const config = SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        );
        await container.read(recordingProvider.notifier).startRecording(config);
      });
      await tester.pumpAndSettle();

      // Initially 0 samples.
      expect(find.text('0 samples'), findsOneWidget);
    });

    testWidgets('new record button appears after stop', (tester) async {
      await pumpPage(tester);
      await tester.runAsync(() async {
        const config = SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        );
        await container.read(recordingProvider.notifier).startRecording(config);
      });
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => container.read(recordingProvider.notifier).stopRecording(),
      );
      await tester.pumpAndSettle();

      expect(find.text('New Recording'), findsOneWidget);
    });

    testWidgets('tapping new recording resets to idle', (tester) async {
      await pumpPage(tester);
      await tester.runAsync(() async {
        const config = SessionConfig(
          topic: 'sprint_test',
          trialNumber: 1,
          sampleRateHz: 100,
        );
        await container.read(recordingProvider.notifier).startRecording(config);
      });
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
