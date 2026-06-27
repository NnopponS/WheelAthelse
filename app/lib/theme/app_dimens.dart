import 'package:flutter/widgets.dart';

/// Spacing scale (4pt base). Use these instead of magic numbers so rhythm stays
/// consistent across every screen.
abstract final class AppSpacing {
  const AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double huge = 48;

  // Convenience EdgeInsets used repeatedly.
  static const EdgeInsets pagePadding = EdgeInsets.all(md);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
}

/// Corner radius scale.
abstract final class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;

  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
}

/// Minimum interactive sizes. Field use means gloves, motion, and glances —
/// touch targets are larger than the 48dp baseline for primary actions.
abstract final class AppSizing {
  const AppSizing._();

  /// Baseline accessible touch target.
  static const double minTouch = 48;

  /// Big in-field primary action (start/stop) — easy to hit while moving.
  static const double primaryActionHeight = 72;

  /// Mark-event button diameter.
  static const double markButton = 96;

  /// Max content width on large/tablet screens to keep line lengths sane.
  static const double maxContentWidth = 640;
}
