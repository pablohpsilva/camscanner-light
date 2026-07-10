import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/features/library/widgets/editor_toolbar_button.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('renders icon+label and fires onPressed', (tester) async {
    var taps = 0;
    await pumpReam(
      tester,
      EditorToolbarButton(
        key: const Key('tb-rotate'),
        icon: Icons.rotate_right,
        label: 'Rotate',
        onPressed: () => taps++,
      ),
      theme: ReamTheme.dark(),
    );
    expect(find.text('Rotate'), findsOneWidget);
    expect(find.byIcon(Icons.rotate_right), findsOneWidget);
    await tester.tap(find.byKey(const Key('tb-rotate')));
    expect(taps, 1);
  });

  testWidgets('danger uses deleteRed', (tester) async {
    await pumpReam(
      tester,
      EditorToolbarButton(
        icon: Icons.delete_outline,
        label: 'Delete',
        danger: true,
        onPressed: () {},
      ),
      theme: ReamTheme.dark(),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.delete_outline));
    expect(icon.color, ReamColors.dark.deleteRed);
  });

  testWidgets('null onPressed dims and does not fire', (tester) async {
    await pumpReam(
      tester,
      const EditorToolbarButton(
        key: Key('tb-x'),
        icon: Icons.crop,
        label: 'Crop',
        onPressed: null,
      ),
      theme: ReamTheme.dark(),
    );
    await tester.tap(find.byKey(const Key('tb-x')));
    expect(find.text('Crop'), findsOneWidget); // no throw
    final icon = tester.widget<Icon>(find.byIcon(Icons.crop));
    expect(icon.color, ReamColors.dark.muted);
  });
}
