import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/edge_detector.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

// CropCorners that will be returned as the detected result.
// Inset 10 % from each edge so they differ visibly from fullFrame.
const _detectedResult = DetectionResult(
  corners: CropCorners(
    topLeft: Offset(0.1, 0.1),
    topRight: Offset(0.9, 0.1),
    bottomRight: Offset(0.9, 0.9),
    bottomLeft: Offset(0.1, 0.9),
  ),
  confidence: 0.8,
);

/// Usage: the app is launched with a fake detector that returns detected corners
Future<void> theAppIsLaunchedWithAFakeDetectorThatReturnsDetectedCorners(
    WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: CameraScreen(
      dependencies: grantedScanDependenciesWithDetector(_detectedResult),
      repository: FakeDocumentRepository(),
    ),
  ));
  await tester.pumpAndSettle();
}
