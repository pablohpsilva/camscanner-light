// On-device integration test exercising the REAL camera plugin path (Android).
// Permission is pre-granted by the harness (verify_integration_android_real),
// so the real permission_handler resolves to granted and the real camera
// initializes, rendering a real CameraPreview. Android-only.
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A2: real camera plugin renders a live CameraPreview on Android',
      (tester) async {
    app.runCamScannerApp(); // production deps — real plugins
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    // Real camera init can take a while on a freshly-booted emulator; pump up to
    // ~25s until the live preview appears.
    for (var i = 0; i < 125 && find.byType(CameraPreview).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byType(CameraPreview), findsOneWidget,
        reason: 'real camera should initialize and render a live preview '
            '(if this fails, the emulator AVD back camera must be VirtualScene/Emulated)');
    expect(find.text('Camera unavailable on this device'), findsNothing);
  });
}
