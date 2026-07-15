import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_availability.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('donations are unavailable on iOS (App Store guideline 3.1.1)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(donationsAvailable, isFalse);
  });

  test('donations are available on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(donationsAvailable, isTrue);
  });
}
