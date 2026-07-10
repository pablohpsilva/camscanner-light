import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open search and type "acme invoice"
Future<void> iOpenSearchAndTypeAcmeInvoice(WidgetTester tester) async {
  // The Ream search field is always visible in the header (mirrors i_search_for).
  await tester.enterText(
    find.byKey(const Key('documents-search-field')),
    'acme invoice',
  );
  await tester.pumpAndSettle();
}
