import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelathlete/theme/app_palette.dart';
import 'package:wheelathlete/theme/wheel_side.dart';
import 'package:wheelathlete/theme/WheelAthlete_colors.dart';

void main() {
  group('WheelAthleteColors.forWheel', () {
    test('returns the left role for the left wheel', () {
      expect(WheelAthleteColors.light.forWheel(WheelSide.left),
          same(WheelAthleteColors.light.left));
    });

    test('returns the right role for the right wheel', () {
      expect(WheelAthleteColors.light.forWheel(WheelSide.right),
          same(WheelAthleteColors.light.right));
    });

    test('left and right solids are visibly distinct', () {
      expect(WheelAthleteColors.light.left.solid,
          isNot(equals(WheelAthleteColors.light.right.solid)));
    });
  });

  group('lerp', () {
    test('t=0 yields the start values', () {
      final result = WheelAthleteColors.light.lerp(WheelAthleteColors.dark, 0);
      expect(result.left.solid, WheelAthleteColors.light.left.solid);
      expect(result.chartGrid, WheelAthleteColors.light.chartGrid);
    });

    test('t=1 yields the end values', () {
      final result = WheelAthleteColors.light.lerp(WheelAthleteColors.dark, 1);
      expect(result.left.solid, WheelAthleteColors.dark.left.solid);
      expect(result.danger.container, WheelAthleteColors.dark.danger.container);
    });

    test('returns this when other is not a WheelAthleteColors', () {
      expect(WheelAthleteColors.light.lerp(null, 0.5), WheelAthleteColors.light);
    });
  });

  group('ColorRole.lerp', () {
    test('interpolates every channel', () {
      const a = ColorRole(
        solid: Color(0xFF000000),
        on: Color(0xFF000000),
        container: Color(0xFF000000),
        onContainer: Color(0xFF000000),
      );
      const b = ColorRole(
        solid: Color(0xFFFFFFFF),
        on: Color(0xFFFFFFFF),
        container: Color(0xFFFFFFFF),
        onContainer: Color(0xFFFFFFFF),
      );
      final mid = a.lerp(b, 1);
      expect(mid.solid, b.solid);
      expect(mid.onContainer, b.onContainer);
    });
  });

  test('left identity color matches the documented palette value', () {
    expect(WheelAthleteColors.light.left.solid, AppPalette.left);
  });

  group('copyWith', () {
    test('returns identical values when called with no arguments', () {
      final copy = WheelAthleteColors.light.copyWith();
      expect(copy.left.solid, WheelAthleteColors.light.left.solid);
      expect(copy.right.solid, WheelAthleteColors.light.right.solid);
      expect(copy.success.solid, WheelAthleteColors.light.success.solid);
      expect(copy.warning.solid, WheelAthleteColors.light.warning.solid);
      expect(copy.danger.solid, WheelAthleteColors.light.danger.solid);
      expect(copy.chartGrid, WheelAthleteColors.light.chartGrid);
    });

    test('overrides only the supplied fields', () {
      const newLeft = ColorRole(
        solid: Color(0xFF123456),
        on: Color(0xFFFFFFFF),
        container: Color(0xFF654321),
        onContainer: Color(0xFFEEEEEE),
      );
      final copy = WheelAthleteColors.light.copyWith(left: newLeft);
      expect(copy.left.solid, const Color(0xFF123456));
      // Untouched fields keep the original.
      expect(copy.right.solid, WheelAthleteColors.light.right.solid);
      expect(copy.chartGrid, WheelAthleteColors.light.chartGrid);
    });
  });
}
