import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_banner.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ReamTheme.light(),
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

  testWidgets('home screen hides the donation banner on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpHome(tester);
      expect(find.byType(DonationBanner), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'with the banner hidden on iOS, the action row clears the bottom inset',
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
