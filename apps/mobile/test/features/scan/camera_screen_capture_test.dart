import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_preview_controller.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

/// Preview whose [capture] blocks on [gate] so a test can observe the transient
/// `capturing` UI (busy indicator + disabled shutter) before capture completes.
class _GatedPreview implements CameraPreviewController {
  final Completer<void> gate = Completer<void>();
  @override
  Future<void> initialize() async {}
  @override
  Widget buildPreview() => const SizedBox.shrink();
  @override
  Future<CapturedImage> capture() async {
    await gate.future;
    return const CapturedImage('/nonexistent/capture.jpg');
  }
  @override
  Future<void> dispose() async {}
}

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
  testWidgets('shutter shows the busy indicator and is disabled while capturing',
      (tester) async {
    final gated = _GatedPreview();
    final deps = ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => gated,
    );
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: deps,
        repository: FakeDocumentRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap the shutter; capture() now blocks on the gate, so capturing == true.
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump();

    expect(find.byKey(const Key('scan-shutter-busy')), findsOneWidget,
        reason: 'busy indicator shows while capturing');
    final fab = tester
        .widget<FloatingActionButton>(find.byKey(const Key('scan-shutter')));
    expect(fab.onPressed, isNull, reason: 'shutter is disabled while capturing');

    // Release capture so teardown is clean (non-loadable path → review no hang).
    gated.gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('ready state shows the shutter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CameraScreen(
        dependencies: grantedScanDependencies(),
        repository: FakeDocumentRepository(),
      )),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-shutter')), findsOneWidget);
  });

  testWidgets('tapping the shutter opens the review screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CameraScreen(
        dependencies: _grantedReview(),
        repository: FakeDocumentRepository(),
      )),
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
      MaterialApp(home: CameraScreen(
        dependencies: _grantedReview(),
        repository: FakeDocumentRepository(),
      )),
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
      MaterialApp(home: CameraScreen(
        dependencies: _grantedWithCaptureError(),
        repository: FakeDocumentRepository(),
      )),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump(); // let the SnackBar appear
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Could not capture photo. Try again.'), findsOneWidget);
    expect(find.byKey(const Key('review-image')), findsNothing);
    expect(find.byKey(const Key('scan-shutter')), findsOneWidget);
  });

  testWidgets('Accept save failure shows a SnackBar and stays on review',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: _grantedReview(),
        repository: FakeDocumentRepository(throwOnCreate: true),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pump(); // start save
    await tester.pump(const Duration(milliseconds: 50)); // let it fail
    expect(find.text("Couldn't save document. Try again."), findsOneWidget);
    expect(find.byKey(const Key('review-accept')), findsOneWidget,
        reason: 'still on the review screen');
  });

  testWidgets('Accept save success returns to the Documents home',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: _grantedReview(),
        repository: FakeDocumentRepository(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-accept')), findsNothing,
        reason: 'left the review screen after a successful save');
  });
}
