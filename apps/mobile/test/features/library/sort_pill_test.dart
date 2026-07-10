import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_sort.dart';
import 'package:mobile/features/library/widgets/sort_pill.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('shows active criterion and selects from menu', (tester) async {
    SortCriterion? picked;
    await pumpReam(
      tester,
      SortPill(
        sort: DocumentSort.initial,
        onCriterionSelected: (c) => picked = c,
      ),
    );
    // DocumentSort.initial == (SortCriterion.created, desc)
    expect(find.text('Created'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sort-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-option-name')));
    await tester.pumpAndSettle();
    expect(picked, SortCriterion.name);
  });
}
