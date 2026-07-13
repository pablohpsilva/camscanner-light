import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the rename field shows "INVOICE"
Future<void> theRenameFieldShowsInvoice(WidgetTester tester) async {
  final field = tester.widget<TextField>(find.byKey(const Key('rename-field')));
  expect(field.controller!.text, 'INVOICE');
}
