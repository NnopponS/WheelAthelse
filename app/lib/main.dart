import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:wheelathlete/theme/theme.dart';
import 'package:wheelathlete/ui/home_page.dart';
import 'package:wheelathlete/ui/showcase_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // flutter_blue_plus defaults to DEBUG on Android, including two native log
  // lines for every characteristic notification. Dual-wheel acquisition is a
  // sustained high-throughput path, so keep production logging disabled and
  // rely on explicit acquisition-health counters instead.
  await FlutterBluePlus.setLogLevel(LogLevel.none);
  GoogleFonts.config.allowRuntimeFetching = true;
  runApp(const ProviderScope(child: WheelAthleteApp()));
}

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
          home: HomePage(themeController: _theme),
          routes: {'/showcase': (context) => ShowcasePage(controller: _theme)},
        );
      },
    );
  }
}
