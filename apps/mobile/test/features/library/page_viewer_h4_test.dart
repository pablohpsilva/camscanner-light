import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/scan_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  Future<void> pushViewer(
    WidgetTester tester,
    FakeDocumentRepository repo, {
    ScanDependencies? deps,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PageViewerScreen(
                    documentId: 1,
                    name: 'Doc',
                    repository: repo,
                    dependencies: deps ?? const ScanDependencies(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  FakeDocumentRepository twoPageRepo() => FakeDocumentRepository(
    pages: [
      const PageImage(position: 1, imagePath: '/nonexistent/p1.jpg'),
      const PageImage(position: 2, imagePath: '/nonexistent/p2.jpg'),
    ],
  );

  testWidgets('overflow menu exposes Retake page and Delete page', (
    tester,
  ) async {
    await pushViewer(tester, twoPageRepo());
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-viewer-retake')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-delete-page')), findsOneWidget);
  });

  testWidgets('Delete page: confirm calls deletePage', (tester) async {
    final repo = twoPageRepo();
    await pushViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-page-confirm')));
    await tester.pumpAndSettle();
    expect(repo.lastDeletedPagePosition, 1);
  });

  testWidgets('Delete page: cancel does NOT call deletePage', (tester) async {
    final repo = twoPageRepo();
    await pushViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-page-cancel')));
    await tester.pumpAndSettle();
    expect(repo.lastDeletedPagePosition, isNull);
  });

  testWidgets('Delete the only page: whole-document copy + pops viewer', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      pages: [const PageImage(position: 1, imagePath: '/nonexistent/p1.jpg')],
    );
    await pushViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This is the only page. Deleting it removes the whole document.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('page-viewer-delete-page-confirm')));
    await tester.pumpAndSettle();
    // remaining == 0 → viewer popped back to the opener button.
    expect(find.byKey(const Key('open')), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsNothing);
  });

  testWidgets('Delete page failure shows a snackbar, stays on viewer', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      throwOnDeletePage: true,
      pages: [
        const PageImage(position: 1, imagePath: '/nonexistent/p1.jpg'),
        const PageImage(position: 2, imagePath: '/nonexistent/p2.jpg'),
      ],
    );
    await pushViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-page-confirm')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't delete page"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });

  testWidgets('Retake page pushes the scan screen', (tester) async {
    final repo = twoPageRepo();
    // Inject a never-completing scanner so ScanScreen stays visible.
    // pumpAndSettle must NOT be used after tapping retake — ScanScreen shows
    // a CircularProgressIndicator that keeps scheduling animation frames.
    final deps = ScanDependencies(
      createDocumentScanner: HangingDocumentScannerService.new,
    );
    await pushViewer(tester, repo, deps: deps);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-retake')));
    await tester
        .pump(); // dispatch tap, push ScanScreen, post-frame _run() starts
    await tester.pump(); // settle pending microtasks; _run() awaits scanner
    expect(find.byType(ScanScreen), findsOneWidget);
  });
}
