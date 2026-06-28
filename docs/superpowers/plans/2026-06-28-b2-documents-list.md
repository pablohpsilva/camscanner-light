# B2 — Documents list reads from storage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the home Documents list into a rich list that reads richer data from storage — each saved document shows a thumbnail, name, date, and page count — and prove saved documents survive an app restart.

**Architecture:** Add a `DocumentSummary` read model and a `listDocumentSummaries()` repository read computed with grouped/aggregate Drift queries (no N+1). Render each row's first page via `Image.file` + `cacheWidth` in a focused `DocumentThumbnail` widget (upright for free via the kept EXIF Orientation tag; non-loadable paths degrade to a placeholder, which also avoids the host-test hang). Prove persistence with a host-level DB close/reopen test (Tier 1) and a fresh-launch-reads-storage integration test (Tier 2). No schema change.

**Tech Stack:** Flutter (Dart `^3.12.2`), Drift/SQLite, `path`, `flutter_test`, `bdd_widget_test` + `build_runner`, bash verify harness on `scripts/verify/lib.sh`.

## Global Constraints

- **Privacy spine (binding):** documents never leave the device. No cloud, no network calls. Thumbnails render from the same on-device files; nothing is uploaded, cached off-device, or indexed externally.
- **No schema change:** page count and thumbnail path are derived at read time. `schemaVersion` stays **1**; add **no** columns and **no** migration. `app_database.g.dart` must not change.
- **Relative paths only:** image paths are stored relative (`documents/<docId>/page_<pos>.jpg`); relative→absolute resolution happens in the **repository** at read time (fresh each launch), never stored absolute.
- **Scrubber untouched:** `JpegExifScrubber` (byte-level, keeps Orientation) is not modified. Its tests keep passing (privacy regression).
- **First page = `MIN(position)`**, not literally `position == 1`.
- **Newest-first** ordering (by `createdAt` desc) is preserved.
- **No N+1:** the list read uses at most two queries total (one grouped count + one first-page lookup), zipped in Dart.
- **Host-test image safety:** in host tests, thumbnail paths are deliberately **non-loadable** (a real loadable file in `Image.file` hangs host widget tests). Actual pixel rendering is verified on-device (REAL_DEVICE lane), not in host tests.
- **Verify discipline:** silence = FAIL; assert exit codes + markers; `--skip-nx-cache`; negative control (`VERIFY_SKIP_DEVICE=1 → GATE: FAIL`); REAL_DEVICE Tier-3 (true OS-kill) is opt-in/manual, deferred-with-sign-off like B1.
- **TDD/BDD-first, SOLID/KISS/DRY**, frequent commits.

All commands run from the repo root unless noted. The Flutter app lives at `apps/mobile` (package `mobile`).

---

### Task 1: `DocumentSummary` read model + `listDocumentSummaries()` (additive)

Adds the new read model and read **alongside** the existing `listDocuments()` so the tree stays green; `listDocuments()` is retired in Task 3.

**Files:**
- Create: `apps/mobile/lib/features/library/document_summary.dart`
- Modify: `apps/mobile/lib/features/library/document_repository.dart` (add interface method)
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart` (implement)
- Modify: `apps/mobile/test/support/fake_library.dart` (fake implements the new method)
- Test: `apps/mobile/test/features/library/drift_document_repository_test.dart` (add summary + Tier-1 tests)

**Interfaces:**
- Consumes (existing): `Document` (`document.dart`); `DocumentFileStore.absoluteFor(String) → File`; `AppDatabase` with `documents`/`pages` tables, `DocumentsCompanion`, `PagesCompanion`; `NativeDatabase` (`package:drift/native.dart`).
- Produces (used by Tasks 2-4):
  - `class DocumentSummary { final Document document; final int pageCount; final String? thumbnailPath; const DocumentSummary({required this.document, required this.pageCount, this.thumbnailPath}); }`
  - `Future<List<DocumentSummary>> DocumentRepository.listDocumentSummaries()` — newest first; `thumbnailPath` is an **absolute** path or `null`.

- [ ] **Step 1: Write the read-model file**

Create `apps/mobile/lib/features/library/document_summary.dart`:

```dart
import 'document.dart';

