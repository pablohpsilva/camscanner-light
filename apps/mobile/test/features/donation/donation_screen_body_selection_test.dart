import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';

import '../../support/fake_tip_jar_service.dart';
import '../../support/localized_app.dart';

void main() {
  testWidgets('tipJarMode true renders tip buttons, not Ko-fi', (tester) async {
    final fake = FakeTipJarService();
    await tester.pumpWidget(
      localizedTestApp(
        home: DonationScreen(
          tipJarMode: true,
          createTipJar: () => fake,
          kofiUrl: 'https://ko-fi.com/x',
          bitcoinAddress: 'bc1qexample',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-button-tip_small')), findsOneWidget);
    expect(find.byKey(const Key('donation-kofi-button')), findsNothing);
    fake.dispose();
  });

  testWidgets('tipJarMode false renders Ko-fi/BTC, not tips', (tester) async {
    await tester.pumpWidget(
      localizedTestApp(
        home: const DonationScreen(
          tipJarMode: false,
          kofiUrl: 'https://ko-fi.com/x',
          bitcoinAddress: 'bc1qexample',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('donation-kofi-button')), findsOneWidget);
    expect(find.byKey(const Key('tip-button-tip_small')), findsNothing);
  });

  testWidgets(
    'iOS tip jar with iosBtcDonation renders BTC after the tip buttons, '
    'no Ko-fi',
    (tester) async {
      final fake = FakeTipJarService();
      await tester.pumpWidget(
        localizedTestApp(
          home: DonationScreen(
            tipJarMode: true,
            iosBtcDonation: true,
            createTipJar: () => fake,
            kofiUrl: 'https://ko-fi.com/x',
            bitcoinAddress: 'bc1qexample',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tip buttons present, Ko-fi stays off on iOS.
      expect(find.byKey(const Key('tip-button-tip_small')), findsOneWidget);
      expect(find.byKey(const Key('donation-kofi-button')), findsNothing);

      // BTC section present and rendered AFTER the tip buttons.
      final section = find.byKey(const Key('donation-bitcoin-section'));
      expect(section, findsOneWidget);
      expect(find.byKey(const Key('donation-bitcoin-copy')), findsOneWidget);
      final tipY = tester
          .getTopLeft(find.byKey(const Key('tip-button-tip_small')))
          .dy;
      final btcY = tester.getTopLeft(section).dy;
      expect(btcY, greaterThan(tipY));

      fake.dispose();
    },
  );

  testWidgets('iOS tip jar with iosBtcDonation false hides BTC', (
    tester,
  ) async {
    final fake = FakeTipJarService();
    await tester.pumpWidget(
      localizedTestApp(
        home: DonationScreen(
          tipJarMode: true,
          iosBtcDonation: false,
          createTipJar: () => fake,
          bitcoinAddress: 'bc1qexample',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-button-tip_small')), findsOneWidget);
    expect(find.byKey(const Key('donation-bitcoin-section')), findsNothing);
    fake.dispose();
  });

  testWidgets('iOS tip jar with empty bitcoin address hides BTC', (
    tester,
  ) async {
    final fake = FakeTipJarService();
    await tester.pumpWidget(
      localizedTestApp(
        home: DonationScreen(
          tipJarMode: true,
          iosBtcDonation: true,
          createTipJar: () => fake,
          bitcoinAddress: '',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-button-tip_small')), findsOneWidget);
    expect(find.byKey(const Key('donation-bitcoin-section')), findsNothing);
    fake.dispose();
  });

  testWidgets(
    'Android body (tipJarMode false) is unchanged by iosBtcDonation',
    (tester) async {
      await tester.pumpWidget(
        localizedTestApp(
          home: const DonationScreen(
            tipJarMode: false,
            iosBtcDonation: false,
            kofiUrl: 'https://ko-fi.com/x',
            bitcoinAddress: 'bc1qexample',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // iosBtcDonation must not gate the Android Ko-fi/BTC body.
      expect(find.byKey(const Key('donation-kofi-button')), findsOneWidget);
      expect(find.byKey(const Key('donation-bitcoin-section')), findsOneWidget);
      expect(find.byKey(const Key('tip-button-tip_small')), findsNothing);
    },
  );
}
