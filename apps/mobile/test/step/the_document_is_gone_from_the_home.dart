import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the document is gone from the home
Future<void> theDocumentIsGoneFromTheHome(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // Back on the home, and the only document is gone.
  expect(find.text('Documents'), findsOneWidget);
  expect(find.byKey(const Key('document-tile-1')), findsNothing);
}
