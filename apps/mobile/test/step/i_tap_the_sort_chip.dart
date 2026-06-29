import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Taps the sort chip for [criterion] (e.g. 'name', 'created', 'modified').
Future<void> iTapTheSortChip(WidgetTester tester, String criterion) async {
  await tester.tap(find.byKey(Key('sort-chip-$criterion')));
  await tester.pumpAndSettle();
}
