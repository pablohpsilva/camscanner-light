// On-device integration test for A2 (permission-denied path).
// Pumps the REAL app on the device with an injected denied-permission fake and
// asserts the rationale UI renders — proving navigation + state rendering on
// device. Run: flutter test integration_test/a2_camera_denied_test.dart -d <id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

import '../test/support/fake_scan.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A2: denied permission shows rationale + Open Settings on device',
      (tester) async {
    app.runCamScannerApp(scanDependencies: deniedScanDependencies());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FloatingActionButton, 'Scan'), findsOneWidget);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.text('Camera access is needed to scan documents'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open Settings'), findsOneWidget);
  });
}
