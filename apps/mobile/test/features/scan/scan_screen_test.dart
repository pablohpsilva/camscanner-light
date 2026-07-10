import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/scan_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

// Push ScanScreen from a host so its final pop() has somewhere to return to.
Widget _host(ScanScreen screen) => MaterialApp(
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

ScanDependencies _deps(List<String> paths) => ScanDependencies(
  createDocumentScanner: () =>
      FakeDocumentScannerService(paths.map(CapturedImage.new).toList()),
);

void main() {
  testWidgets('cancelled scan (empty) pops without saving', (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(
      _host(ScanScreen(dependencies: _deps(const []), repository: repo)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(ScanScreen), findsNothing); // popped back to host
    expect(repo.createCalls, 0);
  });

  testWidgets('multi-page: one filter review, first creates doc, rest append', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(
      _host(
        ScanScreen(
          dependencies: _deps(const [
            '/nonexistent/scan_1.jpg',
            '/nonexistent/scan_2.jpg',
            '/nonexistent/scan_3.jpg',
          ]),
          repository: repo,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(); // scanner returns → review pushed

    expect(find.byType(CaptureReviewScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle(); // save all → pop

    expect(
      find.byType(ScanScreen),
      findsNothing,
    ); // popped after successful save
    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 2);
    expect(repo.lastSavedCorners, CropCorners.fullFrame);
  });

  testWidgets('save failure: stays on screen and shows retry', (tester) async {
    final repo = FakeDocumentRepository(throwOnCreate: true);
    await tester.pumpWidget(
      _host(
        ScanScreen(
          dependencies: _deps(const ['/nonexistent/scan_fail.jpg']),
          repository: repo,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(); // scanner returns → review pushed

    expect(find.byType(CaptureReviewScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle(); // save fails → stays on ScanScreen

    expect(find.byKey(const Key('scan-save-error')), findsOneWidget);
    expect(find.byType(ScanScreen), findsOneWidget); // NOT popped
  });

  testWidgets(
    'retake mode: single page → onCapture with enhancer, pageLimit 1',
    (tester) async {
      final repo = FakeDocumentRepository();
      final fakeScanner = FakeDocumentScannerService([
        const CapturedImage('/nonexistent/re.jpg'),
      ]);
      CapturedImage? captured;
      await tester.pumpWidget(
        _host(
          ScanScreen(
            dependencies: ScanDependencies(
              createDocumentScanner: () => fakeScanner,
            ),
            repository: repo,
            onCapture: (image, corners, enhancer) async {
              captured = image;
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('review-accept')));
      await tester.pumpAndSettle();

      expect(captured?.path, '/nonexistent/re.jpg');
      expect(fakeScanner.lastPageLimit, 1);
      expect(repo.createCalls, 0); // retake replaces, does not create
    },
  );
}
