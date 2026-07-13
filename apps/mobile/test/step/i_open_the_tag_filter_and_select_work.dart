import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the tag filter and select "Work"
///
/// Opens the tag-filter sheet, taps the "Work" filter chip, then confirms
/// with Done.
Future<void> iOpenTheTagFilterAndSelectWork(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tag-filter')));
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(FilterChip, 'Work'));
  await tester.pump();

  await tester.tap(find.byKey(const Key('tag-filter-done')));
  await tester.pumpAndSettle();
}
