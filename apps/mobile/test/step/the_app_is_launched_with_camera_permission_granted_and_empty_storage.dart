import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Usage: the app is launched with camera permission granted and empty storage
Future<void> theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(
    WidgetTester tester) async {
  app.runCamScannerApp(
    scanDependencies: grantedScanDependencies(),
    libraryDependencies: tempLibraryDependencies(),
  );
  await tester.pumpAndSettle();
}
