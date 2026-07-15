import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import 'the_app_is_launched_with_a_fake_id_scanner_returning_a_front_and_a_back.dart';

/// Usage: the app is launched with a fake ID scanner returning a front then a cancelled back
///
/// The sequential scanner yields the front on the first scan and an EMPTY
/// batch (a cancelled capture) on the second, so the back step is cancelled.
/// Reuses the shared [idScanRepo] so the Then step can assert what was saved.
Future<void>
theAppIsLaunchedWithAFakeIdScannerReturningAFrontThenACancelledBack(
  WidgetTester tester,
) async {
  idScanRepo = FakeDocumentRepository();
  app.runCamScannerApp(
    scanDependencies: ScanDependencies(
      createDocumentScanner: () => FakeSequentialDocumentScannerService([
        [const CapturedImage('/nonexistent/id_front.jpg')],
        const <CapturedImage>[],
      ]),
    ),
    libraryDependencies: fakeLibraryDependencies(idScanRepo),
  );
  await tester.pumpAndSettle();
}
