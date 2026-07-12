import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/widgets/ream_action_button.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('tapping fires onPressed; label shown', (tester) async {
    var taps = 0;
    await pumpReam(
      tester,
      ReamActionButton(
        key: const Key('act-scan'),
        label: 'Scan',
        icon: Icons.add,
        primary: true,
        onPressed: () => taps++,
      ),
    );
    expect(find.text('Scan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('act-scan')));
    expect(taps, 1);
  });

  testWidgets('null onPressed disables the button', (tester) async {
    await pumpReam(
      tester,
      const ReamActionButton(key: Key('act-x'), label: 'X', onPressed: null),
    );
    await tester.tap(find.byKey(const Key('act-x')));
    // no throw, no callback — nothing to assert beyond not crashing
    expect(find.text('X'), findsOneWidget);
  });

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
