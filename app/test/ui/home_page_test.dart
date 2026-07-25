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

  testWidgets('shows three NavigationBar destinations', (tester) async {
    await pumpHome(tester);

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    // Experiments tab was merged into Browse (Phase 4 follow-up).
    expect(find.text('Experiments'), findsNothing);
  });

  testWidgets('starts on Connect tab — shows ConnectionCard content', (
    tester,
  ) async {
    await pumpHome(tester);

    // Connect tab is active; ConnectPage shows its two ConnectionCards.
    expect(find.text('Left wheel'), findsOneWidget);
    expect(find.text('Right wheel'), findsOneWidget);
  });

  testWidgets('tapping Live tab reveals Live IMU AppBar', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Live'));
    await tester.pump();

    expect(find.text('Live IMU'), findsOneWidget);
  });

  testWidgets('tapping Browse tab reveals Browse AppBar', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Browse'));
    // BrowsePage contains a FutureBuilder with CircularProgressIndicator which
    // animates continuously — pumpAndSettle would time out. Use pump() instead.
    await tester.pump(const Duration(milliseconds: 100));

    // BrowsePage renders a Scaffold with AppBar title 'Browse'.
    expect(find.text('Browse'), findsWidgets);
  });

  testWidgets('tapping Browse tab reveals New Template FAB', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Browse'));
    // BrowsePage contains a FutureBuilder with CircularProgressIndicator which
    // animates continuously — pumpAndSettle would time out. Use pump() instead.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('New Template'), findsOneWidget);
  });

  testWidgets('Live page Browse button switches to the bottom-nav Browse tab', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();
    expect(find.text('Live IMU'), findsOneWidget);

    // Tap the folder icon in the Live AppBar (tooltip 'Browse').
    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.folder_open_rounded),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Should now be on the Browse tab: Browse AppBar shows and Live content
    // is hidden (no second Browse page was pushed on the nav stack).
    expect(find.text('Browse'), findsWidgets);
    expect(find.text('Live IMU'), findsNothing);
    expect(find.text('New Template'), findsOneWidget);
  });

  testWidgets('switching tabs back to Connect restores Connect content', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.text('Live'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Live IMU'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.pump(const Duration(milliseconds: 50));
    // Back to Connect tab content.
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
    expect(find.byIcon(Icons.sensors_rounded), findsNothing);
  });
}
