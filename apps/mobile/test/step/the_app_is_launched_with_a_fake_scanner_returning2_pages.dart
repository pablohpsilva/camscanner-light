import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Shared repository instance — set by the Given steps; read by the Then steps.
FakeDocumentRepository scanPlatformRepo = FakeDocumentRepository();

/// Usage: the app is launched with a fake scanner returning 2 pages
Future<void> theAppIsLaunchedWithAFakeScannerReturning2Pages(
    WidgetTester tester) async {
  scanPlatformRepo = FakeDocumentRepository();
  app.runCamScannerApp(
    scanDependencies: ScanDependencies(
      createDocumentScanner: () => FakeDocumentScannerService([
        const CapturedImage('/nonexistent/scan_1.jpg'),
        const CapturedImage('/nonexistent/scan_2.jpg'),
      ]),
    ),
    libraryDependencies: fakeLibraryDependencies(scanPlatformRepo),
  );
  await tester.pumpAndSettle();
}
