// On-device integration test for A2 (granted/preview path).
// Pumps the REAL app on the device with an injected granted-permission + fake
// preview and asserts the camera screen + preview render — proving the Scan
// FAB navigates and the ready state mounts on device.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

import '../test/support/fake_scan.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A2: granted permission shows the camera preview on device',
      (tester) async {
    app.runCamScannerApp(scanDependencies: grantedScanDependencies());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);
    expect(find.text('FAKE PREVIEW'), findsOneWidget);

    // Sanity: we navigated away from the Documents home.
    expect(find.text('No documents yet'), findsNothing);
  });
}
