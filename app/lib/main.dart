import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:wheelathlete/desktop/desktop_home_page.dart';
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
  runApp(
    ProviderScope(
      child: WheelAthleteApp(
        desktopMode: Platform.isWindows,
        desktopAutoConnect: Platform.isWindows,
      ),
    ),
  );
}

/// App root.
///
/// The default constructor deliberately remains the existing mobile shell so
/// Android/mobile tests and embeddings do not acquire a daemon dependency.
/// The real [main] entrypoint opts into [DesktopHomePage] only on Windows.
class WheelAthleteApp extends StatefulWidget {
  const WheelAthleteApp({
    super.key,
    this.desktopMode = false,
    this.desktopAutoConnect = false,
  });

  final bool desktopMode;
  final bool desktopAutoConnect;

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
          home: widget.desktopMode
              ? DesktopHomePage(
                  themeController: _theme,
                  autoConnect: widget.desktopAutoConnect,
                )
              : HomePage(themeController: _theme),
          routes: {'/showcase': (context) => ShowcasePage(controller: _theme)},
        );
      },
    );
  }
}
