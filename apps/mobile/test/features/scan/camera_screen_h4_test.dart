import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

ScanDependencies _granted() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => FakeCameraPreviewController(
          captureReturnPath: '/nonexistent/h4test.jpg'),
    );

void main() {
  testWidgets('single-capture mode: accept invokes onCapture and pops',
      (tester) async {
    var called = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        return Scaffold(
          key: const Key('caller'),
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => CameraScreen(
                dependencies: _granted(),
                repository: FakeDocumentRepository(),
                onCapture: (CapturedImage img, CropCorners c, ImageEnhancer e) async {
                  called++;
                  return true;
                },
              ),
            )),
            child: const Text('go'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(called, 1, reason: 'onCapture invoked on accept');
    expect(find.byKey(const Key('caller')), findsOneWidget,
        reason: 'camera popped back to caller after successful capture');
    expect(find.byType(CameraScreen), findsNothing);
  });

  testWidgets('single-capture failure: snackbar shown, stays in camera',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: _granted(),
        repository: FakeDocumentRepository(),
        onCapture: (img, corners, enhancer) async => false,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't replace page. Try again."), findsOneWidget);
    expect(find.byType(CameraScreen), findsOneWidget,
        reason: 'still in camera to retry');
  });
}
