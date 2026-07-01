import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the document has 1 page
///
/// The 2-page fixture had pages at positions 1 and 2. Deleting the current
/// (first) page renumbers the survivor to position 1, so the PageView now
/// shows 'page-viewer-page-1' and no longer has 'page-viewer-page-2'. These
/// keys are set by PageViewerScreen._buildPages, keyed by page position.
Future<void> theDocumentHas1Page(WidgetTester tester) async {
  expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);
  expect(find.byKey(const Key('page-viewer-page-2')), findsNothing);
}
