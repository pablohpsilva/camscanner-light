import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the filter button
Future<void> iTapTheFilterButton(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-filter')));
  await tester.pumpAndSettle();
}
