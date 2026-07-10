import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the text view
Future<void> iOpenTheTextView(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-view-text')));
  await tester.pumpAndSettle();
}
