import 'package:flutter_test/flutter_test.dart';
import '../support/app_l10n.dart';

/// Usage: I see the message please check your message and try again
Future<void> iSeeTheMessagePleaseCheckYourMessageAndTryAgain(
  WidgetTester tester,
) async {
  expect(find.text(l10nOf(tester).feedbackInvalid), findsOneWidget);
}
