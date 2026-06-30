import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/widgets/live_quad_overlay.dart';

import 'package:mobile/features/scan/camera_permission_service.dart';

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

const _lowConfResult = DetectionResult(
  corners: CropCorners.fullFrame,
  confidence: 0.3,
);

void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('overlay appears after timer fires with confident detection',
      (tester) async {
    await tester.pumpWidget(host(CameraScreen(
      dependencies:
          liveDetectionScanDependencies(detectionResult: _confidentResult),
      repository: FakeDocumentRepository(),
    )));
    await tester.pumpAndSettle(); // camera reaches ScanStatus.ready

    expect(find.byType(LiveQuadOverlay), findsNothing);

    await tester.pump(const Duration(milliseconds: 900)); // fire 800ms timer
    await tester.pump(); // drain sampleFrame microtask
    await tester.pump(); // drain detect microtask + setState rebuild

    expect(find.byType(LiveQuadOverlay), findsOneWidget);
  });

  testWidgets('overlay absent when detection returns null', (tester) async {
    await tester.pumpWidget(host(CameraScreen(
      dependencies:
          liveDetectionScanDependencies(detectionResult: null),
      repository: FakeDocumentRepository(),
    )));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LiveQuadOverlay), findsNothing);
  });

  testWidgets('overlay absent when confidence is below 0.5', (tester) async {
    await tester.pumpWidget(host(CameraScreen(
      dependencies:
          liveDetectionScanDependencies(detectionResult: _lowConfResult),
      repository: FakeDocumentRepository(),
    )));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LiveQuadOverlay), findsNothing);
  });

  testWidgets('sampleFrame is called after timer fires', (tester) async {
    final fakeController = FakeCameraPreviewController(
      sampleFrameResult: kFakeJpegBytes,
    );
    await tester.pumpWidget(host(CameraScreen(
      dependencies: ScanDependencies(
        createPermissionService: () =>
            FakeCameraPermissionService(CameraPermissionStatus.granted),
        createPreviewController: () => fakeController,
        createEdgeDetector: () =>
            FakeEdgeDetector(result: _confidentResult),
      ),
      repository: FakeDocumentRepository(),
    )));
    await tester.pumpAndSettle();

    expect(fakeController.sampleFrameCalls, 0);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();

    expect(fakeController.sampleFrameCalls, greaterThan(0));
  });
}
