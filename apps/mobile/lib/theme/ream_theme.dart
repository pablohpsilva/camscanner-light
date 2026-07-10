import 'package:flutter/material.dart';
import 'ream_colors.dart';
import 'ream_typography.dart';

/// Builds the Ream [ThemeData] for light and dark, mapping [ReamColors] onto a
/// Material [ColorScheme] so stock widgets inherit sensible colors.
class ReamTheme {
  static ThemeData light() => _build(ReamColors.light, Brightness.light);
  static ThemeData dark() => _build(ReamColors.dark, Brightness.dark);

  static ThemeData _build(ReamColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.greenDeep,
      brightness: brightness,
    ).copyWith(surface: c.surface, primary: c.greenDeep, error: c.deleteRed);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.paper,
      textTheme: ReamTypography.textTheme(c.ink),
      extensions: [c],
    );
  }
}
