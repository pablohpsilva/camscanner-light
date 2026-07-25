import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I cancel the delete dialog
Future<void> iCancelTheDeleteDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-delete-cancel')));
  await tester.pumpAndSettle();
}
