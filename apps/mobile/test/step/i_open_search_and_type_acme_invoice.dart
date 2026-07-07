import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open search and type "acme invoice"
Future<void> iOpenSearchAndTypeAcmeInvoice(WidgetTester tester) async {
  // Open search if the field isn't already shown (mirrors i_search_for).
  final searchIcon = find.byKey(const Key('documents-search'));
  if (searchIcon.evaluate().isNotEmpty) {
    await tester.tap(searchIcon);
    await tester.pumpAndSettle();
  }
  await tester.enterText(
      find.byKey(const Key('documents-search-field')), 'acme invoice');
  await tester.pumpAndSettle();
}
