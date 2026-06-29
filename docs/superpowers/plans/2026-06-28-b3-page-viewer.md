# B3 — Page Viewer / Tap-to-Open Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap a document on the home list to open a full-screen, pinch-zoom page viewer, and delete a document (with confirmation) from that viewer.

**Architecture:** Two new read/write methods on the existing `DocumentRepository` (`getDocumentPages` returning an absolute-path `PageImage` view model; `deleteDocument` doing a row-first transactional delete + best-effort file cleanup). A new `PageViewerScreen` (loading/error+retry/empty/loaded states; `PageView` of full-res `InteractiveViewer` images; always-on `1 / N` indicator; delete via `showDialog<bool>` where the screen — not the dialog — owns the delete→pop/SnackBar sequence). The dumb `DocumentsListView` gains an optional `onOpen` callback; `HomeScreen` owns navigation and reloads on return.

**Tech Stack:** Flutter 3.44.4 (stable), Drift/SQLite (`store_date_time_values_as_text: true`), `bdd_widget_test` for integration, Nx (`pnpm nx run mobile:*`).

## Global Constraints

- **Privacy spine (binding):** documents never leave the device — no cloud, no network calls. The viewer renders on-device files only; delete removes local data only.
- **Relative paths, resolved at read time:** the DB stores `relativeImagePath`; the repository resolves to absolute via the injected `DocumentFileStore` on every read (iOS container GUID rule). The widget layer never touches the file store.
- **No schema change:** `schemaVersion` stays **1**; no new columns, no migration step.
- **Viewer decodes full-res (NO `cacheWidth`):** so zoom is usable. Its `Image.image` is therefore a **`FileImage`**, NOT the `ResizeImage` that B2's thumbnail asserts — do not copy B2's matcher.
- **Host-test image hazard:** a *loadable* `Image.file` path **hangs**/is unreliable in host tests; a *non-loadable* path settles and does not hang, but `errorBuilder` does not fire in `flutter_test`'s FakeAsync. Host tests use **non-loadable** paths and assert **wiring** (provider type, path, `errorBuilder != null`), never rendered pixels. Pixel rendering + zoom are REAL_DEVICE.
- **Delete is row-first, orphan-safe:** authoritative DB delete (pages then document, in one transaction), then best-effort `deleteDocumentDir`. Worst case = harmless orphan files. A non-existent id is a no-op.
- **BDD silent-stub guard:** `bdd_widget_test` silently generates an *empty stub* when a Gherkin step name does not map to its expected camelCase step file → a vacuous pass. Every new step's generated wiring MUST be confirmed to call a real, asserting implementation.
- **Coverage floor 70%** (excluding `*.g.dart`).
- **REAL_DEVICE deferred-with-sign-off:** the Tier-3 OS-kill + pixel-zoom checks are opt-in (`REAL_DEVICE=1`), not gated, consistent with B1/B2.
- **Personal `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` stays uncommitted** — never `git add` it.

---

## File Structure

**Create:**
- `apps/mobile/lib/features/library/page_image.dart` — `PageImage` view model.
- `apps/mobile/lib/features/library/page_viewer_screen.dart` — the viewer screen.
- `apps/mobile/test/features/library/page_viewer_screen_test.dart` — viewer widget tests.
- `apps/mobile/integration_test/b3_view_and_delete.feature` — Tier-2 scenario (+ generated `_test.dart`).
- `apps/mobile/test/step/i_open_the_first_document.dart`
- `apps/mobile/test/step/i_delete_the_open_document.dart`
- `apps/mobile/test/step/the_document_is_gone_from_the_home.dart`
- `scripts/verify/b3.sh` — the B3 gate.

**Modify:**
- `apps/mobile/lib/features/library/document_repository.dart` — add `getDocumentPages` + `deleteDocument`.
- `apps/mobile/lib/features/library/drift/drift_document_repository.dart` — implement both.
- `apps/mobile/lib/features/library/widgets/documents_list_view.dart` — optional `onOpen`.
- `apps/mobile/lib/features/library/home_screen.dart` — `_openDocument` + pass `onOpen`.
- `apps/mobile/test/support/fake_library.dart` — fake `getDocumentPages` + `deleteDocument`.
- `apps/mobile/test/features/library/documents_list_view_test.dart` — `onOpen`-fires test.
- `apps/mobile/test/features/library/drift_document_repository_test.dart` — `getDocumentPages` + delete + Tier-1 durability tests.

