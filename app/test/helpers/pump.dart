import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wheelsense/theme/theme.dart';

/// Disables network font fetching for the whole test run. Call once in
/// `setUpAll`. Tests then use the bundled fallback font, avoiding flaky network
/// access and keeping layout deterministic.
void disableGoogleFontsFetching() {
  GoogleFonts.config.allowRuntimeFetching = false;
}

/// Pumps [child] inside a [MaterialApp] using the WheelSense theme so widgets
/// can resolve [Theme], [ColorScheme], and the [WheelSenseColors] extension.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
}) {
  return tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}
