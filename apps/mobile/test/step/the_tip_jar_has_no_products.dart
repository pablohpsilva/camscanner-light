import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';
import 'package:mobile/features/donation/tip_jar/tip_product.dart';

import '../support/fake_tip_jar_service.dart';
import '../support/localized_app.dart';

/// Usage: the tip jar has no products
Future<void> theTipJarHasNoProducts(WidgetTester tester) async {
  final fake = FakeTipJarService()..scriptProducts(const <TipProduct>[]);
  await tester.pumpWidget(
    localizedTestApp(
      home: DonationScreen(tipJarMode: true, createTipJar: () => fake),
    ),
  );
  await tester.pumpAndSettle();
}
