import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the print confirmation
Future<void> iSeeThePrintConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Sent to printer'), findsOneWidget);
}
