import 'package:flutter/material.dart';

/// Observable app-level theme-mode selector.
///
/// Wraps a [ValueNotifier] so any widget can listen and rebuild when the user
/// picks *System*, *Light*, or *Dark* from the AppBar menu. Keeping this as a
/// separate class (instead of stashing [ThemeMode] in a `State` field) makes it
/// trivial to unit-test the cycling logic and to later persist the choice via
/// `SharedPreferences` without touching the widget tree.
class ThemeModeController extends ValueNotifier<ThemeMode> {
  ThemeModeController([super.value = ThemeMode.system]);

  /// Jump directly to [mode].
  void set(ThemeMode mode) => value = mode;

  /// Cycle system → light → dark → system. Used by the icon-only toggle.
  void cycle() {
    switch (value) {
      case ThemeMode.system:
        value = ThemeMode.light;
      case ThemeMode.light:
        value = ThemeMode.dark;
      case ThemeMode.dark:
        value = ThemeMode.system;
    }
  }

  /// `true` when the effective mode (after resolving `system`) is dark.
  bool isDark(BuildContext context) {
    final brightness = switch (value) {
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
    };
    return brightness == Brightness.dark;
  }
}
