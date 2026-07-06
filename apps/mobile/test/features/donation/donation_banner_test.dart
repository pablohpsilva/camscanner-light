import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_banner.dart';
import 'package:mobile/features/donation/donation_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox.shrink(),
        bottomNavigationBar: DonationBanner(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders a support message', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('donation-banner')), findsOneWidget);
    expect(find.textContaining('support'), findsOneWidget);
  });

  testWidgets('tapping the banner opens the donation screen', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('donation-banner')));
    await tester.pumpAndSettle();
    expect(find.byType(DonationScreen), findsOneWidget);
  });
}
