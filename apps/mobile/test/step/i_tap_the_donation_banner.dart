import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the donation banner
Future<void> iTapTheDonationBanner(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('donation-banner')));
  await tester.pumpAndSettle();
}
