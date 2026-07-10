import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/scan_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  testWidgets('retake mode captures from the camera and calls onCapture', (
    tester,
  ) async {
    CapturedImage? captured;
    final deps = ScanDependencies(
      createPhotoCamera: () =>
          FakePhotoCamera(const ['/nonexistent/retake.jpg']),
      createCameraPermission: () => FakeCameraPermission(),
      createEdgeDetector: () => FakeEdgeDetector(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ScanScreen(
          dependencies: deps,
          repository: FakeDocumentRepository(),
          onCapture: (image, corners, enhancer) async {
            captured = image;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle(); // permission → capture → review appears
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(captured?.path, '/nonexistent/retake.jpg');
  });
}
