import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/widgets/ream_action_button.dart';

void main() {
  testWidgets('primary honours a custom fillColor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: Scaffold(
          body: ReamActionButton(
            label: 'Send report',
            primary: true,
            fillColor: ReamColors.light.ink,
            onPressed: () {},
          ),
        ),
      ),
    );
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(ReamActionButton),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, ReamColors.light.ink);
  });
}
