# O5 — Library search by content (name + OCR text) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users find a document by the words inside it — search the library by document name AND any page's recognized OCR text.

**Architecture:** A new `DocumentRepository.searchDocuments(query)` matches documents by `name`/`pages.ocrText` via SQLite `LIKE` (two-step: match ids, then build summaries so page counts stay correct), reusing `listDocumentSummaries`'s summary logic via a shared private `_summaries({onlyIds})`. The home screen gains a toggleable AppBar search that filters the list live.

**Tech Stack:** Flutter/Dart, drift (SQLite), `bdd_widget_test` + `build_runner`.

## Global Constraints

- **iOS + Android**: cross-platform only — a SQLite `LIKE` query + a Material `TextField`. No platform channels.
- **On-device only**: search never leaves the device.
- **DRY**: refactor `listDocumentSummaries` to delegate to `_summaries({Set<int>? onlyIds})`; do not duplicate the page-count/thumbnail logic.
- **Page-count correctness**: `searchDocuments` matches document ids first, then counts ALL pages of those ids (never filter page rows before counting).
- **Case-insensitivity**: rely on SQLite `LIKE` ASCII case-insensitivity — do NOT add `lower()`.
- **TDD/BDD first**; SOLID/KISS/DRY.
- **Commits**: stage explicit file paths (never `git add -A`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Do NOT touch**: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, `.superpowers/`.
- **On-device gate**: BDD + integration tests pass on the Samsung `RZCY51D0T1K`. Host `flutter test` skips `integration_test/` (compile gate = `flutter analyze`).
- Paths are relative to `apps/mobile/` unless noted (`scripts/`, `docs/` are repo-root).

---

### Task 1: `searchDocuments` repository method + `_summaries` refactor

**Files:**
- Modify: `lib/features/library/document_repository.dart` (interface method)
- Modify: `lib/features/library/drift/drift_document_repository.dart` (refactor + impl)
- Modify: `test/support/fake_library.dart` (fake impl)
- Test: `test/features/library/search_documents_test.dart` (create)

**Interfaces:**
- Consumes: `AppDatabase` (`documents`, `pages` with `ocrText`), `DocumentSummary`, existing `listDocumentSummaries` query logic.
- Produces: `Future<List<DocumentSummary>> searchDocuments(String query)`.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/search_documents_test.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'dart:io';

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('o5search');
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );
  });

  tearDown(() async {
    await db.close();
    if (await base.exists()) await base.delete(recursive: true);
  });

  // Seeds a document with [pageCount] pages; the first page carries [ocrText].
  Future<int> seedDoc(String name, {String? ocrText, int pageCount = 1}) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: name, createdAt: now, modifiedAt: now));
    for (var pos = 1; pos <= pageCount; pos++) {
      await db.into(db.pages).insert(PagesCompanion.insert(
            documentId: id,
            position: pos,
            relativeImagePath: 'documents/$id/page_$pos.jpg',
            ocrText: Value(pos == 1 ? ocrText : null),
          ));
    }
    return id;
  }

  test('matches by document name (case-insensitive)', () async {
    await seedDoc('Invoice March');
    await seedDoc('Grocery list');
    final results = await repo.searchDocuments('invoice');
    expect(results.map((s) => s.document.name), ['Invoice March']);
  });

  test('matches by a page OCR text even when the name does not', () async {
    await seedDoc('Untitled', ocrText: 'TOTAL DUE 42.00 USD');
    await seedDoc('Other');
    final results = await repo.searchDocuments('total due');
    expect(results.map((s) => s.document.name), ['Untitled']);
  });

  test('a document with two matching pages appears once', () async {
    final id = await seedDoc('Doc', pageCount: 2);
    // give BOTH pages the query text
    await (db.update(db.pages)..where((t) => t.documentId.equals(id)))
        .write(const PagesCompanion(ocrText: Value('SHARED KEYWORD')));
    final results = await repo.searchDocuments('keyword');
    expect(results.length, 1);
    expect(results.single.pageCount, 2); // counts ALL pages, not just matches
  });

  test('empty/whitespace query returns the full list', () async {
    await seedDoc('A');
    await seedDoc('B');
    final all = await repo.listDocumentSummaries();
    final blank = await repo.searchDocuments('   ');
    expect(blank.map((s) => s.document.id).toSet(),
        all.map((s) => s.document.id).toSet());
  });

  test('a non-matching query returns empty', () async {
    await seedDoc('Alpha');
    expect(await repo.searchDocuments('zzznope'), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/search_documents_test.dart`
Expected: FAIL — `searchDocuments` not defined.

- [ ] **Step 3: Add the interface method**

In `lib/features/library/document_repository.dart`, after the `listDocumentSummaries` declaration:

```dart
  /// Same shape as [listDocumentSummaries] (newest first), restricted to
  /// documents whose name OR any page's recognized OCR text contains [query]
  /// (case-insensitive substring). A blank/whitespace [query] returns the same
  /// as [listDocumentSummaries]. Matches never leave the device.
  Future<List<DocumentSummary>> searchDocuments(String query);
```

- [ ] **Step 4: Refactor + implement in the Drift repository**

In `lib/features/library/drift/drift_document_repository.dart`, replace the existing `listDocumentSummaries` method with a thin delegator + a private `_summaries` that adds an optional id filter, and add `searchDocuments`:

```dart
  @override
  Future<List<DocumentSummary>> listDocumentSummaries() => _summaries();

  @override
  Future<List<DocumentSummary>> searchDocuments(String query) async {
    final q = query.trim();
    if (q.isEmpty) return _summaries();
    final like = '%$q%';
    // Step 1: ids of documents matching by name OR any page's ocrText.
    // Grouping by document id yields each matching doc exactly once.
    final idQuery = _db.select(_db.documents).join([
      leftOuterJoin(_db.pages, _db.pages.documentId.equalsExp(_db.documents.id)),
    ])
      ..where(_db.documents.name.like(like) | _db.pages.ocrText.like(like))
      ..groupBy([_db.documents.id]);
    final ids =
        (await idQuery.get()).map((r) => r.readTable(_db.documents).id).toSet();
    if (ids.isEmpty) return const [];
    // Step 2: build summaries for those ids (counts ALL their pages).
    return _summaries(onlyIds: ids);
  }

  Future<List<DocumentSummary>> _summaries({Set<int>? onlyIds}) async {
    // (1) page count per document, newest doc first — one grouped query.
    final pageCount = _db.pages.id.count();
    final query = _db.select(_db.documents).join([
      leftOuterJoin(_db.pages, _db.pages.documentId.equalsExp(_db.documents.id)),
    ])
      ..addColumns([pageCount])
      ..groupBy([_db.documents.id])
      ..orderBy([OrderingTerm.desc(_db.documents.createdAt)]);
    if (onlyIds != null) {
      query.where(_db.documents.id.isIn(onlyIds.toList()));
    }
    final rows = await query.get();

    // (2) lowest-position page path per document — one query, no N+1.
    final pages = await (_db.select(_db.pages)
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final firstPathByDoc = <int, String>{};
    for (final pg in pages) {
      firstPathByDoc.putIfAbsent(
          pg.documentId, () => pg.flatRelativePath ?? pg.relativeImagePath);
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
        pageCount: row.read(pageCount)!,
        thumbnailPath: rel == null ? null : _fileStore.absoluteFor(rel).path,
      );
    }).toList();
  }
```

> **Implementer note:** the `_summaries` body is the EXACT prior `listDocumentSummaries` body plus the `if (onlyIds != null) query.where(...)` line — copy it verbatim so behavior is unchanged. `name.like(...)`, `ocrText.like(...)`, the `|` OR operator, and `id.isIn(List)` are standard drift `Expression`/column APIs. `ocrText` is nullable → `NULL LIKE '%q%'` is falsey, so pages without text simply don't match (correct). `.where(...)` on a joined statement is called as a method here (`query.where(...)`) because the statement is already built with cascades.

- [ ] **Step 5: Implement in the fake repository**

In `test/support/fake_library.dart`, add to `FakeDocumentRepository` (near `listDocumentSummaries`). It filters the injected `documents` by name substring (case-insensitive), returning the same summary shape — enough to drive the home UI; real `ocrText` matching is covered by the Drift unit test:

```dart
  @override
  Future<List<DocumentSummary>> searchDocuments(String query) async {
    if (throwOnList) throw StateError('fake: search failed');
    final summaries = documents
        .map((d) => DocumentSummary(
            document: d,
            pageCount: 1,
            thumbnailPath: '/nonexistent/thumb-${d.id}.jpg'))
        .toList();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return summaries;
    return summaries
        .where((s) => s.document.name.toLowerCase().contains(q))
        .toList();
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/search_documents_test.dart`
Expected: PASS (5/5).

- [ ] **Step 7: Run the full library group (regression: the refactor) + analyze**

The `test/features/library/` group needs the OpenCV host lib. If a test errors on `libdartcv`/`DARTCV_LIB_PATH`:
```bash
bash /Users/pablohpsilva/Documents/camscanner-light/scripts/setup-cv-host-test.sh
export DARTCV_LIB_PATH=/tmp/dartcv_lib/lib/libdartcv.dylib
export DYLD_LIBRARY_PATH=/tmp/dartcv_lib/lib
```
Run: `cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass (existing `listDocumentSummaries` tests still green — the refactor is behavior-preserving); `No issues found`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/document_repository.dart apps/mobile/lib/features/library/drift/drift_document_repository.dart apps/mobile/test/support/fake_library.dart apps/mobile/test/features/library/search_documents_test.dart
git commit -m "feat(o5): searchDocuments — match library by name and page OCR text"
```

---

### Task 2: Home screen search mode

**Files:**
- Modify: `lib/features/library/home_screen.dart`
- Test: `test/features/library/home_search_test.dart` (create)

**Interfaces:**
- Consumes: `DocumentRepository.searchDocuments`, existing `DocumentsListView`, `SortControlBar`, `EmptyDocumentsView`, `fakeLibraryDependencies`, `grantedScanDependencies`.
- Produces: home search UI (keys `documents-search`, `documents-search-field`, `documents-search-clear`, `documents-search-close`, `documents-search-empty`).

- [ ] **Step 1: Write the failing widget test**

Create `test/features/library/home_search_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/home_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, FakeDocumentRepository repo) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(repo),
      ),
    ));
    await tester.pumpAndSettle();
  }

  FakeDocumentRepository twoDocs() {
    final t = DateTime.utc(2026, 7, 1, 12);
    return FakeDocumentRepository(documents: [
      Document(id: 1, name: 'Invoice March', createdAt: t, modifiedAt: t),
      Document(id: 2, name: 'Grocery list', createdAt: t, modifiedAt: t),
    ]);
  }

  testWidgets('search filters the list to matching documents', (tester) async {
    await pumpHome(tester, twoDocs());
    expect(find.text('Invoice March'), findsOneWidget);
    expect(find.text('Grocery list'), findsOneWidget);

    await tester.tap(find.byKey(const Key('documents-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('documents-search-field')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('documents-search-field')), 'invoice');
    await tester.pumpAndSettle();
    expect(find.text('Invoice March'), findsOneWidget);
    expect(find.text('Grocery list'), findsNothing);
  });

  testWidgets('clear restores the full list', (tester) async {
    await pumpHome(tester, twoDocs());
    await tester.tap(find.byKey(const Key('documents-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('documents-search-field')), 'invoice');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('documents-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Invoice March'), findsOneWidget);
    expect(find.text('Grocery list'), findsOneWidget);
  });

  testWidgets('a query with no matches shows the empty-search state',
      (tester) async {
    await pumpHome(tester, twoDocs());
    await tester.tap(find.byKey(const Key('documents-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('documents-search-field')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('documents-search-empty')), findsOneWidget);
  });

  testWidgets('close exits search mode and restores the sort bar',
      (tester) async {
    await pumpHome(tester, twoDocs());
    await tester.tap(find.byKey(const Key('documents-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sort-control-bar')), findsNothing);

    await tester.tap(find.byKey(const Key('documents-search-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('documents-search-field')), findsNothing);
    expect(find.byKey(const Key('sort-control-bar')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/home_search_test.dart`
Expected: FAIL — no `documents-search` key.

- [ ] **Step 3: Add search state + controller + dispose**

In `home_screen.dart`, in `_HomeScreenState`, add fields after `DocumentSort _sort = DocumentSort.initial;`:

```dart
  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';
```

Add a `dispose` (the class has none today) after `initState`:

```dart
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
```

- [ ] **Step 4: Add the search methods**

Add these methods (e.g. after `_load`):

```dart
  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
    _load(); // restore the full list
  }

  Future<void> _onQueryChanged(String value) async {
    final repo = _repository;
    setState(() => _query = value);
    if (repo == null) return;
    try {
      final results = await repo.searchDocuments(value);
      if (!mounted || value != _query) return; // race guard: newer query wins
      setState(() => _summaries = results);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  // After returning from a push, re-apply search if active, else reload.
  Future<void> _refresh() => _searching ? _onQueryChanged(_query) : _load();
```

Change the three post-push `await _load();` calls to `await _refresh();` — in `_openScan` (after the camera push), `_openDocument` (after the viewer push), and `_renameDocument` (after `rename`).

- [ ] **Step 5: Replace the `build` method + add AppBar/body builders**

Replace the entire `build` method (and keep `_buildError`) with:

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _searching ? _buildSearchAppBar() : _buildNormalAppBar(),
      body: _loading
          ? const Center(
              key: Key('documents-loading'),
              child: CircularProgressIndicator())
          : _error
              ? _buildError()
              : _buildBody(),
      floatingActionButton: _searching
          ? null
          : FloatingActionButton.extended(
              onPressed: _repository == null ? null : _openScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan'),
            ),
    );
  }

  AppBar _buildNormalAppBar() => AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            key: const Key('documents-search'),
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: _repository == null ? null : _openSearch,
          ),
        ],
      );

  AppBar _buildSearchAppBar() => AppBar(
        leading: IconButton(
          key: const Key('documents-search-close'),
          tooltip: 'Close search',
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeSearch,
        ),
        title: TextField(
          key: const Key('documents-search-field'),
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search documents',
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          IconButton(
            key: const Key('documents-search-clear'),
            tooltip: 'Clear',
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _onQueryChanged('');
            },
          ),
        ],
      );

  Widget _buildBody() {
    if (_searching) {
      if (_summaries.isEmpty && _query.trim().isNotEmpty) {
        return Center(
          key: const Key('documents-search-empty'),
          child: Text('No documents match "$_query".'),
        );
      }
      if (_summaries.isEmpty) return const EmptyDocumentsView();
      return DocumentsListView(
        summaries: _summaries,
        onOpen: _openDocument,
        onRename: _renameDocument,
      );
    }
    if (_summaries.isEmpty) return const EmptyDocumentsView();
    return Column(
      children: [
        SortControlBar(sort: _sort, onCriterionTapped: _onSortCriterion),
        Expanded(
          child: DocumentsListView(
            summaries: sortDocuments(_summaries, _sort),
            onOpen: _openDocument,
            onRename: _renameDocument,
          ),
        ),
      ],
    );
  }
```

> `EmptyDocumentsView`, `SortControlBar`, `DocumentsListView`, `sortDocuments` are already imported. No new imports needed.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/home_search_test.dart`
Expected: PASS (4/4).

- [ ] **Step 7: Run the full library group + analyze**

Run (with the DARTCV env from Task 1 Step 7 if needed): `cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass (existing home tests unaffected); `No issues found`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/home_screen.dart apps/mobile/test/features/library/home_search_test.dart
git commit -m "feat(o5): home search mode — live filter, clear, close, empty state"
```

---

### Task 3: BDD `.feature`, on-device test, verify script, plans index

**Files:**
- Create: `integration_test/o5_content_search.feature`
- Create step defs: `test/step/a_saved_document_with_page_text.dart`, `test/step/i_search_for.dart`
- Generate: `integration_test/o5_content_search_test.dart` (build_runner; committed)
- Create: `integration_test/o5_content_search_device_test.dart` (deterministic Drift search on device)
- Create: `scripts/verify/o5.sh` (repo root)
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Write the `.feature`**

Create `integration_test/o5_content_search.feature`:

```gherkin
Feature: Search the library by content

  Scenario: Find a document by the text inside it
    Given a saved document named {'Untitled'} with page text {'INVOICE 2026'}
    When the app launches reading that same storage
    And I search for {'invoice'}
    Then I see {'Untitled'} text
    When I search for {'zzz'}
    Then I see the no matches message
```

- [ ] **Step 2: Write the new step definitions**

Create `test/step/a_saved_document_with_page_text.dart` (mirror `a_saved_document_with_recognized_text.dart`, but the doc name and page text are separate params so the match is proven to be by CONTENT, not name):

```dart
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

import '../support/persistent_storage.dart';

/// Usage: a saved document named {'Untitled'} with page text {'INVOICE 2026'}
Future<void> aSavedDocumentNamedWithPageText(
    WidgetTester tester, String name, String pageText) async {
  final dir = await Directory.systemTemp.createTemp('o5persist');
  persistentDir = dir;
  persistentDbFile = File('${dir.path}/camscanner.sqlite');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final db = AppDatabase(NativeDatabase(persistentDbFile!));
  final now = DateTime.utc(2026, 7, 1, 12);
  final docId = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: name, createdAt: now, modifiedAt: now));
  await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId,
        position: 1,
        relativeImagePath: 'documents/$docId/page_1.jpg',
        ocrText: Value(pageText)));
  await db.close();
}
```

Create `test/step/i_search_for.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I search for {'invoice'}
Future<void> iSearchFor(WidgetTester tester, String query) async {
  // Open search if not already open.
  final searchIcon = find.byKey(const Key('documents-search'));
  if (searchIcon.evaluate().isNotEmpty) {
    await tester.tap(searchIcon);
    await tester.pumpAndSettle();
  }
  await tester.enterText(
      find.byKey(const Key('documents-search-field')), query);
  await tester.pumpAndSettle();
}
```

Create `test/step/i_see_the_no_matches_message.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the no matches message
Future<void> iSeeTheNoMatchesMessage(WidgetTester tester) async {
  expect(find.byKey(const Key('documents-search-empty')), findsOneWidget);
}
```

> `the app launches reading that same storage` and `I see {'...'} text` already exist — reuse. Verify the generated function name for the seed step matches the generator's derivation of the Gherkin phrase; if the generator names it differently, rename the step file/function to match (the generator is the source of truth).

- [ ] **Step 3: Generate the BDD test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `integration_test/o5_content_search_test.dart` generated, importing the new step functions + the reused `theAppLaunchesReadingThatSameStorage` and `iSeeText`. If build_runner rewrote unrelated generated files, `git checkout` those back so the commit stays scoped to O5.

- [ ] **Step 4: Write the deterministic on-device test**

Create `integration_test/o5_content_search_device_test.dart`:

```dart
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('searchDocuments matches by page OCR text on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('o5dev');
    final db = AppDatabase(NativeDatabase.memory());
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );

    final now = DateTime.now();
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Untitled', createdAt: now, modifiedAt: now));
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id,
        position: 1,
        relativeImagePath: 'documents/$id/page_1.jpg',
        ocrText: const Value('INVOICE 2026 TOTAL DUE')));
    await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Recipe', createdAt: now, modifiedAt: now));

    final hit = await repo.searchDocuments('invoice');
    expect(hit.map((s) => s.document.name), ['Untitled']);
    final miss = await repo.searchDocuments('zzz');
    expect(miss, isEmpty);

    await db.close();
    await base.delete(recursive: true);
  });
}
```

- [ ] **Step 5: Write the verify script**

Create `scripts/verify/o5.sh` (repo root), mirroring `scripts/verify/o1.sh`:

```bash
#!/usr/bin/env bash
# Verify O5 (library search by name + OCR content) acceptance criteria.
# Run from repository root: bash scripts/verify/o5.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== O5 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "searchDocuments on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "searchDocuments"

assert_file_has "searchDocuments in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "searchDocuments"

assert_file_has "home wires the search field" \
  "apps/mobile/lib/features/library/home_screen.dart" \
  "documents-search-field"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/o5_content_search.feature" \
  "Search the library by content"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/o5_content_search_test.dart" \
  "content"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device O5 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device search test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/o5_content_search_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/o5_content_search_test.dart"
fi

echo "== O5 verification complete =="
```

Make it executable: `chmod +x scripts/verify/o5.sh`.

- [ ] **Step 6: Host verify + analyze (device runs handled by the controller)**

Run: `cd apps/mobile && flutter test && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`. (The generated + device integration_test files must at least compile — analyze covers this.)

- [ ] **Step 7: Update the plans index**

In `docs/superpowers/plans/00-plans-index.md`, add after the O4 row:

```markdown
| O5 | Library search by name + OCR content | 08, 02 | `2026-07-01-o5-content-search.md` | ✅ **built & gated** |
```

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/integration_test/o5_content_search.feature apps/mobile/integration_test/o5_content_search_test.dart apps/mobile/integration_test/o5_content_search_device_test.dart apps/mobile/test/step/a_saved_document_with_page_text.dart apps/mobile/test/step/i_search_for.dart apps/mobile/test/step/i_see_the_no_matches_message.dart scripts/verify/o5.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(o5): BDD + on-device search tests, verify script, index"
```

---

## Self-Review

- **Spec coverage:** name match + ocrText match + case-insensitive + distinct + empty→full + no-match→empty (Task 1); toggle search, live filter, clear, close, empty state (Task 2); on-device content-match proof + BDD (Task 3). ✅
- **Page-count correctness:** two-step id-match then count-all-pages; the `_summaries` refactor is behavior-preserving for the `onlyIds: null` path (existing tests guard it). ✅
- **Placeholder scan:** complete code in every step; implementer notes flag the drift API + generator-name subtleties. ✅
- **Type consistency:** `searchDocuments(String) → Future<List<DocumentSummary>>` identical across interface, Drift, and fake; home keys consistent between Task 2 code and Task 2/3 tests. ✅
- **Out of scope kept out:** no FTS index, no ranking, no snippet highlight, no LIKE-metachar escaping (documented). ✅
