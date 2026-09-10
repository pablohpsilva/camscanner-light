import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_availability.dart';

/// Usage: the donation banner matches this platform's donation availability
///
/// The home banner is gated on [donationEntryPointsAvailable] (see
/// HomeScreen), so this asserts against that SAME predicate rather than
/// restating a platform rule. Both platforms now have a store-compliant path —
/// Ko-fi/Bitcoin on Android, the IAP tip jar on iOS (guideline 3.1.1) — and the
/// destination screen picks the right body.
///
/// It used to hardcode `Platform.isIOS ? findsNothing : findsOneWidget`, which
/// was correct when written (2026-07-14) and silently wrong four days later
/// when `c247e0d` started showing entry points on iOS via the tipJarAvailable
/// gate. Deriving the expectation from the production getter is what stops that
/// happening again: if the gate changes, this step follows it instead of
/// failing on a phone that merely runs the other platform.
Future<void> theDonationBannerMatchesThisPlatformsDonationAvailability(
  WidgetTester tester,
) async {
  expect(
    find.byKey(const Key('donation-banner')),
    donationEntryPointsAvailable ? findsOneWidget : findsNothing,
    reason:
        'banner visibility must track donationEntryPointsAvailable '
        '(= $donationEntryPointsAvailable here)',
  );
}
