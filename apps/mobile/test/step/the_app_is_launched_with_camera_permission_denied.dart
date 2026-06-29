import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_scan.dart';

/// Usage: the app is launched with camera permission denied
Future<void> theAppIsLaunchedWithCameraPermissionDenied(
    WidgetTester tester) async {
  app.runCamScannerApp(scanDependencies: deniedScanDependencies());
  await tester.pumpAndSettle();
}
