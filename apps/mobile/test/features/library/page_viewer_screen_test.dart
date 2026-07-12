import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';
import 'package:mobile/features/library/widgets/editor_toolbar_button.dart';
import 'package:mobile/features/library/widgets/editor_top_bar.dart';

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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PageViewerScreen(
                      documentId: id,
                      name: 'Scan X',
                      repository: repo,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Safe to settle: page image paths are NON-LOADABLE, which does not hang.
    await tester.pumpAndSettle();
  }

  testWidgets(
    'loaded: full-res FileImage (NOT ResizeImage); strip replaces indicator',
    (tester) async {
      await pushViewer(tester, FakeDocumentRepository());

      expect(find.byType(PageViewerScreen), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);

      // The full-res image is the one inside the InteractiveViewer (NOT the strip thumbnail).
      final fullRes = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('page-viewer-page-1')),
          matching: find.byType(Image),
        ),
      );
      expect(
        fullRes.image,
        isA<FileImage>(),
        reason:
            'viewer decodes full-res; NOT a ResizeImage like strip thumbnails',
      );
      expect(
        (fullRes.image as FileImage).file.path,
        '/nonexistent/page-1-1.jpg',
      );
      expect(fullRes.errorBuilder, isNotNull);

      // Strip replaces old text indicator.
      expect(find.byKey(const Key('page-thumbnail-strip')), findsOneWidget);
      expect(find.byKey(const Key('page-viewer-indicator')), findsNothing);
      expect(find.text('1 / 1'), findsNothing);
    },
  );

  testWidgets('empty: zero pages renders the empty placeholder', (
    tester,
  ) async {
    await pushViewer(tester, FakeDocumentRepository(pages: const []));
    expect(find.byKey(const Key('page-viewer-empty')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('load error shows a retryable error state; retry recovers', (
    tester,
  ) async {
    await pushViewer(tester, _FlakyPagesRepo());
    expect(find.byKey(const Key('page-viewer-error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('page-viewer-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-viewer-error')), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('delete confirm calls deleteDocument and pops to the list', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    await pushViewer(tester, repo, id: 7);

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-confirm')));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, contains(7));
    expect(find.byType(PageViewerScreen), findsNothing); // popped
    expect(find.text('open'), findsOneWidget); // back on the base screen
  });

  testWidgets('delete cancel does nothing and stays on the viewer', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
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
    // Delete-document now lives in the overflow menu, disabled when the menu is.
    final menu = tester.widget<PopupMenuButton<String>>(
      find.byKey(const Key('page-viewer-page-menu')),
    );
    expect(menu.enabled, isFalse);
  });

  testWidgets(
    'delete failure stays on the viewer and shows an error SnackBar',
    (tester) async {
      final repo = FakeDocumentRepository(throwOnDelete: true);
      await pushViewer(tester, repo);

      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-delete-confirm')));
      await tester
          .pumpAndSettle(); // drive the async throw -> catch -> SnackBar

      expect(find.text("Couldn't delete"), findsOneWidget);
      expect(find.byType(PageViewerScreen), findsOneWidget);
      expect(repo.deletedIds, isEmpty);
    },
  );

  testWidgets('export success navigates to the PDF preview', (tester) async {
    final repo = FakeDocumentRepository();
    await pushViewer(tester, repo, id: 4);

    await tester.tap(find.byKey(const Key('page-viewer-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pumpAndSettle(); // export-quality dialog animates in
    await tester.tap(find.byKey(const Key('export-quality-original')));
    // pump (NOT settle): the pushed preview opens the real pdfx channel in host.
    await tester.pump();
    await tester.pump();

    expect(repo.exportedIds, contains(4));
    expect(find.byType(PdfPreviewScreen), findsOneWidget);
  });

  testWidgets('export failure shows an error SnackBar and stays', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(throwOnExport: true);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pumpAndSettle(); // export-quality dialog animates in
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't export PDF"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });

  testWidgets('export is disabled in the error state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(throwOnGetPages: true));
    expect(find.byKey(const Key('page-viewer-error')), findsOneWidget);
    // Export PDF now lives behind the Share toolbar action, disabled with it.
    final btn = tester.widget<EditorToolbarButton>(
      find.byKey(const Key('page-viewer-share')),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('export is disabled in the empty state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(pages: const []));
    expect(find.byKey(const Key('page-viewer-empty')), findsOneWidget);
    final btn = tester.widget<EditorToolbarButton>(
      find.byKey(const Key('page-viewer-share')),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('all editor actions are disabled while an export is in flight', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(exportGate: gate);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pumpAndSettle(); // export-quality dialog animates in
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pump(); // start the export; gate holds it open
    EditorToolbarButton toolBtn(String k) =>
        tester.widget<EditorToolbarButton>(find.byKey(Key(k)));
    // Rename + delete-document sit in the overflow menu (disabled with it).
    final menu = tester.widget<PopupMenuButton<String>>(
      find.byKey(const Key('page-viewer-page-menu')),
    );
    expect(menu.enabled, isFalse);
    // Crop + Share (which fronts export) are toolbar actions.
    expect(toolBtn('page-viewer-edit').onPressed, isNull);
    expect(toolBtn('page-viewer-share').onPressed, isNull);

    gate.complete();
    await tester
        .pump(); // process export completion + navigation (NOT settle — pdfx channel)
    await tester.pump();
    expect(find.byType(PdfPreviewScreen), findsOneWidget);
  });

  testWidgets('rename: confirming Save updates the AppBar title', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    await pushViewer(tester, repo, id: 3);

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'Receipts');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();

    expect(repo.renamedTo, contains('Receipts'));
    expect(find.widgetWithText(EditorTopBar, 'Receipts'), findsOneWidget);
    expect(find.widgetWithText(EditorTopBar, 'Scan X'), findsNothing);
  });

  testWidgets('rename is disabled in the error state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(throwOnGetPages: true));
    expect(find.byKey(const Key('page-viewer-error')), findsOneWidget);
    // Rename now lives in the overflow menu, disabled when the menu is.
    final menu = tester.widget<PopupMenuButton<String>>(
      find.byKey(const Key('page-viewer-page-menu')),
    );
    expect(menu.enabled, isFalse);
  });

  testWidgets('rename failure shows an error SnackBar and stays', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(throwOnRename: true);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
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
  testWidgets('E2: viewer renders page key when flatImagePath is set', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      pages: [
        const PageImage(
          position: 1,
          imagePath: '/nonexistent/page_1.jpg',
          flatImagePath: '/nonexistent/page_1_flat.jpg',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);
  });

  testWidgets('the editor actions carry accessible labels', (tester) async {
    await pushViewer(tester, FakeDocumentRepository());
    // The toolbar actions expose visible text labels (no tooltips in Ream).
    expect(find.text('Crop'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    // The overflow menu exposes Rename + Delete document as labeled items.
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-viewer-rename')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-delete')), findsOneWidget);
  });

  // ── E3 — re-edit crop corners ──────────────────────────────────────────

  testWidgets(
    'edit crop: toolbar button is present, enabled, and labeled Crop',
    (tester) async {
      await pushViewer(tester, FakeDocumentRepository());
      final btn = tester.widget<EditorToolbarButton>(
        find.byKey(const Key('page-viewer-edit')),
      );
      expect(btn.onPressed, isNotNull);
      expect(btn.label, 'Crop');
    },
  );

  testWidgets(
    'edit crop: accept returns corners, calls updatePageCorners, reloads viewer',
    (tester) async {
      const testCorners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );
      final repo = FakeDocumentRepository(
        pages: [
          const PageImage(
            position: 1,
            imagePath: '/nonexistent/page_1.jpg',
            corners: testCorners,
          ),
        ],
      );
      await pushViewer(tester, repo, id: 5);

      await tester.tap(find.byKey(const Key('page-viewer-edit')));
      await tester.pumpAndSettle();

      // EditCropScreen is now on top; Accept button is in AppBar (always visible).
      expect(find.byKey(const Key('edit-crop-accept')), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit-crop-accept')));
      await tester.pumpAndSettle();

      expect(repo.lastUpdatedCorners, testCorners);
      expect(repo.lastUpdatedPosition, 1);
      expect(find.byType(PageViewerScreen), findsOneWidget);
    },
  );

  testWidgets('edit crop: failure shows SnackBar and stays on viewer', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(throwOnUpdate: true);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-crop-accept')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't update crop"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });

  testWidgets('edit crop is disabled in the error state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(throwOnGetPages: true));
    final btn = tester.widget<EditorToolbarButton>(
      find.byKey(const Key('page-viewer-edit')),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('edit crop is disabled in the empty state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(pages: const []));
    final btn = tester.widget<EditorToolbarButton>(
      find.byKey(const Key('page-viewer-edit')),
    );
    expect(btn.onPressed, isNull);
  });

  // ── H2 — Page thumbnail strip ──────────────────────────────────────────

  testWidgets(
    'H2: strip is present with correct tile keys for 2-page document',
    (tester) async {
      // Two-page repo so the strip has two tiles.
      final repo = FakeDocumentRepository(
        pages: [
          const PageImage(position: 1, imagePath: '/nonexistent/h2a.jpg'),
          const PageImage(position: 2, imagePath: '/nonexistent/h2b.jpg'),
        ],
      );
      await pushViewer(tester, repo);

      expect(find.byKey(const Key('page-thumbnail-strip')), findsOneWidget);
      expect(find.byKey(const Key('page-thumb-0')), findsOneWidget);
      expect(find.byKey(const Key('page-thumb-1')), findsOneWidget);
    },
  );

  testWidgets('H2: tapping page-thumb-1 navigates PageView to page 2', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      pages: [
        const PageImage(position: 1, imagePath: '/nonexistent/h2a.jpg'),
        const PageImage(position: 2, imagePath: '/nonexistent/h2b.jpg'),
      ],
    );
    await pushViewer(tester, repo);

    // Initially on page 1 (index 0).
    expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);

    // Tap the second thumbnail (0-based index 1).
    await tester.tap(find.byKey(const Key('page-thumb-1')));
    await tester.pumpAndSettle();

    // PageView should have animated to index 1 → shows page at position 2.
    expect(find.byKey(const Key('page-viewer-page-2')), findsOneWidget);
  });

  // ── H3 — Reorder pages ─────────────────────────────────────────────────

  testWidgets(
    'H3: invoking onReorderItem(1,0) calls reorderPages([2,1]) and shows page 2 first',
    (tester) async {
      final repo = FakeDocumentRepository(
        pages: [
          const PageImage(position: 1, imagePath: '/nonexistent/r1.jpg'),
          const PageImage(position: 2, imagePath: '/nonexistent/r2.jpg'),
        ],
      );
      await pushViewer(tester, repo);

      final rlv = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      rlv.onReorderItem!(1, 0);
      await tester.pumpAndSettle();

      expect(repo.lastReorderedPositions, [2, 1]);
      expect(find.byKey(const Key('page-viewer-page-2')), findsOneWidget);
    },
  );

  testWidgets('H3: reorder failure shows SnackBar and stays on viewer', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      throwOnReorder: true,
      pages: [
        const PageImage(position: 1, imagePath: '/nonexistent/r1.jpg'),
        const PageImage(position: 2, imagePath: '/nonexistent/r2.jpg'),
      ],
    );
    await pushViewer(tester, repo);

    final rlv = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    rlv.onReorderItem!(1, 0);
    await tester.pumpAndSettle();

    expect(find.text("Couldn't reorder pages"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });
}
