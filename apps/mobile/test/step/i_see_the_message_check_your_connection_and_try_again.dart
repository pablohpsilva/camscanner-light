import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the message check your connection and try again
///
/// The offline result copy (`l10n.feedbackOffline`, en: "Check your connection
/// and try again.") shown in a SnackBar after a stalled submit times out.
Future<void> iSeeTheMessageCheckYourConnectionAndTryAgain(
  WidgetTester tester,
) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Check your connection and try again.'), findsOneWidget);
}
