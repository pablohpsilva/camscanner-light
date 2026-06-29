import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';

import '../../support/fake_library.dart';

// A repo that fails getDocumentPages on the first call, succeeds after — to
// drive the error -> retry -> loaded transition.
class _FlakyPagesRepo extends FakeDocumentRepository {
  int calls = 0;
  @override
  Future<List<PageImage>> getDocumentPages(int documentId) async {
    calls++;
    if (calls == 1) throw StateError('boom');
    return [PageImage(position: 1, imagePath: '/nonexistent/p.jpg')];
  }
}

void main() {
  // Pump the viewer pushed onto a route over a trivial home, so a delete-pop
  // returns to a detectable base screen.
  Future<void> pushViewer(
    WidgetTester tester,
    DocumentRepository repo, {
    int id = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PageViewerScreen(
                      documentId: id, name: 'Scan X', repository: repo),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // Safe to settle: page image paths are NON-LOADABLE, which does not hang.
    await tester.pumpAndSettle();
  }

  testWidgets('loaded: full-res FileImage (NOT ResizeImage) + indicator',
      (tester) async {
    await pushViewer(tester, FakeDocumentRepository());

    expect(find.byType(PageViewerScreen), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);

    final img = tester.widget<Image>(find.byType(Image));
    expect(img.image, isA<FileImage>(),
        reason: 'viewer decodes full-res; NOT a ResizeImage like the thumbnail');
    expect((img.image as FileImage).file.path, '/nonexistent/page-1-1.jpg');
    expect(img.errorBuilder, isNotNull);

    expect(find.byKey(const Key('page-viewer-indicator')), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('empty: zero pages renders the empty placeholder', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(pages: const []));
    expect(find.byKey(const Key('page-viewer-empty')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('load error shows a retryable error state; retry recovers',
      (tester) async {
    await pushViewer(tester, _FlakyPagesRepo());
    expect(find.byKey(const Key('page-viewer-error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('page-viewer-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-viewer-error')), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('delete confirm calls deleteDocument and pops to the list',
      (tester) async {
    final repo = FakeDocumentRepository();
    await pushViewer(tester, repo, id: 7);

    await tester.tap(find.byKey(const Key('page-viewer-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-confirm')));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, contains(7));
    expect(find.byType(PageViewerScreen), findsNothing); // popped
    expect(find.text('open'), findsOneWidget); // back on the base screen
  });

  testWidgets('delete cancel does nothing and stays on the viewer',
      (tester) async {
    final repo = FakeDocumentRepository();
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-cancel')));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, isEmpty);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });

  testWidgets('delete is disabled in the error state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(throwOnGetPages: true));
    expect(find.byKey(const Key('page-viewer-error')), findsOneWidget);
    final btn = tester.widget<IconButton>(find.byKey(const Key('page-viewer-delete')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('delete failure stays on the viewer and shows an error SnackBar',
      (tester) async {
    final repo = FakeDocumentRepository(throwOnDelete: true);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-confirm')));
    await tester.pumpAndSettle(); // drive the async throw -> catch -> SnackBar

    expect(find.text("Couldn't delete"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
    expect(repo.deletedIds, isEmpty);
  });

  testWidgets('export success navigates to the PDF preview', (tester) async {
    final repo = FakeDocumentRepository();
    await pushViewer(tester, repo, id: 4);

    await tester.tap(find.byKey(const Key('page-viewer-export')));
    // pump (NOT settle): the pushed preview opens the real pdfx channel in host.
    await tester.pump();
    await tester.pump();

    expect(repo.exportedIds, contains(4));
    expect(find.byType(PdfPreviewScreen), findsOneWidget);
  });

  testWidgets('export failure shows an error SnackBar and stays',
      (tester) async {
    final repo = FakeDocumentRepository(throwOnExport: true);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't export PDF"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });

  testWidgets('export is disabled in the error state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(throwOnGetPages: true));
    expect(find.byKey(const Key('page-viewer-error')), findsOneWidget);
    final btn =
        tester.widget<IconButton>(find.byKey(const Key('page-viewer-export')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('export is disabled in the empty state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(pages: const []));
    expect(find.byKey(const Key('page-viewer-empty')), findsOneWidget);
    final btn =
        tester.widget<IconButton>(find.byKey(const Key('page-viewer-export')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('all AppBar actions are disabled while an export is in flight',
      (tester) async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(exportGate: gate);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pump(); // start the export; gate holds it open
    IconButton btn(String k) =>
        tester.widget<IconButton>(find.byKey(Key(k)));
    expect(btn('page-viewer-rename').onPressed, isNull);
    expect(btn('page-viewer-export').onPressed, isNull);
    expect(btn('page-viewer-delete').onPressed, isNull);

    gate.complete();
    await tester.pump(); // process export completion + navigation (NOT settle — pdfx channel)
    await tester.pump();
    expect(find.byType(PdfPreviewScreen), findsOneWidget);
  });

  testWidgets('rename: confirming Save updates the AppBar title',
      (tester) async {
    final repo = FakeDocumentRepository();
    await pushViewer(tester, repo, id: 3);

    await tester.tap(find.byKey(const Key('page-viewer-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'Receipts');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();

    expect(repo.renamedTo, contains('Receipts'));
    expect(find.widgetWithText(AppBar, 'Receipts'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Scan X'), findsNothing);
  });

  testWidgets('rename is disabled in the error state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(throwOnGetPages: true));
    expect(find.byKey(const Key('page-viewer-error')), findsOneWidget);
    final btn = tester
        .widget<IconButton>(find.byKey(const Key('page-viewer-rename')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('rename failure shows an error SnackBar and stays',
      (tester) async {
    final repo = FakeDocumentRepository(throwOnRename: true);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'New');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle(); // drive the async throw -> catch -> SnackBar

    expect(find.text("Couldn't rename"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });

  // E2: viewer uses displayPath — verify the page key is present regardless of
  // whether flatImagePath is set (visual path correctness is covered by page_image_test).
  testWidgets('E2: viewer renders page key when flatImagePath is set',
      (tester) async {
    final repo = FakeDocumentRepository(
      pages: [
        const PageImage(
          position: 1,
          imagePath: '/nonexistent/page_1.jpg',
          flatImagePath: '/nonexistent/page_1_flat.jpg',
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
    ));
    await tester.pump();
    expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);
  });

  testWidgets('the AppBar actions carry screen-reader tooltips',
      (tester) async {
    await pushViewer(tester, FakeDocumentRepository());
    String? tip(String key) =>
        tester.widget<IconButton>(find.byKey(Key(key))).tooltip;
    expect(tip('page-viewer-rename'), 'Rename');
    expect(tip('page-viewer-export'), 'Export PDF');
    expect(tip('page-viewer-delete'), 'Delete');
  });
}
