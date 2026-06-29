import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the rename menu for the first document
Future<void> iOpenTheRenameMenuForTheFirstDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-menu-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('document-rename-1')));
  await tester.pumpAndSettle();
}
