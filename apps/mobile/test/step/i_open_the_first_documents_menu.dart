import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the first document's menu
Future<void> iOpenTheFirstDocumentsMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-menu-1')));
  await tester.pumpAndSettle();
}
