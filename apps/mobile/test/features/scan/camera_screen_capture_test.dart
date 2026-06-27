import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_preview_controller.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_scan.dart';

// Review-rendering tests feed a NON-LOADABLE capture path: a real file routed
// through Image.file hangs a host widget test (pending dart:io isolate-port read
// under fake-async). A bad path errors fast, so pumpAndSettle works. Real
// rendering is covered on-device by the A3 BDD test.
ScanDependencies _grantedReview() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => FakeCameraPreviewController(
          captureReturnPath: '/nonexistent/capture.jpg'),
    );

ScanDependencies _grantedWithCaptureError() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => FakeCameraPreviewController()
        ..captureError = const CameraUnavailableException('boom'),
    );

void main() {
  testWidgets('ready state shows the shutter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CameraScreen(dependencies: grantedScanDependencies())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-shutter')), findsOneWidget);
  });

  testWidgets('tapping the shutter opens the review screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CameraScreen(dependencies: _grantedReview())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('review-image')), findsOneWidget);
    expect(find.byKey(const Key('review-retake')), findsOneWidget);
    expect(find.byKey(const Key('review-accept')), findsOneWidget);
  });

  testWidgets('Retake returns to the live preview', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CameraScreen(dependencies: _grantedReview())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-retake')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan-shutter')), findsOneWidget);
    expect(find.byKey(const Key('review-image')), findsNothing);
  });

  testWidgets('capture failure shows a SnackBar and stays on preview',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CameraScreen(dependencies: _grantedWithCaptureError())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump(); // let the SnackBar appear
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Could not capture photo. Try again.'), findsOneWidget);
    expect(find.byKey(const Key('review-image')), findsNothing);
    expect(find.byKey(const Key('scan-shutter')), findsOneWidget);
  });
}
