import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the document "Invoice"
Future<void> iSeeTheDocumentInvoice(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(
    find.descendant(
      of: find.byKey(const Key('documents-list')),
      matching: find.text('Invoice'),
    ),
    findsOneWidget,
  );
}
