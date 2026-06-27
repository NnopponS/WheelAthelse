import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wheelsense/main.dart';

void main() {
  setUpAll(() {
    // Avoid network font fetches during tests; fall back to bundled fonts.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Showcase renders core components and toggles theme',
      (tester) async {
    await tester.pumpWidget(const WheelSenseApp());
    await tester.pump();

    // Sections + components are present in the initial viewport.
    expect(find.text('WheelSense UI'), findsOneWidget);
    expect(find.text('Left wheel'), findsOneWidget);
    expect(find.text('Right wheel'), findsWidgets);

    // A primary action further down the list renders after scrolling to it.
    await tester.scrollUntilVisible(
      find.text('Start recording'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Start recording'), findsOneWidget);

    // Theme toggle flips light -> dark.
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.dark_mode_rounded));
    await tester.pump();
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
  });
}
