import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

// Granted camera + a gallery picker returning a NON-LOADABLE path (so the
// review screen's FilterPickerStrip does not deadlock under FakeAsync).
ScanDependencies _deps({bool cancel = false, bool throwOnPick = false}) =>
    ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () =>
          FakeCameraPreviewController(captureReturnPath: '/nonexistent/cap.jpg'),
      createGalleryPicker: () => FakeGalleryPicker(
          cancel: cancel,
          throwOnPick: throwOnPick,
          returnPath: '/nonexistent/import.jpg'),
    );

void main() {
  testWidgets('import button is present even before any capture',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CameraScreen(
            dependencies: _deps(), repository: FakeDocumentRepository())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('camera-import')), findsOneWidget);
  });

  testWidgets('importing a photo opens the review screen', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CameraScreen(
            dependencies: _deps(), repository: FakeDocumentRepository())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('camera-import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-accept')), findsOneWidget);
  });

  testWidgets('import then Accept saves a document', (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(MaterialApp(
        home: CameraScreen(dependencies: _deps(), repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('camera-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
  });

  testWidgets('cancelling the picker stays on the camera (no review, no save)',
      (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(MaterialApp(
        home: CameraScreen(
            dependencies: _deps(cancel: true), repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('camera-import')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-accept')), findsNothing);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
    expect(repo.createCalls, 0);
  });

  testWidgets('picker error shows a SnackBar, stays on the camera',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CameraScreen(
            dependencies: _deps(throwOnPick: true),
            repository: FakeDocumentRepository())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('camera-import')));
    await tester.pumpAndSettle();
    expect(find.text('Couldn\'t import photo'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
  });
}
