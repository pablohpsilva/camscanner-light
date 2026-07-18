import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_banner.dart';
import 'package:mobile/features/library/home_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';
import '../../support/localized_app.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    localizedTestApp(
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(FakeDocumentRepository()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home screen shows the donation banner on Android', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pumpHome(tester);
      expect(find.byType(DonationBanner), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('home screen shows the donation banner on iOS', (tester) async {
    // App Store guideline 3.1.1: iOS no longer hides every donation entry
    // point — it shows the IAP tip jar banner instead of the Ko-fi/BTC one.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpHome(tester);
      expect(find.byType(DonationBanner), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'with the banner shown on iOS, the action row uses the banner-present gap',
    (tester) async {
      // Simulate an iPhone home-indicator inset (34 logical px). Without the
      // donation banner absorbing it, the Scan/ID card/Import row must clear
      // the inset itself with a visible gap, or the buttons land in the
      // gesture area.
      const inset = 34.0;
      tester.view.padding = FakeViewPadding(
        bottom: inset * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetPadding);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _pumpHome(tester);
        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        for (final key in const ['home-scan', 'home-scan-id', 'home-import']) {
          final bottom = tester.getBottomLeft(find.byKey(Key(key))).dy;
          expect(
            screenHeight - bottom,
            greaterThanOrEqualTo(inset + 8),
            reason: '$key must sit at least 8px above the home indicator',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'on iOS without a bottom inset the action row still keeps a visible gap',
    (tester) async {
      // Home-button iPhones (e.g. SE) have no home-indicator inset; the row
      // still needs a real gap to the screen edge once the banner is gone.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _pumpHome(tester);
        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        for (final key in const ['home-scan', 'home-scan-id', 'home-import']) {
          final bottom = tester.getBottomLeft(find.byKey(Key(key))).dy;
          expect(
            screenHeight - bottom,
            greaterThanOrEqualTo(16),
            reason: '$key must keep a visible gap to the screen bottom',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
