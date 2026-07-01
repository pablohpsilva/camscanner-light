import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Shared repo instance — set by this Given step; read by Then steps.
FakeDocumentRepository h1Repo = FakeDocumentRepository();

/// Usage: the camera screen is open
Future<void> theCameraScreenIsOpen(WidgetTester tester) async {
  h1Repo = FakeDocumentRepository();
  await tester.pumpWidget(MaterialApp(
    home: CameraScreen(
      dependencies: ScanDependencies(
        createPermissionService: () =>
            FakeCameraPermissionService(CameraPermissionStatus.granted),
        createPreviewController: () =>
            FakeCameraPreviewController(captureReturnPath: '/nonexistent/h1bdd.jpg'),
      ),
      repository: h1Repo,
    ),
  ));
  await tester.pumpAndSettle();
}
