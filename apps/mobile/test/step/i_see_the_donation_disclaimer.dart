import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the donation disclaimer
Future<void> iSeeTheDonationDisclaimer(WidgetTester tester) async {
  // The store-safety disclaimer must be present: donations grant no benefits.
  expect(
    find.textContaining('no features, benefits, or content'),
    findsOneWidget,
  );
}
