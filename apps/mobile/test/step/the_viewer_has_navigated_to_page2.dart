import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the viewer has navigated to page 2
/// Verifies that the PageView has animated to page index 1 (0-based),
/// which shows the page at position 2. Key: 'page-viewer-page-2'.
Future<void> theViewerHasNavigatedToPage2(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('page-viewer-page-2')), findsOneWidget);
}
