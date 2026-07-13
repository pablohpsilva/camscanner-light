import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the message please check your message and try again
Future<void> iSeeTheMessagePleaseCheckYourMessageAndTryAgain(
  WidgetTester tester,
) async {
  expect(find.text('Please check your message and try again.'), findsOneWidget);
}
