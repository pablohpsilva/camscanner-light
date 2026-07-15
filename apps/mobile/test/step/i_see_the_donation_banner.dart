import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the donation banner
Future<void> iSeeTheDonationBanner(WidgetTester tester) async {
  expect(find.byKey(const Key('donation-banner')), findsOneWidget);
}
