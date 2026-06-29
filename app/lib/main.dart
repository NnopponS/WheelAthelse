import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/showcase_page.dart';

void main() {
  // Disable runtime font fetching so the app works offline and doesn't
  // crash on devices without network access. Falls back to bundled fonts.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const ProviderScope(child: WheelAthleteApp()));
}

/// App root. For subtask #4 the home screen is the design-system showcase
/// (living style guide). Real screens (scan/connect, live, recording, browse)
/// are added in subtasks #5+ and will reuse the theme and components defined
/// here.
class WheelAthleteApp extends StatefulWidget {
  const WheelAthleteApp({super.key});

  @override
  State<WheelAthleteApp> createState() => _WheelAthleteAppState();
}

class _WheelAthleteAppState extends State<WheelAthleteApp> {
  final ThemeModeController _theme = ThemeModeController();

  @override
  void dispose() {
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _theme,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'WheelAthlete',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: ShowcasePage(
            controller: _theme,
          ),
        );
      },
    );
  }
}
