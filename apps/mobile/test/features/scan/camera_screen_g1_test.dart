import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

/// [ScanDependencies] that reports permission granted and returns a
/// non-loadable capture path (avoids Image.file host-test hang).
ScanDependencies _grantedReview() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => FakeCameraPreviewController(
          captureReturnPath: '/nonexistent/g1cam.jpg'),
    );

void main() {
  testWidgets(
      'CameraScreen: grayscale toggle + accept threads GrayscaleEnhancer '
      'through to FakeDocumentRepository', (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(dependencies: _grantedReview(), repository: repo),
    ));
    await tester.pumpAndSettle();

    // Open the review screen.
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();

    // Toggle grayscale on.
    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();

    // Accept → save path executes; FakeDocumentRepository records enhancer.
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(repo.lastSavedEnhancer, isA<GrayscaleEnhancer>(),
        reason: 'GrayscaleEnhancer must reach the repository');
  });

  testWidgets(
      'CameraScreen: accept without toggle threads NoneEnhancer '
      'to FakeDocumentRepository', (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(dependencies: _grantedReview(), repository: repo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();

    // No toggle — accept immediately.
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(repo.lastSavedEnhancer, isA<NoneEnhancer>(),
        reason: 'NoneEnhancer must reach the repository when toggle is off');
  });
}
