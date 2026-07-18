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
}
