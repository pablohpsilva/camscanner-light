import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_scan.dart';

/// Usage: the app is launched with no camera available
Future<void> theAppIsLaunchedWithNoCameraAvailable(WidgetTester tester) async {
  app.runCamScannerApp(scanDependencies: unavailableScanDependencies());
  await tester.pumpAndSettle();
}
