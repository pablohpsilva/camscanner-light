import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the delete swipe action
Future<void> iTapTheDeleteSwipeAction(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-slide-delete-1')));
  await tester.pumpAndSettle();
}