**Reused as-is (Tier-2 Given/When):** `test/step/a_document_was_saved_to_persistent_storage_earlier.dart`, `test/step/the_app_launches_reading_that_same_storage.dart`, `test/support/persistent_storage.dart`, `test/support/fake_scan.dart`.

---

## Task 1: `PageImage` + `getDocumentPages` (read model + read query)

**Files:**
- Create: `apps/mobile/lib/features/library/page_image.dart`
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`
- Test: `apps/mobile/test/features/library/drift_document_repository_test.dart`

**Interfaces:**
- Consumes (existing): `DriftDocumentRepository` ctor `({required AppDatabase db, required ImageMetadataScrubber scrubber, required DocumentFileStore fileStore, required DateTime Function() clock})`; `DocumentFileStore.absoluteFor(String rel) → File`, `.relativeFor(int docId, int position) → String`; `AppDatabase`, `PagesCompanion`, `DocumentsCompanion`.
- Produces: `class PageImage { final int position; final String imagePath; const PageImage(...) }`; `DocumentRepository.getDocumentPages(int documentId) → Future<List<PageImage>>` (position asc, absolute paths, empty if none).

- [ ] **Step 1: Write the failing repo test**

Add to `apps/mobile/test/features/library/drift_document_repository_test.dart` (this file already imports `dart:io`, `package:drift/native.dart`, `flutter_test`, the repo, `app_database.dart`, `JpegExifScrubber`, `CapturedImage`, `DocumentFileStore`; add the import below at the top with the others):

```dart
import 'package:mobile/features/library/page_image.dart';
```

Add these tests inside `main()` (the `repo()` helper, `base`, `db`, `capture`, `clock` are already defined in this file):

```dart
  test('getDocumentPages returns pages position-asc with absolute paths',
      () async {
    final doc = await repo().createFromCapture(capture);
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: doc.id,
        position: 2,
        relativeImagePath: 'documents/${doc.id}/page_2.jpg'));

    final pages = await repo().getDocumentPages(doc.id);

    expect(pages.map((p) => p.position), [1, 2]);
    expect(pages.first.imagePath, startsWith(base.path));
    expect(pages.first.imagePath, endsWith('documents/${doc.id}/page_1.jpg'));
    expect(pages.first.imagePath.startsWith('/'), isTrue,
        reason: 'viewer needs an absolute path resolved at read time');
  });

  test('getDocumentPages returns empty for a document with no pages', () async {
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'empty',
        createdAt: DateTime.utc(2026, 1, 1),
        modifiedAt: DateTime.utc(2026, 1, 1)));
    expect(await repo().getDocumentPages(id), isEmpty);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart`
Expected: compile/analysis FAIL — `getDocumentPages` is not defined and `page_image.dart` does not exist.

- [ ] **Step 3: Create the `PageImage` view model**

Create `apps/mobile/lib/features/library/page_image.dart`:

```dart
/// One page's resolved image for the viewer. [imagePath] is ABSOLUTE (resolved
/// at read time via DocumentFileStore) — the widget layer never touches the
/// file store. Symmetric with DocumentSummary on the read side.
class PageImage {
  final int position;
  final String imagePath;
  const PageImage({required this.position, required this.imagePath});
}
```

- [ ] **Step 4: Add the interface method**

In `apps/mobile/lib/features/library/document_repository.dart`, add the import and the method to the `abstract interface class DocumentRepository`:

```dart
import 'page_image.dart';
```

```dart
  /// Pages of [documentId], position ascending, with ABSOLUTE image paths
  /// (resolved at read time). Empty when the document has no pages.
  Future<List<PageImage>> getDocumentPages(int documentId);
```

- [ ] **Step 5: Implement in the Drift repository**

In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`, add the import (with the other `../` imports) and the method (place it after `listDocumentSummaries`):

```dart
import '../page_image.dart';
```

```dart
  @override
  Future<List<PageImage>> getDocumentPages(int documentId) async {
    final pages = await (_db.select(_db.pages)
          ..where((t) => t.documentId.equals(documentId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    return pages
        .map((pg) => PageImage(
              position: pg.position,
              imagePath: _fileStore.absoluteFor(pg.relativeImagePath).path,
            ))
        .toList();
  }
```

(`equals`/`OrderingTerm` come from `package:drift/drift.dart`, already imported in this file. This query shape was proven by the B3 delete-durability spike.)

- [ ] **Step 6: Implement in the fake**

In `apps/mobile/test/support/fake_library.dart`: add the import, the new fields, and the method. Add the import with the others:

```dart
import 'package:mobile/features/library/page_image.dart';
```

Extend the `FakeDocumentRepository` constructor + fields. Replace the field block and constructor head with:

