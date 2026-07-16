import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_controller.dart';
import 'package:mobile/features/library/view_state.dart';

import '../../support/fake_library.dart';

/// Unit tests for the page-viewer orchestration (P06 tasks 5-8) — NO widget is
/// pumped; the controller is a plain ChangeNotifier like SaveController.
void main() {
  List<PageImage> threePages() => [
    for (var i = 1; i <= 3; i++)
      PageImage(position: i, imagePath: '/nonexistent/p$i.jpg'),
  ];

  PageViewerController make(FakeDocumentRepository repo) =>
      PageViewerController(
        repository: repo,
        documentId: 1,
        name: 'Doc',
        clearImageCache: () {},
      );

  group('load', () {
    test('success → Loaded(pages)', () async {
      final c = make(FakeDocumentRepository(pages: threePages()));
      await c.load();
      expect(c.state, isA<Loaded<List<PageImage>>>());
      expect(c.pages, hasLength(3));
    });

    test('empty → Empty', () async {
      final c = make(FakeDocumentRepository(pages: const []));
      await c.load();
      expect(c.state, isA<Empty<List<PageImage>>>());
    });

    test('failure → ErrorState', () async {
      final c = make(FakeDocumentRepository(throwOnGetPages: true));
      await c.load();
      expect(c.state, isA<ErrorState<List<PageImage>>>());
    });
  });

  test('reloadAfterEdit clears the image cache and bumps the epoch', () async {
    var cleared = 0;
    final c = PageViewerController(
      repository: FakeDocumentRepository(pages: threePages()),
      documentId: 1,
      name: 'Doc',
      clearImageCache: () => cleared++,
    );
    await c.load();
    final epoch = c.imageEpoch;
    await c.reloadAfterEdit();
    expect(cleared, 1);
    expect(c.imageEpoch, epoch + 1);
  });

  group('deletePage', () {
    test(
      'surviving document reloads + returns remaining, re-clamps current',
      () async {
        final c = make(FakeDocumentRepository(pages: threePages()));
        await c.load();
        c.setCurrent(2); // last page
        final remaining = await c.deletePage(3);
        expect(remaining, 2);
        expect(c.pages, hasLength(2));
        expect(c.current, 1, reason: 'current clamped to new last index');
      },
    );

    test('deleting the only page returns 0 (widget pops)', () async {
      final c = make(
        FakeDocumentRepository(
          pages: [PageImage(position: 1, imagePath: '/nonexistent/p1.jpg')],
        ),
      );
      await c.load();
      expect(await c.deletePage(1), 0);
    });

    test('failure returns null', () async {
      final c = make(
        FakeDocumentRepository(pages: threePages(), throwOnDeletePage: true),
      );
      await c.load();
      expect(await c.deletePage(1), isNull);
    });
  });

  group('edits (single-flight)', () {
    test('rotate persists + reloads, returns true', () async {
      final repo = FakeDocumentRepository(pages: threePages());
      final c = make(repo);
      await c.load();
      expect(await c.rotatePage(1), isTrue);
    });

    test('rotate failure returns false', () async {
      final repo = FakeDocumentRepository(
        pages: threePages(),
        throwOnUpdate: true,
      );
      final c = make(repo);
      await c.load();
      expect(await c.rotatePage(1), isFalse);
    });
  });

  group('reorder', () {
    test('persist success returns true and applies the new order', () async {
      final repo = FakeDocumentRepository(pages: threePages());
      final c = make(repo);
      await c.load();
      final ok = await c.reorder(0, 2); // move page 1 to the end
      expect(ok, isTrue);
      expect(repo.lastReorderedPositions, isNotEmpty);
    });

    test('persist failure rolls back (reloads) and returns false', () async {
      final repo = FakeDocumentRepository(
        pages: threePages(),
        throwOnReorder: true,
      );
      final c = make(repo);
      await c.load();
      final ok = await c.reorder(0, 2);
      expect(ok, isFalse);
      expect(c.pages, hasLength(3)); // reloaded to persisted order
      expect(c.editing, isFalse);
    });
  });

  group('export (exporting overlay)', () {
    test('exportPdf toggles exporting and returns a file', () async {
      final c = make(FakeDocumentRepository(pages: threePages()));
      await c.load();
      final busy = <bool>[];
      c.addListener(() => busy.add(c.exporting));
      final file = await c.exportPdf(ExportQuality.original);
      expect(file, isNotNull);
      expect(c.exporting, isFalse);
      expect(busy, contains(true)); // went busy then idle
    });

    test('exportPdf failure returns null and clears exporting', () async {
      final c = make(
        FakeDocumentRepository(pages: threePages(), throwOnExport: true),
      );
      await c.load();
      expect(await c.exportPdf(ExportQuality.original), isNull);
      expect(c.exporting, isFalse);
    });
  });

  test('rename updates the name on success', () async {
    final c = make(FakeDocumentRepository(pages: threePages()));
    await c.load();
    expect(await c.rename('New Name'), isTrue);
    expect(c.name, 'New Name');
  });

  test('suppresses notifications after dispose', () async {
    final c = make(FakeDocumentRepository(pages: threePages()));
    await c.load();
    var notified = false;
    c.addListener(() => notified = true);
    c.dispose();
    await c.load();
    expect(notified, isFalse);
  });
}
