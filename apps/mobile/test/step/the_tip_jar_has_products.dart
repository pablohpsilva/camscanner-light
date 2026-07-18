import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';

import '../support/fake_tip_jar_service.dart';
import '../support/localized_app.dart';

/// Usage: the tip jar has products
Future<void> theTipJarHasProducts(WidgetTester tester) async {
  final fake = FakeTipJarService();
  await tester.pumpWidget(
    localizedTestApp(
      home: DonationScreen(tipJarMode: true, createTipJar: () => fake),
    ),
  );
  await tester.pumpAndSettle();
}
