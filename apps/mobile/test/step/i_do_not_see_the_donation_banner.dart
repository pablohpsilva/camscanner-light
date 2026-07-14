import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I do not see the donation banner
Future<void> iDoNotSeeTheDonationBanner(WidgetTester tester) async {
  expect(find.byKey(const Key('donation-banner')), findsNothing);
}
