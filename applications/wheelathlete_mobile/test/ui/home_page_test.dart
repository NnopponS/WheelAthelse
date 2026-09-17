// Tests for the HomePage shell: tab navigation, connection badge, theme toggle.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/ble/ble_repository.dart';
import 'package:wheelathlete/records/protocol_repository.dart';
import 'package:wheelathlete/records/storage_repository.dart';
import 'package:wheelathlete/state/ble_providers.dart';
import 'package:wheelathlete/state/protocol_providers.dart';
import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/home_page.dart';

import '../helpers/pump.dart';

void main() {
  setUpAll(disableGoogleFontsFetching);

  Future<void> pumpHome(
    WidgetTester tester, {
    FakeBleRepository? ble,
    InMemoryProtocolRepository? protocolRepo,
    InMemoryStorageRepository? storageRepo,
  }) async {
    final ctrl = ThemeModeController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleRepositoryProvider.overrideWith(
            (_) => ble ?? FakeBleRepository(devices: const []),
          ),
          protocolRepositoryProvider.overrideWith(
            (_) => protocolRepo ?? InMemoryProtocolRepository(),
          ),
          storageRepositoryProvider.overrideWith(
            (_) => storageRepo ?? InMemoryStorageRepository(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: HomePage(themeController: ctrl),
        ),
      ),
    );
    await tester.pump();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  testWidgets('shows five NavigationBar destinations', (tester) async {
    await pumpHome(tester);

    expect(find.widgetWithText(NavigationDestination, 'Dashboard'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Acquisition'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Results'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Model'), findsOneWidget);
    expect(find.widgetWithText(NavigationDestination, 'Diagnostics'), findsOneWidget);
  });

  testWidgets('starts on Dashboard tab — shows 3-sensor cards and actions', (
    tester,
  ) async {
    await pumpHome(tester);

    // Dashboard tab is active; shows sensor cards
    expect(find.text('Left wheel'), findsOneWidget);
    expect(find.text('Right wheel'), findsOneWidget);
    expect(find.text('Chair center'), findsOneWidget);
  });

  testWidgets('tapping Acquisition tab reveals Acquisition content', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Acquisition'));
    await tester.pump();

    expect(find.text('Acquisition'), findsWidgets);
  });

  testWidgets('tapping Results tab reveals Results content', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Results'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Results'), findsWidgets);
  });

  testWidgets('tapping Model tab reveals Model & Trajectory content', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Model'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Model & Trajectory'), findsWidgets);
  });

  testWidgets('tapping Diagnostics tab reveals Diagnostics matrix', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Diagnostics'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Diagnostics'), findsWidgets);
  });

  testWidgets('switching between tabs preserves shell AppBar', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Acquisition'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('WheelAthlete'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Dashboard'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Left wheel'), findsOneWidget);
  });

  // ── AppBar ────────────────────────────────────────────────────────────────

  testWidgets('AppBar title is WheelAthlete', (tester) async {
    await pumpHome(tester);

    expect(find.text('WheelAthlete'), findsOneWidget);
  });

  testWidgets('theme toggle button is in AppBar', (tester) async {
    await pumpHome(tester);

    expect(find.byTooltip('Theme mode'), findsOneWidget);
  });

  testWidgets('theme toggle opens popup with System/Light/Dark', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.byTooltip('Theme mode'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('System'), findsWidgets);
    expect(find.text('Light'), findsWidgets);
    expect(find.text('Dark'), findsWidgets);
  });

  // ── Connection chip ───────────────────────────────────────────────────────

  testWidgets('no connection chip when no wheels connected', (tester) async {
    await pumpHome(tester);

    // The chip only appears when connectedCount > 0.
    expect(find.text('1 wheel'), findsNothing);
    expect(find.text('L+R'), findsNothing);
  });
}
