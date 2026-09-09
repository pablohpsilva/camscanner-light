import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';

import '../../support/fake_tip_jar_service.dart';
import '../../support/localized_app.dart';

/// The iOS Bitcoin section is ALWAYS on — it is no longer a build flag.
///
/// These tests are meaningful only when the suite is run with the old kill
/// switch forced off, which is what proves the switch is really gone:
///
///   flutter test --dart-define=FEATURE_IOS_BTC_DONATION=false \
///     test/features/donation/ios_btc_always_on_test.dart
///
/// Under that command they FAIL while `DonationScreen` still reads
/// `bool.fromEnvironment('FEATURE_IOS_BTC_DONATION')`, and pass once the
/// default is a plain `true`. Running them without the define proves nothing,
/// so the CI/dev invocation must keep the define.
void main() {
  test('the constructor default ignores FEATURE_IOS_BTC_DONATION=false', () {
    expect(
      const DonationScreen().iosBtcDonation,
      isTrue,
      reason: 'iosBtcDonation must be unconditionally true, not build-flagged',
    );
  });

  testWidgets('the iOS tip jar shows Bitcoin even with the old flag off', (
    tester,
  ) async {
    final fake = FakeTipJarService();
    await tester.pumpWidget(
      localizedTestApp(
        home: DonationScreen(
          tipJarMode: true,
          createTipJar: () => fake,
          bitcoinAddress: 'bc1qexample',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('donation-bitcoin-section')), findsOneWidget);
    fake.dispose();
  });
}
