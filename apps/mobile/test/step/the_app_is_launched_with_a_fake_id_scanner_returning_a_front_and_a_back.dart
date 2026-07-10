import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Shared repository instance — set by the Given step; read by the Then step.
FakeDocumentRepository idScanRepo = FakeDocumentRepository();

/// Usage: the app is launched with a fake ID scanner returning a front and a back
Future<void> theAppIsLaunchedWithAFakeIdScannerReturningAFrontAndABack(
  WidgetTester tester,
) async {
  idScanRepo = FakeDocumentRepository();
  app.runCamScannerApp(
    scanDependencies: ScanDependencies(
      createDocumentScanner: () => FakeSequentialDocumentScannerService([
        [const CapturedImage('/nonexistent/id_front.jpg')],
        [const CapturedImage('/nonexistent/id_back.jpg')],
      ]),
    ),
    libraryDependencies: fakeLibraryDependencies(idScanRepo),
  );
  await tester.pumpAndSettle();
}
