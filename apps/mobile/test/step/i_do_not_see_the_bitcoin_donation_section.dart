import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I do not see the Bitcoin donation section
Future<void> iDoNotSeeTheBitcoinDonationSection(WidgetTester tester) async {
  expect(find.byKey(const Key('donation-bitcoin-section')), findsNothing);
}
