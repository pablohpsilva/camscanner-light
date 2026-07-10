import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/id_scan_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

Widget _host(IdScanScreen screen) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => screen)),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

/// Deps with a sequential fake camera (null = cancel), a granted permission,
/// and a null-returning edge detector (nonexistent paths never reach detect()).
ScanDependencies _deps(List<String?> shots, {bool granted = true}) =>
    ScanDependencies(
      createPhotoCamera: () => FakePhotoCamera(shots),
      createCameraPermission: () => FakeCameraPermission(granted: granted),
      createEdgeDetector: () => FakeEdgeDetector(),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _accept(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-accept')));
  await tester.pumpAndSettle();
}

Future<void> _retake(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-retake')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('accept front then back saves a 2-page id-card document', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    final deps = _deps(const [
      '/nonexistent/front.jpg',
      '/nonexistent/back.jpg',
    ]);
    await tester.pumpWidget(
      _host(IdScanScreen(dependencies: deps, repository: repo)),
    );
    await _open(tester); // permission → capture front → review appears
    await _accept(tester); // advance to back → capture → review appears
    await _accept(tester); // save + pop

    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 1);
    expect(repo.markIdCardCalls.length, 1);
    expect(find.byType(IdScanScreen), findsNothing); // popped
  });

  testWidgets('retaking the front captures again; still one 2-page doc', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    final cam = FakePhotoCamera(const [
      '/nonexistent/front1.jpg',
      '/nonexistent/front2.jpg',
      '/nonexistent/back.jpg',
    ]);
    final deps = ScanDependencies(
      createPhotoCamera: () => cam,
      createCameraPermission: () => FakeCameraPermission(),
      createEdgeDetector: () => FakeEdgeDetector(),
    );
    // Inject the SAME camera instance so captureCount survives.
    await tester.pumpWidget(
      _host(IdScanScreen(dependencies: deps, repository: repo)),
    );
    await _open(tester); // capture front1 → review
    await _retake(tester); // capture front2 → review
    await _accept(tester); // front accepted → capture back → review
    await _accept(tester); // save + pop

    expect(cam.captureCount, 3);
    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 1);
  });

  testWidgets('cancel on front saves nothing and pops', (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(
      _host(IdScanScreen(dependencies: _deps(const [null]), repository: repo)),
    );
    await _open(tester);
    expect(repo.createCalls, 0);
    expect(find.byType(IdScanScreen), findsNothing);
  });

  testWidgets('permission denied saves nothing, never opens camera', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    final cam = FakePhotoCamera(const ['/nonexistent/front.jpg']);
    final deps = ScanDependencies(
      createPhotoCamera: () => cam,
      createCameraPermission: () => FakeCameraPermission(granted: false),
      createEdgeDetector: () => FakeEdgeDetector(),
    );
    await tester.pumpWidget(
      _host(IdScanScreen(dependencies: deps, repository: repo)),
    );
    await _open(tester);
    expect(cam.captureCount, 0);
    expect(repo.createCalls, 0);
    expect(find.byType(IdScanScreen), findsNothing);
  });
}
