import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap save on the filter screen
Future<void> iTapSaveOnTheFilterScreen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('edit-filter-save')));
  await tester.pumpAndSettle();
}
