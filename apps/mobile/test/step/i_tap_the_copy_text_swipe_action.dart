import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the copy text swipe action
Future<void> iTapTheCopyTextSwipeAction(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-slide-copytext-1')));
  await tester.pumpAndSettle();
}
