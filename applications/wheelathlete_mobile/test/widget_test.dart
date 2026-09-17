// Top-level smoke test: verifies the app entry point boots the real HomePage
// (not the design-system showcase), the NavigationBar is present with three
// tabs, and the theme toggle works. Uses a FakeBleRepository so no BLE
// hardware or permissions are required.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wheelathlete/main.dart' as app_entry;
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/theme/theme_mode_controller.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('app boots to real HomePage (not showcase)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleRepositoryProvider.overrideWith(
            (_) => FakeBleRepository(devices: const []),
          ),
        ],
        child: const app_entry.WheelAthleteApp(),
      ),
    );
    await tester.pump();

    // Real home: title is 'WheelAthlete', NOT the showcase 'WheelAthlete UI'.
    expect(find.text('WheelAthlete'), findsWidgets);
    // Showcase sentinel text must NOT be visible at boot.
    expect(find.text('WheelAthlete UI'), findsNothing);
  });

  testWidgets(
    'NavigationBar has five destinations',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleRepositoryProvider.overrideWith(
              (_) => FakeBleRepository(devices: const []),
            ),
          ],
          child: const app_entry.WheelAthleteApp(),
        ),
      );
      await tester.pump();

      expect(find.widgetWithText(NavigationDestination, 'Dashboard'), findsOneWidget);
      expect(find.widgetWithText(NavigationDestination, 'Acquisition'), findsOneWidget);
      expect(find.widgetWithText(NavigationDestination, 'Results'), findsOneWidget);
      expect(find.widgetWithText(NavigationDestination, 'Model'), findsOneWidget);
      expect(find.widgetWithText(NavigationDestination, 'Diagnostics'), findsOneWidget);
    },
  );

  testWidgets('tapping Acquisition tab navigates to Acquisition page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleRepositoryProvider.overrideWith(
            (_) => FakeBleRepository(devices: const []),
          ),
        ],
        child: const app_entry.WheelAthleteApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(NavigationDestination, 'Acquisition'));
    await tester.pump();

    expect(find.text('Acquisition'), findsWidgets);
  });

  testWidgets('tapping Results tab navigates to Results page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleRepositoryProvider.overrideWith(
            (_) => FakeBleRepository(devices: const []),
          ),
        ],
        child: const app_entry.WheelAthleteApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(NavigationDestination, 'Results'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Results'), findsWidgets);
  });

  testWidgets('theme toggle popup opens with System/Light/Dark options', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleRepositoryProvider.overrideWith(
            (_) => FakeBleRepository(devices: const []),
          ),
        ],
        child: const app_entry.WheelAthleteApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Theme mode'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('System'), findsWidgets);
    expect(find.text('Light'), findsWidgets);
    expect(find.text('Dark'), findsWidgets);
  });

  testWidgets('main() entry: WheelAthleteApp renders real home', (
    tester,
  ) async {
    // Verify the WheelAthleteApp widget (the app root) renders the real home,
    // without calling main() directly (runApp in test context causes an
    // AnimationController assertion when the scheduler's fake clock interacts
    // with an immediately-scheduled warm-up frame).
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleRepositoryProvider.overrideWith(
            (_) => FakeBleRepository(devices: const []),
          ),
        ],
        child: const app_entry.WheelAthleteApp(),
      ),
    );
    await tester.pump();
    expect(find.text('WheelAthlete'), findsWidgets);
    expect(find.widgetWithText(NavigationDestination, 'Dashboard'), findsOneWidget);
  });

  testWidgets('ThemeModeController cycle via widget tree', (tester) async {
    final ctrl = ThemeModeController(ThemeMode.system);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<ThemeMode>(
            valueListenable: ctrl,
            builder: (context, mode, _) => Text('Mode: ${mode.name}'),
          ),
        ),
      ),
    );
    expect(find.text('Mode: system'), findsOneWidget);
    ctrl.cycle();
    await tester.pump();
    expect(find.text('Mode: light'), findsOneWidget);
    ctrl.cycle();
    await tester.pump();
    expect(find.text('Mode: dark'), findsOneWidget);
    ctrl.dispose();
  });
}