```dart
  final bool throwOnCreate;
  final bool throwOnList;
  final bool throwOnGetPages;
  final bool throwOnDelete;
  final Completer<void>? gate;
  final List<Document> documents;
  final List<PageImage>? pages; // null => synthesize one non-loadable page
  int createCalls = 0;
  final List<int> deletedIds = <int>[];

  FakeDocumentRepository({
    this.throwOnCreate = false,
    this.throwOnList = false,
    this.throwOnGetPages = false,
    this.throwOnDelete = false,
    this.gate,
    List<Document>? documents,
    this.pages,
  }) : documents = documents ?? <Document>[];
```

Add the method (alongside the other overrides):

```dart
  @override
  Future<List<PageImage>> getDocumentPages(int documentId) async {
    if (throwOnGetPages) throw StateError('fake: getDocumentPages failed');
    return pages ??
        [PageImage(position: 1, imagePath: '/nonexistent/page-$documentId-1.jpg')];
  }
```

Do **not** add `deleteDocument` to the fake in this task: the interface does not declare it until Task 2, so an `@override` here would annotate a non-overriding member and fail `flutter analyze` (Step 8). The `throwOnDelete` and `deletedIds` fields added above are public, so they raise no unused-field warning while they sit idle until Task 2.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart`
Expected: PASS (all existing tests + the two new `getDocumentPages` tests).

- [ ] **Step 8: Analyze**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add apps/mobile/lib/features/library/page_image.dart \
        apps/mobile/lib/features/library/document_repository.dart \
        apps/mobile/lib/features/library/drift/drift_document_repository.dart \
        apps/mobile/test/support/fake_library.dart \
        apps/mobile/test/features/library/drift_document_repository_test.dart
git commit -m "feat(b3): PageImage read model + getDocumentPages (position-asc, absolute paths)"
```

---

## Task 2: `deleteDocument` (row-first transactional delete + durability)

