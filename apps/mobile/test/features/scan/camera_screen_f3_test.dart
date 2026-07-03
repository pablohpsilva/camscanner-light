import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/widgets/live_quad_overlay.dart';

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

/// Minimal 2×2 BGRA frame (4 bytes per pixel, all zeros).
CameraFrame _bgraFrame() {
  return CameraFrame(
    width: 2,
    height: 2,
    format: CameraFrameFormat.bgra8888,
    planes: [
      CameraFramePlane(
        bytes: Uint8List(2 * 2 * 4),
        bytesPerRow: 8,
        bytesPerPixel: 4,
      ),
    ],
  );
}

void main() {
  testWidgets('sampling starts when controller reaches ready', (tester) async {
    final fake = FakeCameraPreviewController();
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: ScanDependencies(
          createPermissionService: () =>
              FakeCameraPermissionService(CameraPermissionStatus.granted),
          createPreviewController: () => fake,
          createEdgeDetector: () => FakeEdgeDetector(result: null),
        ),
        repository: FakeDocumentRepository(),
      ),
    ));
    await tester.pumpAndSettle(); // controller reaches ScanStatus.ready
    expect(fake.sampling, isTrue);
  });

  testWidgets(
      'overlay appears when a streamed frame yields confident detection',
      (tester) async {
    final fake = FakeCameraPreviewController();
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: ScanDependencies(
          createPermissionService: () =>
              FakeCameraPermissionService(CameraPermissionStatus.granted),
          createPreviewController: () => fake,
          createEdgeDetector: () => FakeEdgeDetector(result: _confidentResult),
        ),
        repository: FakeDocumentRepository(),
      ),
    ));
    await tester.pumpAndSettle(); // reaches ScanStatus.ready, startSampling called
    expect(find.byType(LiveQuadOverlay), findsNothing);

    fake.emitFrame(_bgraFrame());
    await tester.pump(); // detectFrame future
    await tester.pump(); // setState

    expect(find.byType(LiveQuadOverlay), findsOneWidget);
  });

  testWidgets('overlay absent when detection returns null', (tester) async {
    final fake = FakeCameraPreviewController();
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: ScanDependencies(
          createPermissionService: () =>
              FakeCameraPermissionService(CameraPermissionStatus.granted),
          createPreviewController: () => fake,
          createEdgeDetector: () => FakeEdgeDetector(result: null),
        ),
        repository: FakeDocumentRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    fake.emitFrame(_bgraFrame());
    await tester.pump();
    await tester.pump();

    expect(find.byType(LiveQuadOverlay), findsNothing);
  });

  testWidgets('overlay absent when confidence is below 0.5', (tester) async {
    final fake = FakeCameraPreviewController();
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: ScanDependencies(
          createPermissionService: () =>
              FakeCameraPermissionService(CameraPermissionStatus.granted),
          createPreviewController: () => fake,
          createEdgeDetector: () => FakeEdgeDetector(result: _lowConfResult),
        ),
        repository: FakeDocumentRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    fake.emitFrame(_bgraFrame());
    await tester.pump();
    await tester.pump();

    expect(find.byType(LiveQuadOverlay), findsNothing);
  });

  testWidgets('overlay appears when confidence is exactly 0.5', (tester) async {
    const boundaryResult = DetectionResult(
      corners: CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      ),
      confidence: 0.5,
    );
    final fake = FakeCameraPreviewController();
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: ScanDependencies(
          createPermissionService: () =>
              FakeCameraPermissionService(CameraPermissionStatus.granted),
          createPreviewController: () => fake,
          createEdgeDetector: () => FakeEdgeDetector(result: boundaryResult),
        ),
        repository: FakeDocumentRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    fake.emitFrame(_bgraFrame());
    await tester.pump();
    await tester.pump();

    expect(find.byType(LiveQuadOverlay), findsOneWidget);
  });

  testWidgets('stops sampling after shutter tap', (tester) async {
    final fake =
        FakeCameraPreviewController(captureReturnPath: '/nonexistent/x.jpg');
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: ScanDependencies(
          createPermissionService: () =>
              FakeCameraPermissionService(CameraPermissionStatus.granted),
          createPreviewController: () => fake,
          createEdgeDetector: () => FakeEdgeDetector(result: _confidentResult),
        ),
        repository: FakeDocumentRepository(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(fake.sampling, isTrue);
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump();
    expect(fake.sampling, isFalse);
  });
}
