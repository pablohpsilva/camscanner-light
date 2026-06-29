import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I rename the document to {'New Name'}
Future<void> iRenameTheDocumentTo(WidgetTester tester, String name) async {
  // enterText replaces the pre-filled name (no manual clear needed).
  await tester.enterText(find.byKey(const Key('rename-field')), name);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('rename-save')));
  await tester.pumpAndSettle();
}
