import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the document disclaims all warranties
Future<void> theDocumentDisclaimsAllWarranties(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('legal-section-no-warranty')),
    300,
  );
  expect(find.byKey(const Key('legal-section-no-warranty')), findsOneWidget);
  expect(find.textContaining('as is'), findsWidgets);
}
