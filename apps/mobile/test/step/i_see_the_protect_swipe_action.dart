import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the protect swipe action
Future<void> iSeeTheProtectSwipeAction(WidgetTester tester) async {
  expect(find.byKey(const Key('document-slide-protect-1')), findsOneWidget);
}
