import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the document says I am responsible for what I scan
Future<void> theDocumentSaysIAmResponsibleForWhatIScan(
  WidgetTester tester,
) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('legal-section-your-content')),
    300,
  );
  expect(find.byKey(const Key('legal-section-your-content')), findsOneWidget);
  expect(find.textContaining('solely responsible'), findsWidgets);
}
