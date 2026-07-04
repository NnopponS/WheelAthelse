import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/ble/device_info.dart';
import 'package:wheelathlete/ble/wheel_id.dart';
import 'package:wheelathlete/records/protocol_repository.dart';
import 'package:wheelathlete/records/session_model.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/protocol_providers.dart';
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
  late InMemoryProtocolRepository protocolRepo;
  late ProviderContainer container;

  setUp(() async {
    storage = InMemoryStorageRepository();
    protocolRepo = InMemoryProtocolRepository();
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
        protocolRepositoryProvider.overrideWith((ref) => protocolRepo),
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
    testWidgets('shows stop button while recording (no MARK button)',
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
      // Mark Event was removed from the recording UI (Phase 3, D16).
      expect(find.text('MARK'), findsNothing);
      expect(find.byIcon(Icons.flag_rounded), findsNothing);
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

    // ── Protocol template picker (Phase 3, subtask #23) ────────────────────
    group('template picker', () {
      testWidgets('idle view shows Custom chip + template chips',
          (tester) async {
        await protocolRepo.createTemplate(
          name: 'Sprint Test',
          topicName: 'sprint_test',
          targetTrialCount: 5,
          sampleRateHz: 200,
        );
        await pumpPage(tester);

        // "Custom" chip is always present (default selected).
        expect(find.text('Custom'), findsOneWidget);
        // Template chip is rendered.
        expect(find.text('Sprint Test'), findsOneWidget);
      });

      testWidgets('Custom chip is selected by default and shows topic dropdown',
          (tester) async {
        await pumpPage(tester);
        // Custom is selected → topic dropdown ("Select topic" hint or the
        // seeded topic) is visible.
        expect(find.text('Custom'), findsOneWidget);
        expect(find.text('sprint_test'), findsWidgets);
        // Topic label is shown in Custom mode.
        expect(find.text('Topic'), findsOneWidget);
      });

      testWidgets('tapping a template chip selects it + fills topic + trial',
          (tester) async {
        await protocolRepo.createTemplate(
          name: 'Balance Test',
          topicName: 'balance_test',
          targetTrialCount: 3,
          sampleRateHz: 50,
        );
        await pumpPage(tester);

        // Tap the template chip.
        await tester.tap(find.text('Balance Test'));
        await tester.pumpAndSettle();

        // The template's topic was created + selected → trial info shows.
        expect(find.text('trial_01'), findsOneWidget);
        // Topic dropdown is hidden when a template is selected (no "Topic"
        // label from the dropdown section).
        expect(find.text('Select topic'), findsNothing);
        // Start button is enabled.
        expect(find.text('Start Recording'), findsOneWidget);
        // The topic folder was auto-created.
        final topics = await storage.listTopics();
        expect(topics.any((t) => t.name == 'balance_test'), isTrue);
      });

      testWidgets('tapping Custom after a template restores topic dropdown',
          (tester) async {
        await protocolRepo.createTemplate(
          name: 'Balance Test',
          topicName: 'balance_test',
          targetTrialCount: 3,
        );
        await pumpPage(tester);
        await tester.tap(find.text('Balance Test'));
        await tester.pumpAndSettle();
        // Template selected → no topic dropdown.
        expect(find.text('Select topic'), findsNothing);

        // Switch back to Custom.
        await tester.tap(find.text('Custom'));
        await tester.pumpAndSettle();
        // Topic dropdown is back.
        expect(find.text('Topic'), findsOneWidget);
      });

      // ── Quick re-record (Phase 3, subtask #24) ───────────────────────────
      group('quick re-record', () {
        Future<void> pumpStopped(
          WidgetTester tester, {
          SessionConfig config = const SessionConfig(
            topic: 'sprint_test',
            trialNumber: 1,
            sampleRateHz: 100,
          ),
        }) async {
          await pumpPage(tester);
          await tester.runAsync(() async {
            await container
                .read(recordingProvider.notifier)
                .startRecording(config);
          });
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => container.read(recordingProvider.notifier).stopRecording(),
          );
          await tester.pumpAndSettle();
        }

        testWidgets('stopped view shows Re-record button', (tester) async {
          await pumpStopped(tester);
          expect(find.text('Re-record'), findsOneWidget);
          // New Recording button is still present.
          expect(find.text('New Recording'), findsOneWidget);
          // Preview button (Phase 4, subtask #34) is also present.
          expect(find.text('Preview'), findsOneWidget);
        });

        testWidgets('tapping Preview opens the session preview page',
            (tester) async {
          await pumpStopped(tester);
          await tester.tap(find.text('Preview'));
          await tester.pumpAndSettle();

          // Preview page should be pushed — Summary card + chart titles appear.
          expect(find.text('Summary'), findsOneWidget);
          expect(find.text('Accelerometer (g)'), findsOneWidget);
        });

        testWidgets('tapping Re-record starts countdown with next trial number',
            (tester) async {
          await pumpStopped(tester);
          // After stopping trial 1, next trial number is 2. Tap Re-record and
          // drive the countdown to completion by injecting START_FIRED events.
          await tester.runAsync(() async {
            await tester.tap(find.text('Re-record'));
            // Wait for the async nextTrialNumber lookup + sync burst + countdown
            // start to complete.
            await Future<void>.delayed(const Duration(milliseconds: 300));
            // Inject START_FIRED from both wheels to trigger recording.
            ble.syncController('L1')?.add(_startFiredEvent(1000000));
            ble.syncController('R1')?.add(_startFiredEvent(1000500));
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pumpAndSettle();

          // Recording should now be active with the carried-over config.
          final recState = container.read(recordingProvider);
          expect(recState.status, RecordingStatus.recording);
          expect(recState.config?.trialNumber, 2);
          expect(recState.config?.topic, 'sprint_test');
          expect(recState.config?.sampleRateHz, 100);

          // Clean up: stop recording so timers/streams are torn down.
          await tester.runAsync(
            () => container.read(recordingProvider.notifier).stopRecording(),
          );
          await tester.pumpAndSettle();
        });

        testWidgets('Re-record carries over protocolTemplateId',
            (tester) async {
          final template = await protocolRepo.createTemplate(
            name: 'Sprint Test',
            topicName: 'sprint_test',
            targetTrialCount: 5,
            sampleRateHz: 200,
          );
          await pumpStopped(
            tester,
            config: SessionConfig(
              topic: 'sprint_test',
              trialNumber: 1,
              sampleRateHz: 200,
              protocolTemplateId: template.id,
            ),
          );

          await tester.runAsync(() async {
            await tester.tap(find.text('Re-record'));
            await Future<void>.delayed(const Duration(milliseconds: 300));
            ble.syncController('L1')?.add(_startFiredEvent(1000000));
            ble.syncController('R1')?.add(_startFiredEvent(1000500));
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await tester.pumpAndSettle();

          final recConfig = container.read(recordingProvider).config;
          expect(recConfig?.protocolTemplateId, template.id);
          expect(recConfig?.sampleRateHz, 200);
          expect(recConfig?.trialNumber, 2);

          await tester.runAsync(
            () => container.read(recordingProvider.notifier).stopRecording(),
          );
          await tester.pumpAndSettle();
        });

        testWidgets('Re-record is disabled when no wheels are connected',
            (tester) async {
          // Disconnect both wheels.
          await container
              .read(connectionManagerProvider.notifier)
              .disconnect(WheelSide.left);
          await container
              .read(connectionManagerProvider.notifier)
              .disconnect(WheelSide.right);
          await pumpStopped(tester);

          // The Re-record button (a PrimaryActionButton / FilledButton) should
          // be disabled — find it by label and check its onPressed is null.
          final button = tester.widget<FilledButton>(
            find.ancestor(
              of: find.text('Re-record'),
              matching: find.byType(FilledButton),
            ).first,
          );
          expect(button.onPressed, isNull);
        });
      });

      testWidgets('SessionConfig carries protocolTemplateId when template used',
          (tester) async {
        final template = await protocolRepo.createTemplate(
          name: 'Sprint Test',
          topicName: 'sprint_test',
          targetTrialCount: 5,
          sampleRateHz: 200,
        );
        await pumpPage(tester);

        // Tap the template chip then start recording.
        await tester.tap(find.text('Sprint Test'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await container.read(recordingProvider.notifier).startRecording(
                    SessionConfig(
                      topic: 'sprint_test',
                      trialNumber: 1,
                      sampleRateHz: 200,
                      protocolTemplateId: template.id,
                    ),
                  );
        });
        await tester.pumpAndSettle();

        final state = container.read(recordingProvider);
        expect(state.status, RecordingStatus.recording);
        expect(state.config?.protocolTemplateId, template.id);
        expect(state.config?.sampleRateHz, 200);
      });
    });
  });
}
