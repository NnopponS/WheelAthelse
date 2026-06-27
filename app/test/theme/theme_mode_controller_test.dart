import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelsense/theme/app_theme.dart';
import 'package:wheelsense/theme/theme_mode_controller.dart';

void main() {
  group('ThemeModeController.set', () {
    test('updates the value', () {
      final ctrl = ThemeModeController();
      ctrl.set(ThemeMode.dark);
      expect(ctrl.value, ThemeMode.dark);
      ctrl.set(ThemeMode.light);
      expect(ctrl.value, ThemeMode.light);
      ctrl.set(ThemeMode.system);
      expect(ctrl.value, ThemeMode.system);
    });

    test('notifies listeners when value changes', () {
      final ctrl = ThemeModeController();
      var notifications = 0;
      ctrl.addListener(() => notifications++);
      ctrl.set(ThemeMode.dark);
      ctrl.set(ThemeMode.light);
      expect(notifications, 2);
    });

    test('does not notify when setting the same value', () {
      final ctrl = ThemeModeController(ThemeMode.dark);
      var notifications = 0;
      ctrl.addListener(() => notifications++);
      ctrl.set(ThemeMode.dark);
      expect(notifications, 0);
    });
  });

  group('ThemeModeController.cycle', () {
    test('cycles system → light → dark → system', () {
      final ctrl = ThemeModeController(ThemeMode.system);
      ctrl.cycle();
      expect(ctrl.value, ThemeMode.light);
      ctrl.cycle();
      expect(ctrl.value, ThemeMode.dark);
      ctrl.cycle();
      expect(ctrl.value, ThemeMode.system);
    });
  });

  group('ThemeModeController.isDark', () {
    testWidgets('returns true for dark mode', (tester) async {
      final ctrl = ThemeModeController(ThemeMode.dark);
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = ctrl.isDark(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(result, isTrue);
      ctrl.dispose();
    });

    testWidgets('returns false for light mode', (tester) async {
      final ctrl = ThemeModeController(ThemeMode.light);
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = ctrl.isDark(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(result, isFalse);
      ctrl.dispose();
    });

    testWidgets('resolves system mode against platform brightness',
        (tester) async {
      final ctrl = ThemeModeController(ThemeMode.system);
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.system,
          home: MediaQuery(
            data: const MediaQueryData(platformBrightness: Brightness.dark),
            child: Builder(
              builder: (context) {
                result = ctrl.isDark(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(result, isTrue);
      ctrl.dispose();
    });
  });
}
