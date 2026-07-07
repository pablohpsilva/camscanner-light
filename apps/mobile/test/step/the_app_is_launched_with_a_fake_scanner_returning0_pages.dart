import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import 'the_app_is_launched_with_a_fake_scanner_returning2_pages.dart';

/// Usage: the app is launched with a fake scanner returning 0 pages
Future<void> theAppIsLaunchedWithAFakeScannerReturning0Pages(
    WidgetTester tester) async {
  scanPlatformRepo = FakeDocumentRepository();
  app.runCamScannerApp(
    scanDependencies: ScanDependencies(
      createDocumentScanner: () => FakeDocumentScannerService(const []),
    ),
    libraryDependencies: fakeLibraryDependencies(scanPlatformRepo),
  );
  await tester.pumpAndSettle();
}
