import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/tip_jar/tip_event.dart';
import 'package:mobile/features/donation/tip_jar/tip_jar_body.dart';
import 'package:mobile/features/donation/tip_jar/tip_product.dart';

import '../../support/fake_tip_jar_service.dart';
import '../../support/localized_app.dart';

Widget _host(FakeTipJarService fake) => localizedTestApp(
  home: Scaffold(body: TipJarBody(createService: () => fake)),
);

void main() {
  testWidgets('renders a button per product with its StoreKit price', (
    tester,
  ) async {
    final fake = FakeTipJarService();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    expect(find.textContaining(r'$1.99'), findsOneWidget);
    expect(find.textContaining(r'$4.99'), findsOneWidget);
    expect(find.textContaining(r'$9.99'), findsOneWidget);
    fake.dispose();
  });

  testWidgets('tapping a tip buys it and shows the thank-you dialog', (
    tester,
  ) async {
    final fake = FakeTipJarService()..scriptNextBuy(const [TipEventSuccess()]);
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining(r'$1.99'));
    await tester.pumpAndSettle();

    expect(fake.buyCount, 1);
    expect(fake.lastBought?.id, 'tip_small');
    expect(find.byKey(const Key('tip-thank-you-dialog')), findsOneWidget);
    fake.dispose();
  });

  testWidgets('canceled purchase shows no dialog and no error', (tester) async {
    final fake = FakeTipJarService()..scriptNextBuy(const [TipEventCanceled()]);
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(r'$1.99'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-thank-you-dialog')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    fake.dispose();
  });

  testWidgets('error purchase shows an error snackbar', (tester) async {
    final fake = FakeTipJarService()..scriptNextBuy(const [TipEventError()]);
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(r'$1.99'));
    await tester.pump(); // let the snackbar appear

    expect(find.byType(SnackBar), findsOneWidget);
    fake.dispose();
  });

  testWidgets('no products shows the unavailable message', (tester) async {
    final fake = FakeTipJarService()..scriptProducts(const <TipProduct>[]);
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-unavailable')), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
    fake.dispose();
  });

  testWidgets('loadProducts throwing shows the unavailable message', (
    tester,
  ) async {
    final fake = FakeTipJarService()..scriptLoadThrows();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-unavailable')), findsOneWidget);
    fake.dispose();
  });
}
