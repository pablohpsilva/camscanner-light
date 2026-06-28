import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

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
}
