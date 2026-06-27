import 'package:flutter/material.dart';

import 'app_dimens.dart';
import 'app_palette.dart';
import 'app_typography.dart';
import 'wheelsense_colors.dart';

/// Builds the WheelSense [ThemeData] for light and dark modes.
///
/// Light mode is the field default: a near-white surface with strong dark ink
/// for maximum legibility under sunlight. Dark mode is for indoor review.
abstract final class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          primary: AppPalette.brand,
          onPrimary: AppPalette.white,
          primaryContainer: Color(0xFFCCFBF1),
          onPrimaryContainer: AppPalette.brandStrong,
          secondary: AppPalette.left,
          onSecondary: AppPalette.white,
          surface: AppPalette.white,
          onSurface: AppPalette.slate900,
          surfaceContainerLowest: AppPalette.white,
          surfaceContainerLow: AppPalette.slate50,
          surfaceContainer: AppPalette.slate100,
          surfaceContainerHigh: AppPalette.slate200,
          onSurfaceVariant: AppPalette.slate600,
          outline: AppPalette.slate300,
          outlineVariant: AppPalette.slate200,
          error: AppPalette.danger,
          onError: AppPalette.white,
        ),
        scaffold: AppPalette.slate50,
        ink: AppPalette.slate900,
        muted: AppPalette.slate600,
        wheelColors: WheelSenseColors.light,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          primary: AppPalette.brandSoft,
          onPrimary: AppPalette.slate950,
          primaryContainer: AppPalette.brandStrong,
          onPrimaryContainer: Color(0xFFCCFBF1),
          secondary: AppPalette.leftBright,
          onSecondary: AppPalette.slate950,
          surface: AppPalette.slate900,
          onSurface: AppPalette.slate100,
          surfaceContainerLowest: AppPalette.slate950,
          surfaceContainerLow: AppPalette.slate900,
          surfaceContainer: AppPalette.slate850,
          surfaceContainerHigh: AppPalette.slate800,
          onSurfaceVariant: AppPalette.slate400,
          outline: AppPalette.slate700,
          outlineVariant: AppPalette.slate800,
          error: AppPalette.dangerBright,
          onError: AppPalette.slate950,
        ),
        scaffold: AppPalette.slate950,
        ink: AppPalette.slate100,
        muted: AppPalette.slate400,
        wheelColors: WheelSenseColors.dark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color scaffold,
    required Color ink,
    required Color muted,
    required WheelSenseColors wheelColors,
  }) {
    final textTheme = AppTypography.textTheme(ink, muted);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      textTheme: textTheme,
      extensions: [wheelColors],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        foregroundColor: ink,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brLg,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppSizing.minTouch),
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppSizing.minTouch),
          textStyle: textTheme.labelLarge,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: textTheme.labelLarge,
          foregroundColor: scheme.primary,
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      ),
    );
  }
}
