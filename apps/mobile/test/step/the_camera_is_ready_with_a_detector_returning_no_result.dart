import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_screen.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Usage: the camera is ready with a detector returning no result
Future<void> theCameraIsReadyWithADetectorReturningNoResult(
    WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: CameraScreen(
      dependencies: liveDetectionScanDependencies(detectionResult: null),
      repository: FakeDocumentRepository(),
    ),
  ));
  await tester.pumpAndSettle();
}
