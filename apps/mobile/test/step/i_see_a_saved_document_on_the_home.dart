import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see a saved document on the home
Future<void> iSeeASavedDocumentOnTheHome(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.text('Documents'), findsOneWidget);
  expect(find.byKey(const Key('documents-list')), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(const Key('documents-list')),
      matching: find.textContaining('Scan '),
    ),
    findsWidgets,
  );
}
