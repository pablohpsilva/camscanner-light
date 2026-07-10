import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_typography.dart';

void main() {
  test('UI text theme uses Figtree', () {
    final t = ReamTypography.textTheme(const Color(0xFF33302A));
    expect(t.titleLarge!.fontFamily, 'Figtree');
    expect(t.bodyMedium!.color, const Color(0xFF33302A));
  });
  test('mono uses IBM Plex Mono', () {
    final s = ReamTypography.mono(size: 11, weight: FontWeight.w600);
    expect(s.fontFamily, 'IBMPlexMono');
    expect(s.fontWeight, FontWeight.w600);
    expect(s.fontSize, 11);
  });
}
