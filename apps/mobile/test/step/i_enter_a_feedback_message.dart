import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I enter a feedback message
Future<void> iEnterAFeedbackMessage(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('feedback-message')),
    'The export button crashes the app',
  );
  await tester.pump();
}
