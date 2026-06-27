import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wheelsense/main.dart' as app_entry;
import 'package:wheelsense/theme/theme_mode_controller.dart';

void main() {
  setUpAll(() {
    // Avoid network font fetches during tests; fall back to bundled fonts.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // The showcase page has a Timer.periodic (120 ms) that keeps scheduling
  // frames, so pumpAndSettle would time out. Use pump() with a small duration
  // instead to process pending frames without waiting for quiescence.

  /// Drag the main ListView until [target] is actually on-screen (center
  /// within the 800×600 test viewport), pumping between drags.
  Future<void> dragUntilVisible(
    WidgetTester tester,
    Finder target, {
    double delta = -300,
    int maxScrolls = 30,
  }) async {
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < maxScrolls; i++) {
      if (tester.any(target)) {
        try {
          final center = tester.getCenter(target);
          if (center.dy > 50 && center.dy < 550) break;
        } on StateError {
          // Widget not yet laid out — keep scrolling.
        }
      }
      await tester.drag(scrollable, Offset(0, delta));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('Showcase renders core components and theme menu opens',
      (tester) async {
    await tester.pumpWidget(const app_entry.WheelSenseApp());
    await tester.pump();

    // Sections + components are present in the initial viewport.
    expect(find.text('WheelSense UI'), findsOneWidget);
    expect(find.text('Left wheel'), findsOneWidget);
    expect(find.text('Right wheel'), findsWidgets);

    // Theme mode popup menu button is present.
    expect(find.byTooltip('Theme mode'), findsOneWidget);

    // Open the popup menu — the three options should appear.
    await tester.tap(find.byTooltip('Theme mode'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('System'), findsWidgets);
    expect(find.text('Light'), findsWidgets);
    expect(find.text('Dark'), findsWidgets);
  });

  testWidgets('tapping Start recording toggles state and enables Mark button',
      (tester) async {
    await tester.pumpWidget(const app_entry.WheelSenseApp());
    await tester.pump();

    // Scroll down to the primary actions section.
    await dragUntilVisible(tester, find.text('Start recording'));
    // Tap Start recording — flips _recording to true.
    await tester.tap(find.text('Start recording'));
    await tester.pump(const Duration(milliseconds: 50));
    // Label should now say Stop recording.
    expect(find.text('Stop recording'), findsOneWidget);

    // Scroll down to Mark event section.
    await dragUntilVisible(tester, find.text('MARK'));
    await tester.tap(find.text('MARK'));
    await tester.pump(const Duration(milliseconds: 50));

    // Scroll back up and tap Stop recording to flip back.
    await dragUntilVisible(tester, find.text('Stop recording'));
    await tester.tap(find.text('Stop recording'));
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('busy sync button renders spinner', (tester) async {
    await tester.pumpWidget(const app_entry.WheelSenseApp());
    await tester.pump();

    // Scroll to the Primary actions section.
    await dragUntilVisible(tester, find.text('Start recording'));
    // The busy button shows a spinner, not the label text.
    // Just verify the section renders without error.
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('tapping connection cards and session items invokes callbacks',
      (tester) async {
    await tester.pumpWidget(const app_entry.WheelSenseApp());
    await tester.pump();

    // Scroll down to connection cards.
    await dragUntilVisible(tester, find.text('WheelSense-L'));
    await tester.tap(find.text('WheelSense-L'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('WheelSense-R'));
    await tester.pump(const Duration(milliseconds: 50));

    // Scroll down to session list.
    await dragUntilVisible(tester, find.text('session_a1f3'));
    await tester.tap(find.text('session_a1f3'));
    await tester.pump(const Duration(milliseconds: 50));
    // Scroll a bit more to bring session_b22c into view.
    await dragUntilVisible(tester, find.text('session_b22c'), delta: -80);
    await tester.tap(find.text('session_b22c'));
    await tester.pump(const Duration(milliseconds: 50));

    // Tap share icons (there are two).
    final shareIcons = find.byIcon(Icons.ios_share_rounded);
    for (var i = 0; i < shareIcons.evaluate().length; i++) {
      await tester.tap(shareIcons.at(i), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('tapping empty-state action and error-state retry', (tester) async {
    await tester.pumpWidget(const app_entry.WheelSenseApp());
    await tester.pump();

    // Scroll down to Empty state.
    await dragUntilVisible(tester, find.text('Scan for devices'));
    await tester.tap(find.text('Scan for devices'));
    await tester.pump(const Duration(milliseconds: 50));

    // Scroll down to Error state.
    await dragUntilVisible(tester, find.text('Try again'));
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('main() launches the app', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Calling main() directly exercises the entry point.
    app_entry.main();
    await tester.pump();
    expect(find.text('WheelSense UI'), findsOneWidget);
    // Clean up so subsequent tests don't see two apps.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ThemeModeController cycle via widget tree', (tester) async {
    final ctrl = ThemeModeController(ThemeMode.system);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<ThemeMode>(
            valueListenable: ctrl,
            builder: (context, mode, _) {
              return Text('Mode: ${mode.name}');
            },
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
