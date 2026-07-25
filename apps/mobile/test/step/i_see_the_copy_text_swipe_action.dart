import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the copy text swipe action
Future<void> iSeeTheCopyTextSwipeAction(WidgetTester tester) async {
  expect(find.byKey(const Key('document-slide-copytext-1')), findsOneWidget);
}
