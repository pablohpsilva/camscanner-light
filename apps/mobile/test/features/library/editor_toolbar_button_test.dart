import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/features/library/widgets/editor_toolbar_button.dart';
import '../../support/app_pump.dart';

void main() {
  testWidgets('renders icon+label and fires onPressed', (tester) async {
    var taps = 0;
    await pumpApp(
      tester,
      EditorToolbarButton(
        key: const Key('tb-rotate'),
        icon: Icons.rotate_right,
        label: 'Rotate',
        onPressed: () => taps++,
      ),
      theme: AppTheme.dark(),
    );
    expect(find.text('Rotate'), findsOneWidget);
    expect(find.byIcon(Icons.rotate_right), findsOneWidget);
    await tester.tap(find.byKey(const Key('tb-rotate')));
    expect(taps, 1);
  });

  testWidgets('danger uses deleteRed', (tester) async {
    await pumpApp(
      tester,
      EditorToolbarButton(
        icon: Icons.delete_outline,
        label: 'Delete',
        danger: true,
        onPressed: () {},
      ),
      theme: AppTheme.dark(),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.delete_outline));
    expect(icon.color, AppColors.dark.deleteRed);
  });

  testWidgets('null onPressed dims and does not fire', (tester) async {
    await pumpApp(
      tester,
      const EditorToolbarButton(
        key: Key('tb-x'),
        icon: Icons.crop,
        label: 'Crop',
        onPressed: null,
      ),
      theme: AppTheme.dark(),
    );
    await tester.tap(find.byKey(const Key('tb-x')));
    expect(find.text('Crop'), findsOneWidget); // no throw
    final icon = tester.widget<Icon>(find.byIcon(Icons.crop));
    expect(icon.color, AppColors.dark.muted);
  });
}
