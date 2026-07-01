import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I search for {'invoice'}
Future<void> iSearchFor(WidgetTester tester, String query) async {
  // Open search if not already open.
  final searchIcon = find.byKey(const Key('documents-search'));
  if (searchIcon.evaluate().isNotEmpty) {
    await tester.tap(searchIcon);
    await tester.pumpAndSettle();
  }
  await tester.enterText(
      find.byKey(const Key('documents-search-field')), query);
  await tester.pumpAndSettle();
}
