// apps/mobile/integration_test/n1_donation_gate_device_test.dart
// On-device proof of the donation entry-point rules.
//
// HISTORY: this test used to assert that donation entry points were ABSENT on
// iOS, under App Store guideline 3.1.1. That stopped being true when v1.1.4
// added the IAP tip jar: `donationEntryPointsAvailable` is
// `donationsAvailable || tipJarAvailable`, so iOS now shows the banner and the
// Settings row too — what differs is the BODY behind them (tip consumables on
// iOS, Ko-fi/BTC on Android). The old assertion had gone stale and could only
// fail on an iPhone.
//
// It also pins the Bitcoin section as ALWAYS ON, including on iOS: that is no
// longer a build flag, so a device is the only place to prove the shipped
// default really renders.
//
// Run (the address comes from the gitignored donation_config.json):
//   flutter test integration_test/n1_donation_gate_device_test.dart \
//     -d <device-id> --dart-define-from-file=donation_config.json
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/donation/donation_config.dart';
import 'package:mobile/features/donation/donation_screen.dart';
import 'package:mobile/main.dart' as app;

import '../test/support/fake_tip_jar_service.dart';
import '../test/support/localized_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('donation entry points are present on this platform', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();

    // Both platforms: Android via Ko-fi/BTC, iOS via the tip jar.
    expect(find.byKey(const Key('donation-banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-support')), findsOneWidget);
  });

  testWidgets('the tip-jar body shows Bitcoin with no flag passed', (
    tester,
  ) async {
    // Guard rather than skip: a silent pass here would hide exactly the
    // regression this test exists to catch.
    expect(
      DonationConfig.bitcoinAddress,
      isNotEmpty,
      reason:
          'run with --dart-define-from-file=donation_config.json, '
          'otherwise the Bitcoin section legitimately hides and proves nothing',
    );

    final fake = FakeTipJarService();
    addTearDown(fake.dispose);

    // tipJarMode: true forces the iOS body on either platform. Crucially,
    // iosBtcDonation is NOT passed — this asserts the shipped DEFAULT.
    await tester.pumpWidget(
      localizedTestApp(
        home: DonationScreen(tipJarMode: true, createTipJar: () => fake),
      ),
    );
    await tester.pumpAndSettle();

    // TipJarBody nests its own Scrollable, so scrollUntilVisible must be told
    // which one to drive — otherwise it throws "Bad state: Too many elements".
    final section = find.byKey(const Key('donation-bitcoin-section'));
    await tester.scrollUntilVisible(
      section,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(section, findsOneWidget);
  });
}
