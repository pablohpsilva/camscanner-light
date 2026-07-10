import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';

void main() {
  test('light tokens match the approved palette', () {
    const c = ReamColors.light;
    expect(c.paper, const Color(0xFFF4F1EA));
    expect(c.green, const Color(0xFF4FA866));
    expect(c.greenDeep, const Color(0xFF2D7B44));
    expect(c.amberSoft, const Color(0xFFFEECCD));
  });

  test('lerp interpolates halfway', () {
    final mid = ReamColors.light.lerp(ReamColors.dark, 0.5);
    expect(mid, isA<ReamColors>());
  });

  testWidgets('context.ream resolves from a themed context', (tester) async {
    late ReamColors seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [ReamColors.light]),
        home: Builder(
          builder: (context) {
            seen = context.ream;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.paper, const Color(0xFFF4F1EA));
  });

  testWidgets('context.ream falls back to light when no extension is present',
      (tester) async {
    late ReamColors seen;
    await tester.pumpWidget(
      MaterialApp(
        // No ReamColors extension registered (bare theme) — as in isolated
        // widget tests. context.ream must degrade to light, not crash.
        home: Builder(
          builder: (context) {
            seen = context.ream;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.paper, ReamColors.light.paper);
    expect(seen.green, ReamColors.light.green);
  });
}
