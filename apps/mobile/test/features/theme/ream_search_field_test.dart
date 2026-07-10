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
}
