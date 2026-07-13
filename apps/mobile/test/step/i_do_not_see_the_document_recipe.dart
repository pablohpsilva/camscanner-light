import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I do not see the document "Recipe"
Future<void> iDoNotSeeTheDocumentRecipe(WidgetTester tester) async {
  expect(
    find.descendant(
      of: find.byKey(const Key('documents-list')),
      matching: find.text('Recipe'),
    ),
    findsNothing,
  );
}