/// Read model for the documents list: a [Document] plus its page count and the
/// absolute path to its first page's image (for the thumbnail). Built by the
/// repository at read time; [thumbnailPath] is already resolved to an ABSOLUTE
/// path (relative→absolute happens in the repository, fresh each launch) and is
/// null when the document has no page.
class DocumentSummary {
  final Document document;
  final int pageCount;
  final String? thumbnailPath;

  const DocumentSummary({
    required this.document,
    required this.pageCount,
    this.thumbnailPath,
  });
}
```

- [ ] **Step 2: Add the interface method (keep `listDocuments`)**

In `apps/mobile/lib/features/library/document_repository.dart`, add the import and the method to the `abstract interface class DocumentRepository`:

```dart
import '../scan/captured_image.dart';
import 'document.dart';
import 'document_summary.dart';
```

```dart
  /// All documents, newest first.
  Future<List<Document>> listDocuments();

  /// All documents (newest first) with page count and first-page thumbnail path
  /// (absolute, resolved at read time; null when the document has no page).
  Future<List<DocumentSummary>> listDocumentSummaries();
```

- [ ] **Step 3: Write the failing repository tests**

Append these tests to `apps/mobile/test/features/library/drift_document_repository_test.dart` (inside `main()`, after the existing tests). Also add the import near the top:

```dart
import 'package:mobile/features/library/document_summary.dart';
```

```dart
  test('listDocumentSummaries reports page count and first-page path',
      () async {
    final doc = await repo().createFromCapture(capture);
    // Add a second page directly (multi-page capture is not built yet).
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: doc.id,
        position: 2,
        relativeImagePath: 'documents/${doc.id}/page_2.jpg'));

    final summaries = await repo().listDocumentSummaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.document.id, doc.id);
    expect(summaries.single.pageCount, 2);
    expect(summaries.single.thumbnailPath, startsWith(base.path));
    expect(summaries.single.thumbnailPath,
        endsWith('documents/${doc.id}/page_1.jpg'),
        reason: 'first page is MIN(position) = position 1');
  });

  test('listDocumentSummaries returns newest first', () async {
    final fixture = File('test/fixtures/exif_sample.jpg').readAsBytesSync();
    void seedSource() => File(capture.path).writeAsBytesSync(fixture);

    var t = DateTime.utc(2026, 6, 27, 10);
    final r = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: () => t,
    );
    seedSource();
    await r.createFromCapture(capture);
    t = DateTime.utc(2026, 6, 27, 12);
    seedSource();
    await r.createFromCapture(capture);

    final s = await r.listDocumentSummaries();
    expect(s, hasLength(2));
    expect(s.first.document.createdAt.isAfter(s.last.document.createdAt), isTrue);
  });

  test('a document with no page yields pageCount 0 and a null thumbnail',
      () async {
    await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'orphan',
        createdAt: DateTime.utc(2026, 1, 1),
        modifiedAt: DateTime.utc(2026, 1, 1)));
    final s = await repo().listDocumentSummaries();
    expect(s.single.pageCount, 0);
    expect(s.single.thumbnailPath, isNull);
  });

  test('Tier 1: documents persist across a DB close/reopen on disk', () async {
    final dir = Directory.systemTemp.createTempSync('b2persist');
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
    await db1.close();

    final db2 = AppDatabase(NativeDatabase(dbFile));
    final repo2 = DriftDocumentRepository(
      db: db2,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(dir),
      clock: () => DateTime.utc(2026, 6, 27, 9),
    );
    final summaries = await repo2.listDocumentSummaries();
    await db2.close();
    dir.deleteSync(recursive: true);

    expect(summaries, hasLength(1));
    expect(summaries.single.document.id, saved.id);
    expect(summaries.single.pageCount, 1);
    expect(summaries.single.thumbnailPath, endsWith('page_1.jpg'));
  });
```

- [ ] **Step 4: Run the tests — verify they fail to compile**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart`
Expected: FAIL — `listDocumentSummaries` is not defined on `DriftDocumentRepository` (and the interface is abstract).

- [ ] **Step 5: Implement `listDocumentSummaries()` in the Drift repository**

