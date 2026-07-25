import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I swipe the first document left
Future<void> iSwipeTheFirstDocumentLeft(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const Key('document-slidable-1')),
    const Offset(-600, 0),
  );
  await tester.pumpAndSettle();
}
