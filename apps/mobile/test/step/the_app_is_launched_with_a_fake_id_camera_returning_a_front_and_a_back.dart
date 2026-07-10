import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Shared repository instance — set by the Given step; read by the Then step.
FakeDocumentRepository idScanRepo = FakeDocumentRepository();

/// Usage: the app is launched with a fake ID camera returning a front and a back
Future<void> theAppIsLaunchedWithAFakeIdCameraReturningAFrontAndABack(
  WidgetTester tester,
) async {
  idScanRepo = FakeDocumentRepository();
  app.runCamScannerApp(
    scanDependencies: ScanDependencies(
      createPhotoCamera: () => FakePhotoCamera(const [
        '/nonexistent/id_front.jpg',
        '/nonexistent/id_front_retake.jpg',
        '/nonexistent/id_back.jpg',
      ]),
      createCameraPermission: () => FakeCameraPermission(),
      createEdgeDetector: () => FakeEdgeDetector(),
    ),
    libraryDependencies: fakeLibraryDependencies(idScanRepo),
  );
  await tester.pumpAndSettle();
}
