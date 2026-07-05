import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the message {'some text'}
Future<void> iSeeTheMessage(WidgetTester tester, String message) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text(message), findsOneWidget);
}
