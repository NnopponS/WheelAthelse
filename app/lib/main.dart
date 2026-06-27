import 'package:flutter/material.dart';

import 'package:wheelsense/theme/theme.dart';
import 'package:wheelsense/ui/showcase_page.dart';

void main() => runApp(const WheelSenseApp());

/// App root. For subtask #4 the home screen is the design-system showcase
/// (living style guide). Real screens (scan/connect, live, recording, browse)
/// are added in subtasks #5+ and will reuse the theme and components defined
/// here.
class WheelSenseApp extends StatefulWidget {
  const WheelSenseApp({super.key});

  @override
  State<WheelSenseApp> createState() => _WheelSenseAppState();
}

class _WheelSenseAppState extends State<WheelSenseApp> {
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
          title: 'WheelSense',
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
