// On-device integration test for A2 (no-camera / unavailable path).
// Pumps the REAL app on the device with an injected unavailable-camera fake and
// asserts the unavailable UI renders — proving navigation + state rendering on
// device. Run: flutter test integration_test/a2_camera_unavailable_test.dart -d <id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

import '../test/support/fake_scan.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A2: no-camera shows the unavailable message on device',
      (tester) async {
    app.runCamScannerApp(scanDependencies: unavailableScanDependencies());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.text('Camera unavailable on this device'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsNothing);
  });
}
