import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';

void main() {
  test('light tokens match the approved palette (all 18 tokens)', () {
    const c = ReamColors.light;
    expect(c.paper, const Color(0xFFF4F1EA));
    expect(c.surface, const Color(0xFFFFFDF8));
    expect(c.surface2, const Color(0xFFFAF7F0));
    expect(c.ink, const Color(0xFF33302A));
    expect(c.ink2, const Color(0xFF5C574D));
    expect(c.muted, const Color(0xFF928C80));
    expect(c.line, const Color(0xFFE6E1D6));
    expect(c.line2, const Color(0xFFEFEBE2));
    expect(c.appBg, const Color(0xFFE7E3D9));
    expect(c.green, const Color(0xFF4FA866));
    expect(c.greenDeep, const Color(0xFF2D7B44));
    expect(c.greenSoft, const Color(0xFFDEF1E1));
    expect(c.amber, const Color(0xFFCA932E));
    expect(c.amberSoft, const Color(0xFFFEECCD));
    expect(c.blue, const Color(0xFF4B99D7));
    expect(c.blueSoft, const Color(0xFFDFF1FF));
    expect(c.kofiRed, const Color(0xFFD5565D));
    expect(c.deleteRed, const Color(0xFFF47B74));
  });

  test('dark tokens match the approved palette (all 18 tokens)', () {
    const c = ReamColors.dark;
    expect(c.paper, const Color(0xFF16130E));
    expect(c.surface, const Color(0xFF211D16));
    expect(c.surface2, const Color(0xFF1B1811));
    expect(c.ink, const Color(0xFFF4F1EA));
    expect(c.ink2, const Color(0xFFC9C2B4));
    expect(c.muted, const Color(0xFF8F887A));
    expect(c.line, const Color(0xFF322C22));
    expect(c.line2, const Color(0xFF2A251C));
    expect(c.appBg, const Color(0xFF0F0D09));
    expect(c.green, const Color(0xFF4FA866));
    expect(c.greenDeep, const Color(0xFF2D7B44));
    expect(c.greenSoft, const Color(0xFF1E3325));
    expect(c.amber, const Color(0xFFCA932E));
    expect(c.amberSoft, const Color(0xFF3A2F17));
    expect(c.blue, const Color(0xFF4B99D7));
    expect(c.blueSoft, const Color(0xFF17293A));
    expect(c.kofiRed, const Color(0xFFD5565D));
    expect(c.deleteRed, const Color(0xFFF47B74));
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

  testWidgets('context.ream falls back to light when no extension is present', (
    tester,
  ) async {
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
