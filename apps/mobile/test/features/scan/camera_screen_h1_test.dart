import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

/// Non-loadable capture path — prevents FilterPickerStrip thumbnail-generation
/// deadlock in FakeAsync (readBytes throws → _sourceBytes = null).
ScanDependencies _grantedH1() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () =>
          FakeCameraPreviewController(captureReturnPath: '/nonexistent/h1test.jpg'),
    );

void main() {
  testWidgets(
      'CameraScreen initial state: title is "Scan", no Done button',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: CameraScreen(dependencies: _grantedH1(), repository: FakeDocumentRepository())));
    await tester.pumpAndSettle();

    expect(find.text('Scan'), findsOneWidget);
    expect(find.byKey(const Key('camera-done')), findsNothing);
  });

  testWidgets(
      'CameraScreen after first Accept: title "1 page saved", Done button visible',
      (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(
        MaterialApp(home: CameraScreen(dependencies: _grantedH1(), repository: repo)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(find.text('1 page saved'), findsOneWidget);
    expect(find.byKey(const Key('camera-done')), findsOneWidget);
    expect(repo.createCalls, 1);
  });

  testWidgets(
      'CameraScreen after second Accept: title "2 pages saved"',
      (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(
        MaterialApp(home: CameraScreen(dependencies: _grantedH1(), repository: repo)));
    await tester.pumpAndSettle();

    // First Accept
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    // Second Accept
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(find.text('2 pages saved'), findsOneWidget);
    expect(repo.addPageCalls, 1);
  });

  testWidgets('Done button pops back to home screen', (tester) async {
    final repo = FakeDocumentRepository();

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        return Scaffold(
          key: const Key('home-scaffold'),
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => CameraScreen(
                  dependencies: _grantedH1(), repository: repo),
            )),
            child: const Text('go'),
          ),
        );
      }),
    ));

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Accept first page
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('camera-done')), findsOneWidget);

    // Tap Done → should navigate back to home
    await tester.tap(find.byKey(const Key('camera-done')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-scaffold')), findsOneWidget);
    expect(find.byKey(const Key('camera-done')), findsNothing);
  });

  testWidgets('addPage failure: snackbar shown, camera stays in add-page mode',
      (tester) async {
    // First create succeeds; subsequent addPage throws.
    final repo = FakeDocumentRepository(throwOnAddPage: true);
    await tester.pumpWidget(
        MaterialApp(home: CameraScreen(dependencies: _grantedH1(), repository: repo)));
    await tester.pumpAndSettle();

    // First Accept (create, succeeds)
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('camera-done')), findsOneWidget,
        reason: 'add-page mode active after first accept');

    // Second Accept (addPage, fails)
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't save page. Try again."), findsOneWidget,
        reason: 'snackbar shown on addPage failure');
    expect(find.byKey(const Key('camera-done')), findsOneWidget,
        reason: '_activeDocId not reset; camera stays in add-page mode');
  });
}
