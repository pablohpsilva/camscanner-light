import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';

import '../support/fake_tip_jar_service.dart';
import '../support/localized_app.dart';

/// Usage: the iOS tip jar with Bitcoin disabled is shown
Future<void> theIosTipJarWithBitcoinDisabledIsShown(WidgetTester tester) async {
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
}
