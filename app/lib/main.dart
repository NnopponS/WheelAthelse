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
  ThemeMode _mode = ThemeMode.light;

  void _toggle() => setState(() {
        _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WheelSense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      home: ShowcasePage(
        onToggleTheme: _toggle,
        isDark: _mode == ThemeMode.dark,
      ),
    );
  }
}
