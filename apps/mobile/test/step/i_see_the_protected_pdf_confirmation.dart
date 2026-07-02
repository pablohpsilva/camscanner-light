import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the protected PDF confirmation
Future<void> iSeeTheProtectedPdfConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Protected PDF ready'), findsOneWidget);
}
