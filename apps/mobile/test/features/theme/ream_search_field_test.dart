import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/widgets/ream_search_field.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('typing calls onChanged; hint shown', (tester) async {
    final controller = TextEditingController();
    String? last;
    await pumpReam(
      tester,
      ReamSearchField(controller: controller, onChanged: (v) => last = v),
    );
    expect(find.text('Search titles & text inside pages'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('documents-search-field')),
      'lease',
    );
    expect(last, 'lease');
  });

  testWidgets(
    'clear button is reactive: hidden initially, shows on text, clears on tap',
    (tester) async {
      final controller = TextEditingController();
      final changed = <String>[];
      await pumpReam(
        tester,
        ReamSearchField(controller: controller, onChanged: changed.add),
      );

      // Initially no clear button.
      expect(find.byKey(const Key('documents-search-clear')), findsNothing);

      // Type something → clear button appears.
      await tester.enterText(
        find.byKey(const Key('documents-search-field')),
        'x',
      );
      await tester.pump();
      expect(find.byKey(const Key('documents-search-clear')), findsOneWidget);

      // Tap clear → field is empty and onChanged('') fired and button gone.
      await tester.tap(find.byKey(const Key('documents-search-clear')));
      await tester.pump();
      expect(controller.text, '');
      expect(changed.last, '');
      expect(find.byKey(const Key('documents-search-clear')), findsNothing);
    },
  );
}
