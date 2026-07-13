import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the feedback back button
Future<void> iTapTheFeedbackBackButton(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('ream-back')));
  await tester.pumpAndSettle();
}
