// On-device integration test for A1 — programmatic UI verification.
// Runs the REAL app on a physical device/emulator and asserts the rendered
// widget tree, so a wrong/blank/splash UI fails the gate (unlike a screenshot).
//
// Run: flutter test integration_test/a1_home_screen_test.dart -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'A1: app renders the Documents home (empty state + Scan) on device',
    (tester) async {
      app.main();
      await tester.pumpAndSettle();

      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('No documents yet'), findsOneWidget);
      expect(
        find.text('Tap Scan to create your first document'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-scan')), findsOneWidget);

      // Sanity: the old generated counter demo must be gone.
      expect(find.text('Flutter Demo Home Page'), findsNothing);
      expect(find.textContaining('You have pushed the button'), findsNothing);
    },
  );
}
