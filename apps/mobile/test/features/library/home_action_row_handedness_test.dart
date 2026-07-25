import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/settings/handedness_controller.dart';
import 'package:mobile/features/settings/handedness_store.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';
import '../../support/localized_app.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    required Handedness handedness,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      localizedTestApp(
        locale: locale,
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
          ),
          handednessController: HandednessController(
            store: InMemoryHandednessStore(),
            initial: handedness,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double dx(WidgetTester tester, String key) =>
      tester.getCenter(find.byKey(Key(key))).dx;

  testWidgets('LTR right-handed: Scan sits on the right (rightmost)', (
    tester,
  ) async {
    await pumpHome(tester, handedness: Handedness.right);
    final scan = dx(tester, 'home-scan');
    final id = dx(tester, 'home-scan-id');
    final import = dx(tester, 'home-import');
    expect(scan, greaterThan(id));
    expect(scan, greaterThan(import));
  });

  testWidgets('LTR left-handed: Scan sits on the left (leftmost)', (
    tester,
  ) async {
    await pumpHome(tester, handedness: Handedness.left);
    final scan = dx(tester, 'home-scan');
    final id = dx(tester, 'home-scan-id');
    final import = dx(tester, 'home-import');
    expect(scan, lessThan(id));
    expect(scan, lessThan(import));
  });

  testWidgets(
    'RTL (Arabic) right-handed: Scan is still physically on the right '
    '(handedness is not double-flipped)',
    (tester) async {
      await pumpHome(
        tester,
        handedness: Handedness.right,
        locale: const Locale('ar'),
      );
      final scan = dx(tester, 'home-scan');
      final id = dx(tester, 'home-scan-id');
      final import = dx(tester, 'home-import');
      expect(scan, greaterThan(id));
      expect(scan, greaterThan(import));
    },
  );
}
