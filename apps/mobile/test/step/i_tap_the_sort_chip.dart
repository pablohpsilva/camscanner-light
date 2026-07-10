import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Selects [criterion] (e.g. 'name', 'created', 'modified') via the Ream sort
/// pill: open the pill, then tap its option.
Future<void> iTapTheSortChip(WidgetTester tester, String criterion) async {
  await tester.tap(find.byKey(const Key('sort-pill')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('sort-option-$criterion')));
  await tester.pumpAndSettle();
}