In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`, add the import and the method (keep `listDocuments`):

```dart
import '../document_summary.dart';
```

```dart
  @override
  Future<List<DocumentSummary>> listDocumentSummaries() async {
    // (1) page count per document, newest doc first — one grouped query.
    final pageCount = _db.pages.id.count();
    final query = _db.select(_db.documents).join([
      leftOuterJoin(_db.pages, _db.pages.documentId.equalsExp(_db.documents.id)),
    ])
      ..addColumns([pageCount])
      ..groupBy([_db.documents.id])
      ..orderBy([OrderingTerm.desc(_db.documents.createdAt)]);
    final rows = await query.get();

    // (2) lowest-position page path per document — one query, no N+1.
    final pages = await (_db.select(_db.pages)
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final firstPathByDoc = <int, String>{};
    for (final pg in pages) {
      firstPathByDoc.putIfAbsent(pg.documentId, () => pg.relativeImagePath);
    }

    return rows.map((row) {
      final d = row.readTable(_db.documents);
      final rel = firstPathByDoc[d.id];
      return DocumentSummary(
        document: Document(
            id: d.id,
            name: d.name,
            createdAt: d.createdAt,
            modifiedAt: d.modifiedAt),
        pageCount: row.read(pageCount) ?? 0,
        thumbnailPath: rel == null ? null : _fileStore.absoluteFor(rel).path,
      );
    }).toList();
  }
```

> Note: `drift_document_repository.dart` imports `app_database.dart` with `hide Document` (the generated data class collides with the domain `Document`). `row.readTable(_db.documents)` infers that hidden type; member access (`d.id`, `d.name`, …) still compiles because only the *name* is hidden, not the type's members.

- [ ] **Step 6: Add `listDocumentSummaries()` to the fake (keep `listDocuments`)**

In `apps/mobile/test/support/fake_library.dart`, add the import and the method to `FakeDocumentRepository`:

```dart
import 'package:mobile/features/library/document_summary.dart';
```

```dart
  @override
  Future<List<DocumentSummary>> listDocumentSummaries() async {
    if (throwOnList) {
      throw StateError('fake: list failed');
    }
    // Synthesize: every fake document has one page and a deliberately
    // NON-LOADABLE thumbnail path (host tests must not load a real Image.file).
    return List<DocumentSummary>.unmodifiable(documents.map((d) =>
        DocumentSummary(
            document: d,
            pageCount: 1,
            thumbnailPath: '/nonexistent/thumb-${d.id}.jpg')));
  }
```

- [ ] **Step 7: Run the tests — verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart`
Expected: PASS (all tests, including the four new ones).

- [ ] **Step 8: Analyze**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add apps/mobile/lib/features/library/document_summary.dart \
  apps/mobile/lib/features/library/document_repository.dart \
  apps/mobile/lib/features/library/drift/drift_document_repository.dart \
  apps/mobile/test/support/fake_library.dart \
  apps/mobile/test/features/library/drift_document_repository_test.dart
git commit -m "feat(b2): DocumentSummary read model + listDocumentSummaries (Tier-1 persistence)"
```

---

### Task 2: `DocumentThumbnail` widget

A focused widget that paints a small upright thumbnail or a placeholder.

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/document_thumbnail.dart`
- Test: `apps/mobile/test/features/library/widgets/document_thumbnail_test.dart`

**Interfaces:**
- Produces: `class DocumentThumbnail extends StatelessWidget` with `const DocumentThumbnail({super.key, required String? path, double size = 48})`.

- [ ] **Step 1: Write the failing widget test**

Create `apps/mobile/test/features/library/widgets/document_thumbnail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/document_thumbnail.dart';

void main() {
  Future<void> pump(WidgetTester tester, String? path) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DocumentThumbnail(path: path))),
      );

  testWidgets('null path renders the placeholder icon and no Image',
      (tester) async {
    await pump(tester, null);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a non-loadable path falls back to the placeholder (no hang)',
      (tester) async {
    await pump(tester, '/nonexistent/missing-thumb.jpg');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it — verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/widgets/document_thumbnail_test.dart`
Expected: FAIL — `document_thumbnail.dart` / `DocumentThumbnail` does not exist.

- [ ] **Step 3: Implement the widget**

Create `apps/mobile/lib/features/library/widgets/document_thumbnail.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

/// A small, upright document thumbnail. Renders the stored JPEG via [Image.file]
/// with [cacheWidth] so the codec downsamples at decode (low memory). The stored
/// file keeps its EXIF Orientation tag, which Flutter honors — so it shows
/// upright with no re-encode. A null or unreadable path degrades to a neutral
/// placeholder (never a crash, never a host-test hang).
class DocumentThumbnail extends StatelessWidget {
  final String? path;
  final double size;
  const DocumentThumbnail({super.key, required this.path, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.description_outlined, color: scheme.onSurfaceVariant),
    );

    final path = this.path;
    if (path == null) return placeholder;

    final dpr = MediaQuery.of(context).devicePixelRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * dpr).round(),
        errorBuilder: (context, error, stack) => placeholder,
      ),
    );
  }
}
```

- [ ] **Step 4: Run it — verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/widgets/document_thumbnail_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/widgets/document_thumbnail.dart \
  apps/mobile/test/features/library/widgets/document_thumbnail_test.dart
git commit -m "feat(b2): DocumentThumbnail widget (Image.file + cacheWidth, placeholder fallback)"
```

---

### Task 3: Rich `DocumentsListView`, wire `HomeScreen`, retire `listDocuments()`

Switches the list UI to summaries (thumbnail + page count), points `HomeScreen` at `listDocumentSummaries()`, and removes the now-dead `listDocuments()` everywhere.

**Files:**
- Modify: `apps/mobile/lib/features/library/widgets/documents_list_view.dart`
- Modify: `apps/mobile/lib/features/library/home_screen.dart`
- Modify: `apps/mobile/lib/features/library/document_repository.dart` (remove `listDocuments`)
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart` (remove `listDocuments`)
- Modify: `apps/mobile/test/support/fake_library.dart` (remove `listDocuments`)
- Modify: `apps/mobile/test/features/library/documents_list_view_test.dart`
- Modify: `apps/mobile/test/features/library/drift_document_repository_test.dart` (remove old `listDocuments` test)

**Interfaces:**
- Consumes: `DocumentSummary`, `DocumentThumbnail`, `DocumentRepository.listDocumentSummaries()`.
- Produces: `DocumentsListView({required List<DocumentSummary> summaries})`; tile keys `document-tile-<id>` and `document-thumb-<id>` (unchanged tile key; new thumb key).

- [ ] **Step 1: Rewrite the `DocumentsListView` widget test**

Replace the contents of `apps/mobile/test/features/library/documents_list_view_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';

void main() {
  DocumentSummary summary(int id, {int pageCount = 1}) => DocumentSummary(
        document: Document(
          id: id,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
        ),
        pageCount: pageCount,
        thumbnailPath: '/nonexistent/thumb-$id.jpg', // non-loadable on purpose
      );

  testWidgets('renders one tile per document with name, date and page count',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentsListView(
            summaries: [summary(1), summary(2, pageCount: 3)]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('documents-list')), findsOneWidget);
    expect(find.byKey(const Key('document-tile-1')), findsOneWidget);
    expect(find.byKey(const Key('document-tile-2')), findsOneWidget);
    expect(find.byKey(const Key('document-thumb-1')), findsOneWidget);
    expect(find.byKey(const Key('document-thumb-2')), findsOneWidget);
    expect(find.text('Scan 2026-06-27 20.26.42'), findsNWidgets(2));
    expect(find.textContaining('· 1 page'), findsOneWidget);
    expect(find.textContaining('· 3 pages'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it — verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/documents_list_view_test.dart`
Expected: FAIL — `DocumentsListView` has no `summaries` parameter.

- [ ] **Step 3: Rewrite `DocumentsListView`**

Replace the contents of `apps/mobile/lib/features/library/widgets/documents_list_view.dart` with:

```dart
import 'package:flutter/material.dart';

import '../document_summary.dart';
import 'document_thumbnail.dart';

/// Rich list of saved documents: thumbnail, name, date, page count. Newest
/// first (the repository orders the list).
class DocumentsListView extends StatelessWidget {
  final List<DocumentSummary> summaries;
  const DocumentsListView({super.key, required this.summaries});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('documents-list'),
      itemCount: summaries.length,
      itemBuilder: (context, i) {
        final s = summaries[i];
        final d = s.document;
        return ListTile(
          key: Key('document-tile-${d.id}'),
          leading: DocumentThumbnail(
              key: Key('document-thumb-${d.id}'), path: s.thumbnailPath),
          title: Text(d.name),
          subtitle: Text(
              '${_formatLocal(d.createdAt.toLocal())} · ${_pages(s.pageCount)}'),
        );
      },
    );
  }

  String _pages(int n) => n == 1 ? '1 page' : '$n pages';

  String _formatLocal(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
```

- [ ] **Step 4: Run it — verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/documents_list_view_test.dart`
Expected: PASS.

- [ ] **Step 5: Point `HomeScreen` at the summary read**

In `apps/mobile/lib/features/library/home_screen.dart`: change the import `import 'document.dart';` to `import 'document_summary.dart';`, then update the state field, `_load`, and `build`:

Replace `List<Document> _documents = const [];` with:

```dart
  List<DocumentSummary> _summaries = const [];
```

Replace the body of `_load()`'s try block:

```dart
    try {
      final docs = await repo.listDocumentSummaries();
      if (!mounted) return;
      setState(() {
        _summaries = docs;
        _loading = false;
      });
    } catch (_) {
```

In `build`, replace the list/empty branch:

```dart
              : _summaries.isEmpty
                  ? const EmptyDocumentsView()
                  : DocumentsListView(summaries: _summaries),
```

- [ ] **Step 6: Remove the dead `listDocuments()`**

Delete the `listDocuments()` declaration from the interface (`document_repository.dart`), the override from `drift_document_repository.dart`, and the override from `FakeDocumentRepository` (`fake_library.dart`). In `drift_document_repository_test.dart`, **delete** the now-obsolete `test('listDocuments returns newest first', ...)` (the summary newest-first test added in Task 1 covers ordering). Leave the `import '.../document.dart'` in files that still use `Document` directly (the Drift repo still constructs `Document`; the fake still takes `documents`).

- [ ] **Step 7: Run the full unit/widget suite + analyze**

Run: `cd apps/mobile && flutter test && flutter analyze`
Expected: all tests PASS (`All tests passed!`); analyze `No issues found!`.

> The existing `home_screen_test.dart` is unchanged: the fake still accepts `documents:` and synthesizes summaries; the non-empty test's non-loadable thumbnail degrades to a placeholder under `pumpAndSettle`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/widgets/documents_list_view.dart \
  apps/mobile/lib/features/library/home_screen.dart \
  apps/mobile/lib/features/library/document_repository.dart \
  apps/mobile/lib/features/library/drift/drift_document_repository.dart \
  apps/mobile/test/support/fake_library.dart \
  apps/mobile/test/features/library/documents_list_view_test.dart \
  apps/mobile/test/features/library/drift_document_repository_test.dart
git commit -m "feat(b2): rich documents list (thumbnail + page count); retire listDocuments"
```

---

### Task 4: Tier-2 restart-persistence integration scenario

A new BDD scenario: seed a document into on-disk storage via a throwaway connection (then close it), launch the app fresh against the **same** DB file + documents dir, and assert the document appears on the home — proving the app's read path reconstitutes the list from storage on a cold launch.

**Files:**
- Create: `apps/mobile/test/support/persistent_storage.dart`
- Modify: `apps/mobile/test/support/fake_library.dart` (add `persistentLibraryDependencies`)
- Create: `apps/mobile/test/step/a_document_was_saved_to_persistent_storage_earlier.dart`
- Create: `apps/mobile/test/step/the_app_launches_reading_that_same_storage.dart`
- Create: `apps/mobile/integration_test/b2_restart_persistence.feature`
- Generated (commit): `apps/mobile/integration_test/b2_restart_persistence_test.dart`

**Interfaces:**
- Consumes: `runCamScannerApp`, `grantedScanDependencies()`, `AppDatabase`/`NativeDatabase`, `DocumentsCompanion`/`PagesCompanion`, existing step `iSeeASavedDocumentOnTheHome`.
- Produces: `persistentLibraryDependencies({required File dbFile, required Directory baseDir})`.

- [ ] **Step 1: Add the persistent dependencies helper**

In `apps/mobile/test/support/fake_library.dart`, append (it already imports `dart:io`, `package:drift/native.dart`, `DocumentFileStore`, `AppDatabase`, `DriftDocumentRepository`, `JpegExifScrubber`, `LibraryDependencies`):

```dart
/// A persistent (file-backed) LibraryDependencies that reuses the SAME db file
/// and documents baseDir on every createRepository() call — so data written
/// before one app pump is still there when a later pump reads it. This is the
/// Tier-2 restart proof. (Contrast tempLibraryDependencies(), which builds a
/// fresh NativeDatabase.memory() AND a fresh temp dir per call, and therefore
/// cannot persist across a re-pump.)
LibraryDependencies persistentLibraryDependencies({
  required File dbFile,
  required Directory baseDir,
}) =>
    LibraryDependencies(
      createRepository: () async => DriftDocumentRepository(
        db: AppDatabase(NativeDatabase(dbFile)),
        scrubber: const JpegExifScrubber(),
        fileStore: DocumentFileStore(baseDir),
        clock: DateTime.now,
      ),
    );
```

- [ ] **Step 2: Add the shared storage holder**

Create `apps/mobile/test/support/persistent_storage.dart`:

```dart
import 'dart:io';

/// Shared handle to the on-disk DB file + documents dir used by the Tier-2
/// restart scenario, so the seed step and the relaunch step target the SAME
/// storage. Set by the seed step, read by the relaunch step.
File? persistentDbFile;
Directory? persistentDir;
```

- [ ] **Step 3: Write the seed step**

Create `apps/mobile/test/step/a_document_was_saved_to_persistent_storage_earlier.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

import '../support/persistent_storage.dart';

/// Usage: a document was saved to persistent storage earlier
///
/// Seeds a document + one page DIRECTLY into an on-disk SQLite file via a
/// throwaway connection, then closes it — modelling "this data was persisted
/// before the current app instance started". No image file is written, so the
/// thumbnail will resolve to a placeholder (which also exercises the
/// missing-file path on-device); the home assertion only needs the row.
Future<void> aDocumentWasSavedToPersistentStorageEarlier(
    WidgetTester tester) async {
  final dir = await Directory.systemTemp.createTemp('b2persist');
  persistentDir = dir;
  persistentDbFile = File('${dir.path}/camscanner.sqlite');

  final db = AppDatabase(NativeDatabase(persistentDbFile!));
  final docId = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Scan 2026-06-27 20.26.42',
        createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
        modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
      ));
  await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId,
        position: 1,
        relativeImagePath: 'documents/$docId/page_1.jpg',
      ));
  await db.close();
}
```

- [ ] **Step 4: Write the relaunch step**

Create `apps/mobile/test/step/the_app_launches_reading_that_same_storage.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import '../support/persistent_storage.dart';

/// Usage: the app launches reading that same storage
Future<void> theAppLaunchesReadingThatSameStorage(WidgetTester tester) async {
  app.runCamScannerApp(
    scanDependencies: grantedScanDependencies(),
    libraryDependencies: persistentLibraryDependencies(
      dbFile: persistentDbFile!,
      baseDir: persistentDir!,
    ),
  );
  await tester.pumpAndSettle();
}
```

- [ ] **Step 5: Write the feature file**

Create `apps/mobile/integration_test/b2_restart_persistence.feature`:

```gherkin
Feature: Documents persist across an app restart

  Scenario: A document saved earlier is listed after a fresh launch
    Given a document was saved to persistent storage earlier
    When the app launches reading that same storage
    Then I see a saved document on the home
```

- [ ] **Step 6: Generate the BDD test and verify it wired the real steps**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: ends with a build-success line; creates `integration_test/b2_restart_persistence_test.dart`.

Then **open** `integration_test/b2_restart_persistence_test.dart` and confirm it imports the three real step files and calls `aDocumentWasSavedToPersistentStorageEarlier`, `theAppLaunchesReadingThatSameStorage`, and `iSeeASavedDocumentOnTheHome` — NOT freshly-generated stub bodies. (bdd_widget_test silently generates stub step files when a step phrase doesn't match an existing function name; a mismatch here means the `.feature` text and the Dart function names diverged — fix the phrasing/name so they match, delete any stray generated stub, and re-run.)

- [ ] **Step 7: Run the new integration test on a device**

Run (emulator must be booted, or let the verify harness boot it later):
`cd apps/mobile && flutter test integration_test/b2_restart_persistence_test.dart`
Expected: `All tests passed!`

- [ ] **Step 8: Commit (including the generated test)**

```bash
git add apps/mobile/test/support/persistent_storage.dart \
  apps/mobile/test/support/fake_library.dart \
  apps/mobile/test/step/a_document_was_saved_to_persistent_storage_earlier.dart \
  apps/mobile/test/step/the_app_launches_reading_that_same_storage.dart \
  apps/mobile/integration_test/b2_restart_persistence.feature \
  apps/mobile/integration_test/b2_restart_persistence_test.dart
git commit -m "test(b2): Tier-2 restart-persistence integration scenario (fresh launch reads storage)"
```

---

### Task 5: B2 verification harness

A `scripts/verify/b2.sh` mirroring `b1.sh`: static asserts for the new units, codegen-current, host unit/widget suite, analyze, coverage floor, on-device integration (Android + iOS sim) of the restart scenario, EXIF-clean regression, fail-closed negative control, and an opt-in REAL_DEVICE Tier-3 (OS-kill) lane.

**Files:**
- Create: `scripts/verify/b2.sh`

**Interfaces:**
- Consumes `scripts/verify/lib.sh` helpers: `require_tool`, `assert_file_has`, `assert_cmd`, `assert_coverage_floor`, `verify_integration_android`, `verify_integration_ios`, `verify_summary`, `pass`, `fail`, and vars `ROOT`, `ADB`, `APP_ID`, `EVIDENCE_DIR`.

- [ ] **Step 1: Write `scripts/verify/b2.sh`**

Create `scripts/verify/b2.sh`:

```bash
#!/usr/bin/env bash
# Verify B2 (documents list reads from storage) acceptance criteria.
# Run: bash scripts/verify/b2.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 OS-kill (force-stop + relaunch) lane (manual upright check).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== B2 verification =="

# ---- Tool preconditions ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence (static asserts) ----
assert_file_has "DocumentSummary read model exists" \
  "apps/mobile/lib/features/library/document_summary.dart" "class DocumentSummary"
assert_file_has "repository exposes listDocumentSummaries" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<List<DocumentSummary>> listDocumentSummaries()"
assert_file_has "list read is no-N+1 (grouped aggregate)" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "groupBy("
assert_file_has "DocumentThumbnail uses Image.file + cacheWidth" \
  "apps/mobile/lib/features/library/widgets/document_thumbnail.dart" "cacheWidth:"
assert_file_has "list view renders thumbnails" \
  "apps/mobile/lib/features/library/widgets/documents_list_view.dart" "DocumentThumbnail("
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"
assert_file_has "Tier-2 persistent deps helper exists" \
  "apps/mobile/test/support/fake_library.dart" "persistentLibraryDependencies"
assert_file_has "no schema bump (schemaVersion stays 1)" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 1;"

# ---- Generated code is current (Drift unchanged + new BDD test) ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (drift + b2 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/lib/features/library/drift/app_database.g.dart apps/mobile/integration_test/b2_restart_persistence_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria: unit + widget tests (incl. Tier-1 persistence + EXIF regression), analyze, coverage ----
assert_cmd "b2 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (BDD integration tests) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android b2_restart_persistence_test.dart
verify_integration_ios b2_restart_persistence_test.dart

# ---- Opt-in REAL_DEVICE Tier-3: true OS kill (force-stop) + relaunch shows the doc ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 (OS-kill) lane --"
  rdev="$("$ADB" devices | awk '/device$/{print $1; exit}')"
  if [ -z "$rdev" ]; then
    fail "REAL_DEVICE: no Android device connected"
  else
    "$ADB" -s "$rdev" shell am force-stop "$APP_ID" 2>/dev/null
    "$ADB" -s "$rdev" shell input keyevent KEYCODE_WAKEUP 2>/dev/null
    "$ADB" -s "$rdev" shell wm dismiss-keyguard 2>/dev/null
    "$ADB" -s "$rdev" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    "$ADB" -s "$rdev" shell sleep 7
    "$ADB" -s "$rdev" exec-out screencap -p > "$EVIDENCE_DIR/b2-real-restart-home.png" 2>/dev/null
    pass "REAL_DEVICE: force-stopped + relaunched (evidence: b2-real-restart-home.png)"
    echo "REAL_DEVICE Tier-3: MANUAL — confirm the home list shows the previously-saved document with an UPRIGHT thumbnail (see b2-real-restart-home.png)."
  fi
  echo "REAL_DEVICE (iOS): MANUAL — confirm a saved document survives an OS kill and renders upright on a physical iPhone."
fi

verify_summary
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/verify/b2.sh`

- [ ] **Step 3: Negative-control check (fail-closed)**

Run: `VERIFY_SKIP_DEVICE=1 bash scripts/verify/b2.sh; echo "exit=$?"`
Expected: prints `GATE: FAIL` and `exit=1` (skipping device checks must never pass).

- [ ] **Step 4: Full gate**

Run: `bash scripts/verify/b2.sh; echo "exit=$?"`
Expected: `GATE: PASS` and `exit=0` (emulator + iOS sim booted/booting as needed).

- [ ] **Step 5: Commit**

```bash
git add scripts/verify/b2.sh
git commit -m "test(b2): verification harness (host gate + restart integration + Tier-3 lane)"
```

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| `DocumentSummary` (document + pageCount + thumbnailPath, absolute, null-safe) | 1 |
| `listDocumentSummaries()` newest-first, no N+1, `MIN(position)` first page | 1 |
| Replace/remove `listDocuments()`; migration surface (interface, drift, home, fake, repo test) | 1 (add) + 3 (remove) |
| No schema change / `schemaVersion` stays 1 | static assert (5); no `.g.dart` change gated (5) |
| Fake synthesizes pageCount:1 + non-loadable thumbnail | 1 |
| `DocumentThumbnail` (Image.file + cacheWidth, upright via Orientation, placeholder, host-safe) | 2 |
| Rich list UI: thumbnail + name + date + `N page(s)` | 3 |
| Reuse loading/empty/error states | 3 (HomeScreen unchanged except read) |
| Tier 1 host close/reopen persistence | 1 |
| Tier 2 fresh-launch reads storage (new persistent helper, file DB + stable baseDir) | 4 |
| Tier 3 OS-kill manual REAL_DEVICE | 5 |
| EXIF-clean + transactional regression | 5 (scrubber static assert + suite runs scrubber/rollback tests) |
| Verify harness: coverage floor, codegen, integration A+iOS, negative control, GATE | 5 |
| Missing/corrupt file → placeholder, no crash/hang | 1 (null thumbnail) + 2 (errorBuilder) |

All acceptance criteria 1–6 are covered by gated checks; 7–8 are the deferred REAL_DEVICE Tier-3 lane.

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to". Every code step shows complete code.

**3. Type consistency:** `DocumentSummary{document,pageCount,thumbnailPath}` defined in Task 1 is used identically in Tasks 2–4. `listDocumentSummaries()` signature matches across interface, Drift impl, fake, and `HomeScreen` caller. `DocumentsListView({required summaries})` matches its test and `HomeScreen` usage. Keys `document-tile-<id>`/`document-thumb-<id>` consistent between widget and test. `persistentLibraryDependencies({dbFile, baseDir})` matches its step caller.

## Execution options

**Plan complete and saved to `docs/superpowers/plans/2026-06-28-b2-documents-list.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review (spec + quality) between tasks, fast iteration, broad whole-branch review at the end.

**2. Inline Execution** — execute tasks in this session with checkpoints.

**Which approach?**
