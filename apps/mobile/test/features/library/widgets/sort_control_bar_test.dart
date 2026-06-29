import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_sort.dart';
import 'package:mobile/features/library/widgets/sort_control_bar.dart';

void main() {
  Future<void> pumpBar(WidgetTester tester, DocumentSort sort,
      {void Function(SortCriterion)? onTap}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SortControlBar(
          sort: sort,
          onCriterionTapped: onTap ?? (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the bar and three chips by key', (tester) async {
    await pumpBar(tester, DocumentSort.initial);
    expect(find.byKey(const Key('sort-control-bar')), findsOneWidget);
    expect(find.byKey(const Key('sort-chip-name')), findsOneWidget);
    expect(find.byKey(const Key('sort-chip-created')), findsOneWidget);
    expect(find.byKey(const Key('sort-chip-modified')), findsOneWidget);
  });

  testWidgets('active chip is selected; others are not', (tester) async {
    await pumpBar(tester,
        const DocumentSort(SortCriterion.name, SortDirection.asc));
    ChoiceChip chip(String key) =>
        tester.widget<ChoiceChip>(find.byKey(Key(key)));
    expect(chip('sort-chip-name').selected, isTrue);
    expect(chip('sort-chip-created').selected, isFalse);
    expect(chip('sort-chip-modified').selected, isFalse);
  });

  testWidgets('shows the desc arrow by key for the initial sort',
      (tester) async {
    await pumpBar(tester, DocumentSort.initial); // created, desc
    expect(find.byKey(const Key('sort-direction-desc')), findsOneWidget);
    expect(find.byKey(const Key('sort-direction-asc')), findsNothing);
  });

  testWidgets('shows the asc arrow by key when direction is asc',
      (tester) async {
    await pumpBar(tester,
        const DocumentSort(SortCriterion.name, SortDirection.asc));
    expect(find.byKey(const Key('sort-direction-asc')), findsOneWidget);
    expect(find.byKey(const Key('sort-direction-desc')), findsNothing);
  });

  testWidgets('tapping a chip fires onCriterionTapped with that criterion',
      (tester) async {
    final taps = <SortCriterion>[];
    await pumpBar(tester, DocumentSort.initial, onTap: taps.add);
    await tester.tap(find.byKey(const Key('sort-chip-name')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-chip-modified')));
    await tester.pumpAndSettle();
    expect(taps, [SortCriterion.name, SortCriterion.modified]);
  });
}