**Files:**
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/test/support/fake_library.dart` (add the `deleteDocument` override — fields exist from Task 1)
- Test: `apps/mobile/test/features/library/drift_document_repository_test.dart`

**Interfaces:**
- Consumes (existing): `DocumentFileStore.deleteDocumentDir(int docId) → Future<void>` (guards `if (await dir.exists())`); `_db.transaction(...)`, `_db.delete(table)`.
- Produces: `DocumentRepository.deleteDocument(int documentId) → Future<void>` — row-first (pages then document in one transaction), then best-effort dir delete; non-existent id is a no-op.

- [ ] **Step 1: Write the failing repo tests**

Add to `apps/mobile/test/features/library/drift_document_repository_test.dart` inside `main()`:

```dart
  test('deleteDocument removes the document, its pages, and its on-disk dir',
      () async {
    final doc = await repo().createFromCapture(capture);
    final dir = Directory('${base.path}/documents/${doc.id}');
    expect(dir.existsSync(), isTrue);

    await repo().deleteDocument(doc.id);

    expect(await db.select(db.documents).get(), isEmpty);
    expect(await db.select(db.pages).get(), isEmpty);
    expect(dir.existsSync(), isFalse);
  });

  test('deleteDocument on a non-existent id is a no-op (no throw)', () async {
    await repo().deleteDocument(99999); // never inserted
    expect(await db.select(db.documents).get(), isEmpty);
  });

  test('Tier 1: a delete is durable across a DB close/reopen on disk',
      () async {
    final dir = Directory.systemTemp.createTempSync('b3delpersist');
    final dbFile = File('${dir.path}/camscanner.sqlite');
    final fixture = File('test/fixtures/exif_sample.jpg').readAsBytesSync();
    final src = File('${dir.path}/cap.jpg')..writeAsBytesSync(fixture);

    final db1 = AppDatabase(NativeDatabase(dbFile));
    final repo1 = DriftDocumentRepository(
      db: db1,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(dir),
      clock: () => DateTime.utc(2026, 6, 27, 9),
    );
    final saved = await repo1.createFromCapture(CapturedImage(src.path));
    await repo1.deleteDocument(saved.id);
    await db1.close(); // destroy the connection

    final db2 = AppDatabase(NativeDatabase(dbFile)); // brand-new, same file
    final repo2 = DriftDocumentRepository(
      db: db2,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(dir),
      clock: () => DateTime.utc(2026, 6, 27, 9),
    );
    final summaries = await repo2.listDocumentSummaries();
    final pages = await repo2.getDocumentPages(saved.id);
    await db2.close();
    final dirGone = !Directory('${dir.path}/documents/${saved.id}').existsSync();
    dir.deleteSync(recursive: true);

    expect(summaries, isEmpty, reason: 'the delete must survive a reopen');
    expect(pages, isEmpty);
    expect(dirGone, isTrue);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart`
Expected: FAIL — `deleteDocument` is not defined on `DocumentRepository`.

- [ ] **Step 3: Add the interface method**

In `apps/mobile/lib/features/library/document_repository.dart`, add to the interface:

```dart
  /// Deletes [documentId], its pages, and its on-disk image files. Row-first:
  /// an authoritative DB delete (pages then document, one transaction), then a
  /// best-effort file cleanup. A non-existent id is a no-op.
  Future<void> deleteDocument(int documentId);
```

- [ ] **Step 4: Implement in the Drift repository**

In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`, add after `getDocumentPages`:

```dart
  @override
  Future<void> deleteDocument(int documentId) async {
    // Row-first: the DB delete is authoritative. Explicit page delete (not
    // relying solely on the FK cascade pragma), then the document row.
    await _db.transaction(() async {
      await (_db.delete(_db.pages)
            ..where((t) => t.documentId.equals(documentId)))
          .go();
      await (_db.delete(_db.documents)..where((t) => t.id.equals(documentId)))
          .go();
    });
    // Best-effort file cleanup AFTER commit. Worst case = harmless orphan files
    // (no row references them). deleteDocumentDir guards dir-absent.
    await _fileStore.deleteDocumentDir(documentId);
  }
```

- [ ] **Step 5: Add the fake override**

In `apps/mobile/test/support/fake_library.dart`, add the `deleteDocument` override (the `throwOnDelete` and `deletedIds` fields already exist from Task 1; add the method alongside the other overrides):

```dart
  @override
  Future<void> deleteDocument(int documentId) async {
    if (throwOnDelete) throw StateError('fake: delete failed');
    deletedIds.add(documentId);
    documents.removeWhere((d) => d.id == documentId);
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart`
Expected: PASS (including the three new delete tests). These exact semantics were proven by the B3 delete-durability spike on Flutter 3.44.4.

- [ ] **Step 7: Analyze**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/document_repository.dart \
        apps/mobile/lib/features/library/drift/drift_document_repository.dart \
        apps/mobile/test/support/fake_library.dart \
        apps/mobile/test/features/library/drift_document_repository_test.dart
git commit -m "feat(b3): deleteDocument — row-first transactional delete + durable across reopen"
```

---

## Task 3: `PageViewerScreen` (states, full-res zoom, delete sequence)

**Files:**
- Create: `apps/mobile/lib/features/library/page_viewer_screen.dart`
- Test: `apps/mobile/test/features/library/page_viewer_screen_test.dart`

**Interfaces:**
- Consumes: `DocumentRepository.getDocumentPages(int) → Future<List<PageImage>>`, `.deleteDocument(int) → Future<void>`; `PageImage{position, imagePath}`; `FakeDocumentRepository({bool throwOnGetPages, bool throwOnDelete, List<PageImage>? pages, ...})` with `List<int> deletedIds`.
- Produces: `class PageViewerScreen extends StatefulWidget` with ctor `({Key? key, required int documentId, required String name, required DocumentRepository repository})`. Keys: `page-viewer-loading`, `page-viewer-error`, `page-viewer-retry`, `page-viewer-empty`, `page-viewer-page-<position>`, `page-viewer-indicator`, `page-viewer-delete`, `page-viewer-delete-cancel`, `page-viewer-delete-confirm`.

- [ ] **Step 1: Write the failing widget tests**

Create `apps/mobile/test/features/library/page_viewer_screen_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_screen_test.dart`
Expected: compile FAIL — `page_viewer_screen.dart` does not exist.

- [ ] **Step 3: Implement the viewer**

Create `apps/mobile/lib/features/library/page_viewer_screen.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import 'document_repository.dart';
import 'page_image.dart';

/// Full-screen page viewer: pinch-zoom + pan over a document's page(s).
/// Multi-page-ready (PageView; one page today). Loads pages on init and shows
/// loading / error+retry / empty / loaded. The delete action confirms, deletes
/// (row + files), and pops back to the list. The SCREEN owns the delete
/// sequence; the dialog only returns the user's choice.
///
/// Decodes full-resolution (no cacheWidth) so zoom is usable — its Image is a
/// FileImage, NOT a ResizeImage. NOTE: this is not memory-safe for many pages;
/// when multi-page capture lands, add decode management (screen-width cacheWidth
/// + offscreen dispose).
class PageViewerScreen extends StatefulWidget {
  final int documentId;
  final String name;
  final DocumentRepository repository;
  const PageViewerScreen({
    super.key,
    required this.documentId,
    required this.name,
    required this.repository,
  });

  @override
  State<PageViewerScreen> createState() => _PageViewerScreenState();
}

class _PageViewerScreenState extends State<PageViewerScreen> {
  final PageController _controller = PageController();
  List<PageImage>? _pages;
  bool _loading = true;
  bool _error = false;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final pages = await widget.repository.getDocumentPages(widget.documentId);
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _confirmAndDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text("Delete this document? This can't be undone."),
        actions: [
          TextButton(
            key: const Key('page-viewer-delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('page-viewer-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repository.deleteDocument(widget.documentId);
      if (!mounted) return;
      Navigator.of(context).pop(); // leave the viewer -> Home._load() reflects it
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            key: const Key('page-viewer-delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: _loading ? null : _confirmAndDelete,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              key: Key('page-viewer-loading'),
              child: CircularProgressIndicator())
          : _error
              ? _buildError()
              : (_pages == null || _pages!.isEmpty)
                  ? _buildEmpty()
                  : _buildPages(_pages!),
    );
  }

  Widget _buildError() => Center(
        key: const Key('page-viewer-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Couldn't load this document."),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('page-viewer-retry'),
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _buildEmpty() => const Center(
        key: Key('page-viewer-empty'),
        child: Text('This document has no pages.'),
      );

  Widget _buildPages(List<PageImage> pages) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: pages.length,
          onPageChanged: (i) => setState(() => _current = i),
          itemBuilder: (context, i) {
            final pg = pages[i];
            return InteractiveViewer(
              key: Key('page-viewer-page-${pg.position}'),
              child: Image.file(
                File(pg.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 64),
                ),
              ),
            );
          },
        ),
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              '${_current + 1} / ${pages.length}',
              key: const Key('page-viewer-indicator'),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_screen_test.dart`
Expected: PASS (all seven tests). The non-loadable-path + no-hang behavior was proven by the B3 viewer host-test spike.

- [ ] **Step 5: Analyze**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!` (in particular, no `use_build_context_synchronously` — `mounted` is checked after each await).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/page_viewer_screen.dart \
        apps/mobile/test/features/library/page_viewer_screen_test.dart
git commit -m "feat(b3): PageViewerScreen — full-res zoom, states, screen-owned delete sequence"
```

---

## Task 4: Navigation wiring (tile `onOpen` + `HomeScreen` open/reload)

**Files:**
- Modify: `apps/mobile/lib/features/library/widgets/documents_list_view.dart`
- Modify: `apps/mobile/lib/features/library/home_screen.dart`
- Test: `apps/mobile/test/features/library/documents_list_view_test.dart`
- Test: `apps/mobile/test/features/library/home_screen_test.dart`

**Interfaces:**
- Consumes: `PageViewerScreen({required int documentId, required String name, required DocumentRepository repository})`; `DocumentSummary{document: Document{id, name}, ...}`.
- Produces: `DocumentsListView({required List<DocumentSummary> summaries, ValueChanged<DocumentSummary>? onOpen})`; `HomeScreen._openDocument(DocumentSummary)`.

- [ ] **Step 1: Write the failing `onOpen` test**

Add to `apps/mobile/test/features/library/documents_list_view_test.dart` inside `main()` (the `summary(int id)` helper already exists in this file):

```dart
  testWidgets('tapping a tile invokes onOpen with that summary', (tester) async {
    DocumentSummary? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentsListView(
          summaries: [summary(1), summary(2, pageCount: 3)],
          onOpen: (s) => opened = s,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('document-tile-2')));
    expect(opened, isNotNull);
    expect(opened!.document.id, 2);
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/documents_list_view_test.dart`
Expected: FAIL — `DocumentsListView` has no `onOpen` parameter.

- [ ] **Step 3: Add the optional `onOpen` to the list view**

In `apps/mobile/lib/features/library/widgets/documents_list_view.dart`, change the class to add the field and wire `onTap`:

```dart
class DocumentsListView extends StatelessWidget {
  final List<DocumentSummary> summaries;
  final ValueChanged<DocumentSummary>? onOpen;
  const DocumentsListView({super.key, required this.summaries, this.onOpen});
```

In the `ListTile`, add `onTap` (after the `subtitle:` line):

```dart
          onTap: onOpen == null ? null : () => onOpen!(s),
```

- [ ] **Step 4: Run the list test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/documents_list_view_test.dart`
Expected: PASS (existing render test + new `onOpen` test). Existing construction without `onOpen` still compiles because it is optional.

- [ ] **Step 5: Write the failing HomeScreen navigation test**

This file already has a `pumpHome(WidgetTester, FakeDocumentRepository)` helper and imports `Document`, `HomeScreen`, `fakeLibraryDependencies`, `grantedScanDependencies` — reuse them. Add this test inside `main()`, using a fake that lists one document so a tile is tappable (no new imports needed):

```dart
  testWidgets('tapping a document opens the page viewer', (tester) async {
    final repo = FakeDocumentRepository(documents: [
      Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42)),
    ]);
    await pumpHome(tester, repo);

    await tester.tap(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page-viewer-delete')), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Scan 2026-06-27 20.26.42'),
        findsOneWidget);
  });
```

- [ ] **Step 6: Run it to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/home_screen_test.dart`
Expected: FAIL — tapping the tile does nothing (no `onOpen` wired in `HomeScreen`).

- [ ] **Step 7: Wire navigation in `HomeScreen`**

In `apps/mobile/lib/features/library/home_screen.dart`, add the import:

```dart
import 'page_viewer_screen.dart';
```

Change the `DocumentsListView` construction in `build` to pass `onOpen`:

```dart
                  : DocumentsListView(
                      summaries: _summaries, onOpen: _openDocument),
```

Add the method (next to `_openScan`):

```dart
  Future<void> _openDocument(DocumentSummary s) async {
    final repo = _repository;
    if (repo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PageViewerScreen(
          documentId: s.document.id,
          name: s.document.name,
          repository: repo,
        ),
      ),
    );
    await _load(); // a delete may have happened in the viewer
  }
```

- [ ] **Step 8: Run both widget tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/home_screen_test.dart test/features/library/documents_list_view_test.dart`
Expected: PASS.

- [ ] **Step 9: Analyze**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add apps/mobile/lib/features/library/widgets/documents_list_view.dart \
        apps/mobile/lib/features/library/home_screen.dart \
        apps/mobile/test/features/library/documents_list_view_test.dart \
        apps/mobile/test/features/library/home_screen_test.dart
git commit -m "feat(b3): tap-to-open wiring — list onOpen callback + HomeScreen open/reload"
```

---

## Task 5: Tier-2 integration (open → view → delete → gone)

**Files:**
- Create: `apps/mobile/integration_test/b3_view_and_delete.feature`
- Create: `apps/mobile/test/step/i_open_the_first_document.dart`
- Create: `apps/mobile/test/step/i_delete_the_open_document.dart`
- Create: `apps/mobile/test/step/the_document_is_gone_from_the_home.dart`
- Generated: `apps/mobile/integration_test/b3_view_and_delete_test.dart` (by build_runner)

**Interfaces:**
- Consumes (reused B2 steps): `aDocumentWasSavedToPersistentStorageEarlier(tester)` (seeds doc id **1** into a fresh on-disk DB, no image file), `theAppLaunchesReadingThatSameStorage(tester)` (launches the app against that storage).
- Produces: three new step functions named EXACTLY `iOpenTheFirstDocument`, `iDeleteTheOpenDocument`, `theDocumentIsGoneFromTheHome` (camelCase of the Gherkin steps — a mismatch silently generates an empty stub).

- [ ] **Step 1: Write the feature file**

Create `apps/mobile/integration_test/b3_view_and_delete.feature`:

```gherkin
Feature: View and delete a document

  Scenario: Open a saved document, view its page, then delete it
    Given a document was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    And I delete the open document
    Then the document is gone from the home
```

- [ ] **Step 2: Write the three new step implementations**

Create `apps/mobile/test/step/i_open_the_first_document.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the first document
Future<void> iOpenTheFirstDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-tile-1')));
  await tester.pumpAndSettle();
  // The viewer is open (its delete action is present). The seeded document has
  // no image file on disk, so the page degrades to the broken-image placeholder
  // on-device — not a hang.
  expect(find.byKey(const Key('page-viewer-delete')), findsOneWidget);
}
```

Create `apps/mobile/test/step/i_delete_the_open_document.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I delete the open document
Future<void> iDeleteTheOpenDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-delete')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-delete-confirm')));
  await tester.pumpAndSettle();
}
```

Create `apps/mobile/test/step/the_document_is_gone_from_the_home.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the document is gone from the home
Future<void> theDocumentIsGoneFromTheHome(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // Back on the home, and the only document is gone.
  expect(find.widgetWithText(AppBar, 'Documents'), findsOneWidget);
  expect(find.byKey(const Key('document-tile-1')), findsNothing);
}
```

- [ ] **Step 3: Generate the BDD test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `Built with build_runner` and a new `integration_test/b3_view_and_delete_test.dart`.

- [ ] **Step 4: Verify the generated test wires the REAL steps (silent-stub guard)**

Run: `cat apps/mobile/integration_test/b3_view_and_delete_test.dart`
Expected — the generated `main()` calls all five steps in order and imports the three new step files from `./../test/step/`:

```
await aDocumentWasSavedToPersistentStorageEarlier(tester);
await theAppLaunchesReadingThatSameStorage(tester);
await iOpenTheFirstDocument(tester);
await iDeleteTheOpenDocument(tester);
await theDocumentIsGoneFromTheHome(tester);
```

Then confirm **no empty stub step files were generated** (a name mismatch would create a new, empty `test/step/*.dart`):

Run: `cd apps/mobile && git status --porcelain test/step/`
Expected: only the three files you authored appear as added — `i_open_the_first_document.dart`, `i_delete_the_open_document.dart`, `the_document_is_gone_from_the_home.dart`. If any OTHER new `test/step/*.dart` appears, a step name mismatched — fix the Gherkin/step name to match and re-generate. Also confirm each authored step file contains a real `expect(` or `tester.tap(` (not an empty stub body).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/integration_test/b3_view_and_delete.feature \
        apps/mobile/integration_test/b3_view_and_delete_test.dart \
        apps/mobile/test/step/i_open_the_first_document.dart \
        apps/mobile/test/step/i_delete_the_open_document.dart \
        apps/mobile/test/step/the_document_is_gone_from_the_home.dart
git commit -m "test(b3): Tier-2 integration — open, view, delete, gone (no stub steps)"
```

---

## Task 6: `scripts/verify/b3.sh` (the B3 gate)

**Files:**
- Create: `scripts/verify/b3.sh`

**Interfaces:**
- Consumes: `scripts/verify/lib.sh` helpers — `require_tool`, `assert_file_has`, `assert_cmd`, `assert_coverage_floor`, `verify_integration_android`, `verify_integration_ios`, `verify_summary`, and env `APP_ID`, `ADB`, `EVIDENCE_DIR`.

- [ ] **Step 1: Write the verify script**

Create `scripts/verify/b3.sh`:

```bash
#!/usr/bin/env bash
# Verify B3 (page viewer / tap-to-open + delete) acceptance criteria.
# Run: bash scripts/verify/b3.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 lane (pinch-zoom + post-delete OS-kill, manual).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== B3 verification =="

# ---- Tool preconditions ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence (static asserts) ----
assert_file_has "PageImage read model exists" \
  "apps/mobile/lib/features/library/page_image.dart" "class PageImage"
assert_file_has "repository exposes getDocumentPages" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<List<PageImage>> getDocumentPages(int documentId)"
assert_file_has "repository exposes deleteDocument" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<void> deleteDocument(int documentId)"
assert_file_has "delete is transactional (row-first)" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "deleteDocumentDir(documentId)"
assert_file_has "PageViewerScreen exists" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "class PageViewerScreen"
assert_file_has "viewer uses InteractiveViewer (zoom/pan)" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "InteractiveViewer"
assert_file_has "delete dialog returns a bool (screen owns the sequence)" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "showDialog<bool>"
assert_file_has "list view has the onOpen callback" \
  "apps/mobile/lib/features/library/widgets/documents_list_view.dart" "ValueChanged<DocumentSummary>? onOpen"
assert_file_has "home wires tap-to-open" \
  "apps/mobile/lib/features/library/home_screen.dart" "PageViewerScreen("
assert_file_has "no schema bump (schemaVersion stays 1)" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 1;"
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"

# ---- No-empty-stub guard: each new B3 step is a real implementation ----
assert_file_has "step: open document is real (not a stub)" \
  "apps/mobile/test/step/i_open_the_first_document.dart" "tester.tap"
assert_file_has "step: delete document is real (not a stub)" \
  "apps/mobile/test/step/i_delete_the_open_document.dart" "page-viewer-delete-confirm"
assert_file_has "step: gone-from-home is real (not a stub)" \
  "apps/mobile/test/step/the_document_is_gone_from_the_home.dart" "findsNothing"
assert_file_has "generated b3 test calls the open step" \
  "apps/mobile/integration_test/b3_view_and_delete_test.dart" "iOpenTheFirstDocument(tester)"
assert_file_has "generated b3 test calls the delete step" \
  "apps/mobile/integration_test/b3_view_and_delete_test.dart" "iDeleteTheOpenDocument(tester)"

# ---- Generated code is current (Drift unchanged + new BDD test) ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (drift + b3 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/lib/features/library/drift/app_database.g.dart apps/mobile/integration_test/b3_view_and_delete_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria: unit + widget tests, analyze, coverage ----
assert_cmd "b3 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (BDD integration test) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android b3_view_and_delete_test.dart
verify_integration_ios b3_view_and_delete_test.dart

# ---- Opt-in REAL_DEVICE Tier-3: pinch-zoom + post-delete OS-kill ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  rdev="$("$ADB" devices | awk '/device$/{print $1; exit}')"
  if [ -z "$rdev" ]; then
    fail "REAL_DEVICE: no Android device connected"
  else
    "$ADB" -s "$rdev" exec-out screencap -p > "$EVIDENCE_DIR/b3-real-viewer.png" 2>/dev/null
    pass "REAL_DEVICE: captured viewer screen (evidence: b3-real-viewer.png)"
    echo "REAL_DEVICE Tier-3 (MANUAL): (1) open a document, pinch-zoom — the page MAGNIFIES and renders UPRIGHT; (2) delete it, then 'adb shell am force-stop $APP_ID' + relaunch — the document is still GONE."
  fi
  echo "REAL_DEVICE (iOS): MANUAL — confirm pinch-zoom magnifies + upright, and a deleted document stays gone after an OS kill on a physical iPhone."
fi

verify_summary
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/verify/b3.sh`

- [ ] **Step 3: Static + negative-control smoke (no device)**

Run: `VERIFY_SKIP_DEVICE=1 bash scripts/verify/b3.sh; echo "exit=$?"`
Expected: the static asserts run; the run ends with `GATE: FAIL` and `exit=1` (fail-closed because device checks were skipped — this proves the negative control, it is NOT a real pass).

- [ ] **Step 4: Commit**

```bash
git add scripts/verify/b3.sh
git commit -m "test(b3): verification gate — static asserts, no-stub guard, integration, REAL_DEVICE lane"
```

- [ ] **Step 5: Full gate (with devices)**

Run: `bash scripts/verify/b3.sh`
Expected: `GATE: PASS` (exit 0) — all static asserts, host tests, analyze, coverage ≥70%, and the Android + iOS integration tests pass.

---

## Self-Review

**1. Spec coverage** (each spec section → task):
- `PageImage` + `getDocumentPages` (no N+1, position-asc, absolute) → Task 1.
- `deleteDocument` row-first + durability + idempotent + dir-absent → Task 2 (semantics proven by spike 2).
- `PageViewerScreen` states (loading/error+retry/empty/loaded), full-res `InteractiveViewer`+`PageView`, always-on `1 / N` indicator, screen-owned delete (showDialog<bool> → pop/SnackBar), `FileImage` not `ResizeImage` → Task 3 (host-test behavior proven by spike 3).
- Optional `onOpen` (existing tests keep compiling) + `HomeScreen` open/reload → Task 4.
- Tier-2 feature + steps + silent-stub guard → Task 5.
- Verify harness (static asserts, no-stub guard, integration, coverage floor 70, fail-closed, REAL_DEVICE Tier-3) → Task 6.
- Gaps F–P all map: F (migration surface — Tasks 1/2/4 + optional onOpen), G (delete-error test — Task 3), H (full-res memory note — Task 3 doc), I (orphan-safety review-enforced — not over-claimed as gated; Task 2 tests the happy path), J (zoom bitmap-scaling note — Task 3 doc), K (silent-stub guard — Task 5 Step 4 + Task 6), L (state keys + retry — Task 3), M (always-on indicator — Task 3), N (load-error test — Task 3), O (delete sequence — Task 3), P (load-error acceptance — Task 3 covers state).
- REAL_DEVICE criteria 9–10 → Task 6 opt-in lane (deferred, not gated).

**2. Placeholder scan:** none — every code step contains complete code; every run step has an exact command + expected output.

**3. Type consistency:** `PageImage{position:int, imagePath:String}` is identical across Tasks 1/3; `getDocumentPages(int)→Future<List<PageImage>>` and `deleteDocument(int)→Future<void>` match interface, drift impl, and fake; `DocumentsListView({required summaries, onOpen})` matches Task 4 test + HomeScreen call; keys used in Task 3 tests (`page-viewer-*`) match the widget; `FakeDocumentRepository` fields (`throwOnGetPages`, `throwOnDelete`, `pages`, `deletedIds`) defined in Task 1 are used in Task 3.
```
