import 'package:flutter/material.dart';

/// Raw color primitives for the WheelAthlete design system.
///
/// These are the only place hex literals live. Everything else in the app
/// references colors through [ColorScheme] or the [WheelAthleteColors] theme
/// extension. High-chroma, high-contrast values are chosen deliberately so the
/// UI stays legible on a phone screen under direct sunlight on the field.
///
/// Wheel identity colors (Left = blue, Right = orange) are a colorblind-safe
/// pairing (distinguishable under deutan/protan deficiency) and are used
/// consistently everywhere a left/right wheel is represented.
abstract final class AppPalette {
  const AppPalette._();

  // ---- Brand (teal) — deliberately distinct from L/R wheel hues ----
  static const Color brand = Color(0xFF0D9488);
  static const Color brandStrong = Color(0xFF0F766E);
  static const Color brandSoft = Color(0xFF5EEAD4);

  // ---- Left wheel (blue) ----
  static const Color left = Color(0xFF2563EB);
  static const Color leftStrong = Color(0xFF1D4ED8);
  static const Color leftBright = Color(0xFF60A5FA);

  // ---- Right wheel (orange) ----
  static const Color right = Color(0xFFF97316);
  static const Color rightStrong = Color(0xFFEA580C);
  static const Color rightBright = Color(0xFFFB923C);

  // ---- Semantic ----
  static const Color success = Color(0xFF16A34A);
  static const Color successBright = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFEAB308); // clearly yellow vs orange R
  static const Color warningBright = Color(0xFFFACC15);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerBright = Color(0xFFF87171);

  // ---- Neutrals (slate ramp) ----
  static const Color slate950 = Color(0xFF020617);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate850 = Color(0xFF162032);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color white = Color(0xFFFFFFFF);
}
