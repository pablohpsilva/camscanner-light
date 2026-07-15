import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: tapping the donation banner opens the donation disclaimer where available
///
/// App Store guideline 3.1.1: on iOS the banner is absent (asserted by the
/// previous step), so there is nothing to tap. Elsewhere, tapping it must
/// still surface the store-safety disclaimer: donations grant no benefits.
Future<void> tappingTheDonationBannerOpensTheDonationDisclaimerWhereAvailable(
  WidgetTester tester,
) async {
  if (Platform.isIOS) {
    return;
  }

  await tester.tap(find.byKey(const Key('donation-banner')));
  await tester.pumpAndSettle();

  expect(
    find.textContaining('no features, benefits, or content'),
    findsOneWidget,
  );
}
