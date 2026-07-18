import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_availability.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('tipJarAvailable is true only on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(tipJarAvailable, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(tipJarAvailable, isFalse);
  });

  test('donationsAvailable is true only on Android (Ko-fi/BTC)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(donationsAvailable, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(donationsAvailable, isTrue);
  });

  test('donationEntryPointsAvailable is true on both platforms', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(donationEntryPointsAvailable, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(donationEntryPointsAvailable, isTrue);
  });
}
