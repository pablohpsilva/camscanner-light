import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the donation banner matches this platform's donation availability
///
/// App Store guideline 3.1.1: donation UI must be hidden on iOS/iPadOS. The
/// home banner is unconditionally absent on iOS and present elsewhere.
Future<void> theDonationBannerMatchesThisPlatformsDonationAvailability(
  WidgetTester tester,
) async {
  final matcher = Platform.isIOS ? findsNothing : findsOneWidget;
  expect(find.byKey(const Key('donation-banner')), matcher);
}
