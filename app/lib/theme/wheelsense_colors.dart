import 'package:flutter/material.dart';

import 'package:wheelsense/theme/app_palette.dart';
import 'package:wheelsense/theme/wheel_side.dart';

/// A pair of foreground/background colors used to render a semantic chip,
/// badge, or accent surface. [container] is a tinted fill; [on] is text/icon
/// color that meets contrast on [container]; [solid] is the full-strength hue.
@immutable
class ColorRole {
  const ColorRole({
    required this.solid,
    required this.on,
    required this.container,
    required this.onContainer,
  });

  /// Full-strength hue (e.g. for indicators, borders, charts).
  final Color solid;

  /// Foreground that reads on top of [solid].
  final Color on;

  /// Soft tinted fill for chips/cards.
  final Color container;

  /// Foreground that reads on top of [container].
  final Color onContainer;

  ColorRole lerp(ColorRole other, double t) => ColorRole(
        solid: Color.lerp(solid, other.solid, t)!,
        on: Color.lerp(on, other.on, t)!,
        container: Color.lerp(container, other.container, t)!,
        onContainer: Color.lerp(onContainer, other.onContainer, t)!,
      );
}

/// WheelSense-specific colors that don't fit Material's [ColorScheme]:
/// per-wheel identity (L/R) and extra semantic roles (success/warning).
/// Access via `Theme.of(context).extension<WheelSenseColors>()!` or the
/// `context.wheelColors` helper.
@immutable
class WheelSenseColors extends ThemeExtension<WheelSenseColors> {
  const WheelSenseColors({
    required this.left,
    required this.right,
    required this.success,
    required this.warning,
    required this.danger,
    required this.chartGrid,
  });

  final ColorRole left;
  final ColorRole right;
  final ColorRole success;
  final ColorRole warning;
  final ColorRole danger;

  /// Subtle line color for chart gridlines / dividers on chart surfaces.
  final Color chartGrid;

  /// Returns the color role for a given wheel.
  ColorRole forWheel(WheelSide side) =>
      side == WheelSide.left ? left : right;

  static const WheelSenseColors light = WheelSenseColors(
    left: ColorRole(
      solid: AppPalette.left,
      on: AppPalette.white,
      container: Color(0xFFDBEAFE),
      onContainer: AppPalette.leftStrong,
    ),
    right: ColorRole(
      solid: AppPalette.rightStrong,
      on: AppPalette.white,
      container: Color(0xFFFFEDD5),
      onContainer: Color(0xFF9A3412),
    ),
    success: ColorRole(
      solid: AppPalette.success,
      on: AppPalette.white,
      container: Color(0xFFDCFCE7),
      onContainer: Color(0xFF15803D),
    ),
    warning: ColorRole(
      solid: Color(0xFFA16207),
      on: AppPalette.white,
      container: Color(0xFFFEF9C3),
      onContainer: Color(0xFF854D0E),
    ),
    danger: ColorRole(
      solid: AppPalette.danger,
      on: AppPalette.white,
      container: Color(0xFFFEE2E2),
      onContainer: Color(0xFFB91C1C),
    ),
    chartGrid: AppPalette.slate200,
  );

  static const WheelSenseColors dark = WheelSenseColors(
    left: ColorRole(
      solid: AppPalette.leftBright,
      on: AppPalette.slate950,
      container: Color(0xFF172554),
      onContainer: Color(0xFFBFDBFE),
    ),
    right: ColorRole(
      solid: AppPalette.rightBright,
      on: AppPalette.slate950,
      container: Color(0xFF431407),
      onContainer: Color(0xFFFED7AA),
    ),
    success: ColorRole(
      solid: AppPalette.successBright,
      on: AppPalette.slate950,
      container: Color(0xFF14532D),
      onContainer: Color(0xFFBBF7D0),
    ),
    warning: ColorRole(
      solid: AppPalette.warningBright,
      on: AppPalette.slate950,
      container: Color(0xFF422006),
      onContainer: Color(0xFFFEF08A),
    ),
    danger: ColorRole(
      solid: AppPalette.dangerBright,
      on: AppPalette.slate950,
      container: Color(0xFF450A0A),
      onContainer: Color(0xFFFECACA),
    ),
    chartGrid: AppPalette.slate700,
  );

  @override
  WheelSenseColors copyWith({
    ColorRole? left,
    ColorRole? right,
    ColorRole? success,
    ColorRole? warning,
    ColorRole? danger,
    Color? chartGrid,
  }) {
    return WheelSenseColors(
      left: left ?? this.left,
      right: right ?? this.right,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      chartGrid: chartGrid ?? this.chartGrid,
    );
  }

  @override
  WheelSenseColors lerp(ThemeExtension<WheelSenseColors>? other, double t) {
    if (other is! WheelSenseColors) return this;
    return WheelSenseColors(
      left: left.lerp(other.left, t),
      right: right.lerp(other.right, t),
      success: success.lerp(other.success, t),
      warning: warning.lerp(other.warning, t),
      danger: danger.lerp(other.danger, t),
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
    );
  }
}

/// Ergonomic access to [WheelSenseColors] from a [BuildContext].
extension WheelSenseColorsX on BuildContext {
  WheelSenseColors get wheelColors =>
      Theme.of(this).extension<WheelSenseColors>()!;
}
