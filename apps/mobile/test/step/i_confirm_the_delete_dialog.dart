import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I confirm the delete dialog
Future<void> iConfirmTheDeleteDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-delete-confirm')));
  await tester.pumpAndSettle();
}
