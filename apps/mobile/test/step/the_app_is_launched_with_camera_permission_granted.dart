import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_scan.dart';

/// Usage: the app is launched with camera permission granted
Future<void> theAppIsLaunchedWithCameraPermissionGranted(
    WidgetTester tester) async {
  app.runCamScannerApp(scanDependencies: grantedScanDependencies());
  await tester.pumpAndSettle();
}
