import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I do not see the print action
Future<void> iDoNotSeeThePrintAction(WidgetTester tester) async {
  expect(find.byKey(const Key('page-viewer-print')), findsNothing);
  // The share sheet is really open — a still-enabled action is present.
  expect(find.byKey(const Key('page-viewer-export')), findsOneWidget);
}
