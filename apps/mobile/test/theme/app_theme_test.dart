import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';

void main() {
  test('light theme carries AppColors + paper scaffold + Figtree', () {
    final t = AppTheme.light();
    expect(t.extension<AppColors>(), AppColors.light);
    expect(t.scaffoldBackgroundColor, AppColors.light.paper);
    expect(t.textTheme.titleLarge!.fontFamily, 'Figtree');
    expect(t.brightness, Brightness.light);
  });
  test('dark theme carries dark tokens', () {
    expect(AppTheme.dark().extension<AppColors>(), AppColors.dark);
  });
}
