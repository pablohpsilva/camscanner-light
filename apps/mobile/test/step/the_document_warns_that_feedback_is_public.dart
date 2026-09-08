import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the document warns that feedback is public
Future<void> theDocumentWarnsThatFeedbackIsPublic(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('legal-section-feedback')),
    300,
  );
  expect(find.byKey(const Key('legal-section-feedback')), findsOneWidget);
  expect(find.textContaining('public'), findsWidgets);
}
