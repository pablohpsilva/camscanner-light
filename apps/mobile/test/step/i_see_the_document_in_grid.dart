import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the document in grid
Future<void> iSeeTheDocumentInGrid(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('documents-grid')), findsOneWidget);
  expect(
    find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey &&
          (w.key as ValueKey).value.toString().startsWith('document-card-'),
    ),
    findsWidgets,
  );
}
