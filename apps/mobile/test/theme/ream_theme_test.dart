import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';

void main() {
  test('light theme carries ReamColors + paper scaffold + Figtree', () {
    final t = ReamTheme.light();
    expect(t.extension<ReamColors>(), ReamColors.light);
    expect(t.scaffoldBackgroundColor, ReamColors.light.paper);
    expect(t.textTheme.titleLarge!.fontFamily, 'Figtree');
    expect(t.brightness, Brightness.light);
  });
  test('dark theme carries dark tokens', () {
    expect(ReamTheme.dark().extension<ReamColors>(), ReamColors.dark);
  });
}
