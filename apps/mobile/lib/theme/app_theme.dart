import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the App [ThemeData] for light and dark, mapping [AppColors] onto a
/// Material [ColorScheme] so stock widgets inherit sensible colors.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(AppColors.light, Brightness.light);
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.greenDeep,
      brightness: brightness,
    ).copyWith(surface: c.surface, primary: c.greenDeep, error: c.deleteRed);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.paper,
      textTheme: AppTypography.textTheme(c.ink),
      extensions: [c],
    );
  }
}
