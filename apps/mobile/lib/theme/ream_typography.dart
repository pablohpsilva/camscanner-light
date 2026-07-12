import 'package:flutter/material.dart';

/// Ream typography: Figtree for UI, IBM Plex Mono for technical readouts.
class ReamTypography {
  ReamTypography._();

  static const _ui = 'Figtree';
  static const _mono = 'IBMPlexMono';

  static TextTheme textTheme(Color ink) {
    TextStyle f(double size, FontWeight w, {double spacing = 0}) => TextStyle(
      fontFamily: _ui,
      fontSize: size,
      fontWeight: w,
      color: ink,
      letterSpacing: spacing,
      height: 1.2,
    );
    return TextTheme(
      displayLarge: f(28, FontWeight.w800, spacing: -0.5),
      headlineMedium: f(24, FontWeight.w800, spacing: -0.4),
      titleLarge: f(18, FontWeight.w700),
      titleMedium: f(15, FontWeight.w600),
      bodyLarge: f(14.5, FontWeight.w500),
      bodyMedium: f(13, FontWeight.w400),
      labelLarge: f(13.5, FontWeight.w600),
      labelMedium: f(12, FontWeight.w600),
    );
  }

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: _mono,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );
}
