import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the first document
Future<void> iOpenTheFirstDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-tile-1')));
  await tester.pumpAndSettle();
  // The viewer is open (its delete action is present). The seeded document has
  // no image file on disk, so the page degrades to the broken-image placeholder
  // on-device — not a hang.
  expect(find.byKey(const Key('page-viewer-delete')), findsOneWidget);
}
