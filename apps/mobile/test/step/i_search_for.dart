import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I search for {'invoice'}
Future<void> iSearchFor(WidgetTester tester, String query) async {
  // The Ream search field is always visible in the header — no icon to open.
  await tester.enterText(
    find.byKey(const Key('documents-search-field')),
    query,
  );
  await tester.pumpAndSettle();
}
