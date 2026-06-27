import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheelsense/theme/app_palette.dart';
import 'package:wheelsense/theme/wheel_side.dart';
import 'package:wheelsense/theme/wheelsense_colors.dart';

void main() {
  group('WheelSenseColors.forWheel', () {
    test('returns the left role for the left wheel', () {
      expect(WheelSenseColors.light.forWheel(WheelSide.left),
          same(WheelSenseColors.light.left));
    });

    test('returns the right role for the right wheel', () {
      expect(WheelSenseColors.light.forWheel(WheelSide.right),
          same(WheelSenseColors.light.right));
    });

    test('left and right solids are visibly distinct', () {
      expect(WheelSenseColors.light.left.solid,
          isNot(equals(WheelSenseColors.light.right.solid)));
    });
  });

  group('lerp', () {
    test('t=0 yields the start values', () {
      final result = WheelSenseColors.light.lerp(WheelSenseColors.dark, 0);
      expect(result.left.solid, WheelSenseColors.light.left.solid);
      expect(result.chartGrid, WheelSenseColors.light.chartGrid);
    });

    test('t=1 yields the end values', () {
      final result = WheelSenseColors.light.lerp(WheelSenseColors.dark, 1);
      expect(result.left.solid, WheelSenseColors.dark.left.solid);
      expect(result.danger.container, WheelSenseColors.dark.danger.container);
    });

    test('returns this when other is not a WheelSenseColors', () {
      expect(WheelSenseColors.light.lerp(null, 0.5), WheelSenseColors.light);
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
    expect(WheelSenseColors.light.left.solid, AppPalette.left);
  });

  group('copyWith', () {
    test('returns identical values when called with no arguments', () {
      final copy = WheelSenseColors.light.copyWith();
      expect(copy.left.solid, WheelSenseColors.light.left.solid);
      expect(copy.right.solid, WheelSenseColors.light.right.solid);
      expect(copy.success.solid, WheelSenseColors.light.success.solid);
      expect(copy.warning.solid, WheelSenseColors.light.warning.solid);
      expect(copy.danger.solid, WheelSenseColors.light.danger.solid);
      expect(copy.chartGrid, WheelSenseColors.light.chartGrid);
    });

    test('overrides only the supplied fields', () {
      const newLeft = ColorRole(
        solid: Color(0xFF123456),
        on: Color(0xFFFFFFFF),
        container: Color(0xFF654321),
        onContainer: Color(0xFFEEEEEE),
      );
      final copy = WheelSenseColors.light.copyWith(left: newLeft);
      expect(copy.left.solid, const Color(0xFF123456));
      // Untouched fields keep the original.
      expect(copy.right.solid, WheelSenseColors.light.right.solid);
      expect(copy.chartGrid, WheelSenseColors.light.chartGrid);
    });
  });
}
