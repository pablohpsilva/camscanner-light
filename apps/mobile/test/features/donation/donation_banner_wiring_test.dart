import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_banner.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  testWidgets('home screen shows the donation banner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DonationBanner), findsOneWidget);
  });
}
