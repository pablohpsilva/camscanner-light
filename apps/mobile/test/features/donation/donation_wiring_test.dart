import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';

import '../../support/localized_app.dart';

void main() {
  testWidgets('Android body is Ko-fi/BTC and builds no tip jar', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        localizedTestApp(
          home: const DonationScreen(
            kofiUrl: 'https://ko-fi.com/x',
            bitcoinAddress: 'bc1qexample',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('donation-kofi-button')), findsOneWidget);
      expect(find.byKey(const Key('tip-button-tip_small')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
