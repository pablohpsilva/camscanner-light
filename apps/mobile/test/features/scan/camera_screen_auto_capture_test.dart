import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/auto_capture_controller.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

const _confidentResult = DetectionResult(
  corners: CropCorners(
    topLeft: Offset(0.1, 0.1),
    topRight: Offset(0.9, 0.1),
    bottomRight: Offset(0.9, 0.9),
    bottomLeft: Offset(0.1, 0.9),
  ),
  confidence: 0.8,
);

CameraFrame _bgraFrame() => CameraFrame(
      width: 2,
      height: 2,
      format: CameraFrameFormat.bgra8888,
      planes: [
        CameraFramePlane(
            bytes: Uint8List(2 * 2 * 4), bytesPerRow: 8, bytesPerPixel: 4),
      ],
    );

// Non-loadable capture path: a real file through Image.file hangs a host widget
// test; a bad path errors fast so pumpAndSettle works (see camera_screen_capture_test).
FakeCameraPreviewController _fake() =>
    FakeCameraPreviewController(captureReturnPath: '/nonexistent/capture.jpg');

Widget _screen(FakeCameraPreviewController fake) => MaterialApp(
      home: CameraScreen(
        dependencies: ScanDependencies(
          createPermissionService: () =>
              FakeCameraPermissionService(CameraPermissionStatus.granted),
          createPreviewController: () => fake,
          createEdgeDetector: () => FakeEdgeDetector(result: _confidentResult),
        ),
        repository: FakeDocumentRepository(),
      ),
    );

Future<void> _emitStable(WidgetTester tester, FakeCameraPreviewController fake,
    int n) async {
  for (var i = 0; i < n; i++) {
    fake.emitFrame(_bgraFrame());
    await tester.pump(); // detectFrame future
    await tester.pump(); // setState
  }
}

void main() {
  testWidgets('auto-capture (default ON) fires after N stable frames',
      (tester) async {
    final fake = _fake();
    await tester.pumpWidget(_screen(fake));
    await tester.pumpAndSettle(); // ready + sampling

    await _emitStable(
        tester, fake, AutoCaptureController().requiredStableFrames);
    await tester.pumpAndSettle(); // capture + navigate to review

    expect(find.byType(CaptureReviewScreen), findsOneWidget);
  });

  testWidgets('toggling auto-capture off suppresses auto-fire',
      (tester) async {
    final fake = _fake();
    await tester.pumpWidget(_screen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-auto-capture-toggle')));
    await tester.pump();

    await _emitStable(tester, fake, 8); // more than N
    await tester.pumpAndSettle();

    expect(find.byType(CaptureReviewScreen), findsNothing);
  });

  testWidgets('manual shutter still fires when auto-capture is off',
      (tester) async {
    final fake = _fake();
    await tester.pumpWidget(_screen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-auto-capture-toggle')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();

    expect(find.byType(CaptureReviewScreen), findsOneWidget);
  });

  testWidgets('countdown ring appears mid-climb, before auto-fire',
      (tester) async {
    final fake = _fake();
    await tester.pumpWidget(_screen(fake));
    await tester.pumpAndSettle();

    final n = AutoCaptureController().requiredStableFrames;
    await _emitStable(tester, fake, n ~/ 2); // partway: progress > 0, not yet firing

    expect(find.byKey(const Key('scan-auto-capture-ring')), findsOneWidget);
    expect(find.byType(CaptureReviewScreen), findsNothing);
  });
}
