import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_banner.dart';
import 'package:mobile/features/donation/donation_screen.dart';

import '../../support/localized_app.dart';

void main() {
  Future<void> pumpBanner(WidgetTester tester) async {
    await tester.pumpWidget(
      localizedTestApp(
        home: const Scaffold(
          body: SizedBox.shrink(),
          bottomNavigationBar: DonationBanner(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders a support message', (tester) async {
    await pumpBanner(tester);
    expect(find.byKey(const Key('donation-banner')), findsOneWidget);
    expect(find.textContaining('support'), findsOneWidget);
  });

  testWidgets('leads with a heart icon and drops the coffee icon', (
    tester,
  ) async {
    await pumpBanner(tester);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.local_cafe_outlined), findsNothing);
  });

  testWidgets('support text has no trailing heart emoji', (tester) async {
    await pumpBanner(tester);
    expect(find.text('Enjoying the app? Tap to support it'), findsOneWidget);
  });

  testWidgets('tapping the banner opens the donation screen', (tester) async {
    await pumpBanner(tester);
    await tester.tap(find.byKey(const Key('donation-banner')));
    await tester.pumpAndSettle();
    expect(find.byType(DonationScreen), findsOneWidget);
  });
}
