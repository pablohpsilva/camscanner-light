import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    required FeatureFlags features,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
            features: features,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('all three home buttons present by default', (tester) async {
    await pumpHome(tester, features: const FeatureFlags());
    expect(find.byKey(const Key('home-scan')), findsOneWidget);
    expect(find.byKey(const Key('home-scan-id')), findsOneWidget);
    expect(find.byKey(const Key('home-import')), findsOneWidget);
  });

  testWidgets('id card off hides the ID card button', (tester) async {
    await pumpHome(tester, features: const FeatureFlags(idCard: false));
    expect(find.byKey(const Key('home-scan-id')), findsNothing);
    expect(find.byKey(const Key('home-scan')), findsOneWidget);
    expect(find.byKey(const Key('home-import')), findsOneWidget);
  });

  testWidgets('scan off hides the Scan button', (tester) async {
    await pumpHome(tester, features: const FeatureFlags(scan: false));
    expect(find.byKey(const Key('home-scan')), findsNothing);
    expect(find.byKey(const Key('home-import')), findsOneWidget);
  });

  testWidgets('import off hides the Import button', (tester) async {
    await pumpHome(tester, features: const FeatureFlags(import: false));
    expect(find.byKey(const Key('home-import')), findsNothing);
    expect(find.byKey(const Key('home-scan')), findsOneWidget);
  });
}
