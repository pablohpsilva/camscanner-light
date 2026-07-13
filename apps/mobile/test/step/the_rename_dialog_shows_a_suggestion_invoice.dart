import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the rename dialog shows a suggestion "INVOICE"
Future<void> theRenameDialogShowsASuggestionInvoice(WidgetTester tester) async {
  expect(find.byKey(const Key('rename-suggestion')), findsOneWidget);
  expect(find.text('INVOICE'), findsOneWidget);
}
