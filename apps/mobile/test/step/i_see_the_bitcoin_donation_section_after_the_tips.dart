import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the Bitcoin donation section after the tips
Future<void> iSeeTheBitcoinDonationSectionAfterTheTips(
  WidgetTester tester,
) async {
  final section = find.byKey(const Key('donation-bitcoin-section'));
  expect(section, findsOneWidget);
  final tipY = tester
      .getTopLeft(find.byKey(const Key('tip-button-tip_small')))
      .dy;
  final btcY = tester.getTopLeft(section).dy;
  expect(btcY, greaterThan(tipY));
}
