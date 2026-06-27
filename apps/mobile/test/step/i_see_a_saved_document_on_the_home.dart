import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see a saved document on the home
Future<void> iSeeASavedDocumentOnTheHome(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.widgetWithText(AppBar, 'Documents'), findsOneWidget);
  expect(find.byKey(const Key('documents-list')), findsOneWidget);
  expect(find.textContaining('Scan '), findsWidgets);
}
