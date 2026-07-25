import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/widgets/app_action_button.dart';
import '../../support/app_pump.dart';

void main() {
  testWidgets('tapping fires onPressed; label shown', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      AppActionButton(
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
    await pumpApp(
      tester,
      const AppActionButton(key: Key('act-x'), label: 'X', onPressed: null),
    );
    await tester.tap(find.byKey(const Key('act-x')));
    // no throw, no callback — nothing to assert beyond not crashing
    expect(find.text('X'), findsOneWidget);
  });

  testWidgets('primary honours a custom fillColor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AppActionButton(
            label: 'Send report',
            primary: true,
            fillColor: AppColors.light.ink,
            onPressed: () {},
          ),
        ),
      ),
    );
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(AppActionButton),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, AppColors.light.ink);
  });

  testWidgets('primary label is white when fill is dark (light theme ink)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => AppActionButton(
              label: 'Send report',
              primary: true,
              fillColor: context.appColors.ink,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    final style = tester.widget<Text>(find.text('Send report')).style!;
    expect(style.color, Colors.white);
  });

  testWidgets(
    'primary label is dark on-fill color when fill is light (dark theme ink)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => AppActionButton(
                label: 'Send report',
                primary: true,
                fillColor: context.appColors.ink,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      final style = tester.widget<Text>(find.text('Send report')).style!;
      expect(style.color, const Color(0xFF201C16));
    },
  );
}
