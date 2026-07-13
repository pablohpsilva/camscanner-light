import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap send feedback
Future<void> iTapSendFeedback(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('feedback-submit')));
  await tester.pumpAndSettle();
}
