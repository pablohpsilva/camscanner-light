# FTS5 Search — Trigram Matching + Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the O5 `LIKE` search engine with a SQLite FTS5 **trigram** index (one row per document) so multi-word queries match across a document's pages, ranked by `bm25`, without regressing today's substring/CJK matching or changing the search UI.

**Architecture:** A standalone `doc_fts` FTS5 virtual table keyed by `documents.id`, holding each document's pages' `ocr_text` concatenated. Three SQLite triggers on `pages` rebuild a document's row on any `ocr_text` insert/update/delete, so no repository write-path changes are needed. A `v4→v5` migration creates the table+triggers and backfills. `searchDocuments` gains a sanitized, ranked trigram `MATCH` path with a `LIKE` fallback for sub-3-char terms.

**Tech Stack:** Flutter/Dart, drift (SQLite), `sqlite3_flutter_libs` (ships FTS5), ML Kit OCR (already wired), `flutter_test` (host), `integration_test` (device Samsung RZCY51D0T1K).

## Global Constraints

- Full-text engine: SQLite **FTS5** with `tokenize = 'trigram'` — never `unicode61` (would regress substring/CJK matching).
- FTS table is **one row per document**, `rowid = documents.id`, single `text` column = `group_concat(ocr_text, ' ')` of that doc's non-null pages. (Per-page rows are wrong: FTS5 `MATCH 'a AND b'` requires both terms in one row.)
- SQL column names are drift snake_case: `ocr_text`, `document_id`, `id`.
- Sync is **trigger-only** — no repository code writes to `doc_fts`. Every current/future `ocr_text` write path stays indexed automatically.
- Raw user query text is **never** passed to `MATCH`; each term is stripped of FTS operator chars and double-quoted. Terms `< 3` chars (or a query that sanitizes to nothing) take the `LIKE` fallback.
- Ranking: `bm25(doc_fts)` ascending (lower = more relevant); document **name** matches sort **first**.
- `schemaVersion` becomes **5**; the vtable is raw SQL, so **no `build_runner` regen**.
- TDD: failing test first, minimal impl, green, commit. `flutter analyze` clean at each commit.
- Device verification target: Samsung **RZCY51D0T1K**. Host `flutter test` skips `integration_test/`.

**Repo paths (all relative to `apps/mobile/`):**
- DB/schema: `lib/features/library/drift/app_database.dart`
- Repository: `lib/features/library/drift/drift_document_repository.dart`
- Search unit tests: `test/features/library/search_documents_test.dart` (existing O5) + new files below.

---

### Task 1: Retire the FTS5/trigram host-availability risk

**Files:**
- Test (create): `apps/mobile/test/features/library/fts5_availability_test.dart`

**Interfaces:**
- Consumes: nothing (uses `drift` `NativeDatabase.memory()` directly).
- Produces: proof that FTS5 + trigram work under host `flutter test`. If this FAILS, STOP and escalate — the data-layer/search tests (Tasks 2–3) must move to `integration_test/` on device; the production code is unchanged either way.

- [ ] **Step 1: Write the test**

Create `apps/mobile/test/features/library/fts5_availability_test.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the host test runtime's SQLite has FTS5 + the trigram tokenizer.
/// Device is fine (sqlite3_flutter_libs ships FTS5); this guards the HOST path
/// that Tasks 2–3 rely on. If it fails, those tests move to integration_test/.
void main() {
  test('host SQLite supports fts5 trigram substring MATCH', () async {
    final db = NativeDatabase.memory();
    await db.ensureOpen(_NoOpUser());
    await db.runCustom(
        "CREATE VIRTUAL TABLE t USING fts5(x, tokenize = 'trigram')", const []);
    await db.runCustom("INSERT INTO t(rowid, x) VALUES (1, 'rescanned page')",
        const []);
    final rows =
        await db.runSelect("SELECT rowid FROM t WHERE t MATCH ?", ['scan']);
    expect(rows, hasLength(1),
        reason: 'trigram MATCH must find the mid-word substring "scan"');
    await db.close();
  });
}

class _NoOpUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;
  @override
  Future<void> beforeOpen(_, __) async {}
}
```

- [ ] **Step 2: Run it — expect PASS**

Run: `cd apps/mobile && flutter test test/features/library/fts5_availability_test.dart`
Expected: **PASS** (1 test). If it FAILS with an FTS5/trigram error, STOP: Tasks 2–3 tests move to `integration_test/` (same pattern as the OpenCV host-test limitation). Do not change production code.

- [ ] **Step 3: Commit**

```bash
cd apps/mobile && git add test/features/library/fts5_availability_test.dart
git commit -m "test(search): prove host SQLite has FTS5 trigram (retire risk)"
```

---

### Task 2: `doc_fts` virtual table, triggers, migration + backfill

**Files:**
- Modify: `apps/mobile/lib/features/library/drift/app_database.dart` (migration block ~L46-63, `schemaVersion` L47)
- Test (create): `apps/mobile/test/features/library/doc_fts_sync_test.dart`

**Interfaces:**
- Consumes: existing `Documents`/`Pages` tables, `AppDatabase(NativeDatabase.memory())`.
- Produces: table `doc_fts` (fts5, `rowid`=document id, column `text`), triggers `doc_fts_ai`/`doc_fts_au`/`doc_fts_ad`, `schemaVersion == 5`, methods `_createFts()`/`_backfillFts()` on `AppDatabase`. Query contract used by Task 3: `SELECT rowid, bm25(doc_fts) FROM doc_fts WHERE doc_fts MATCH ?`.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/library/doc_fts_sync_test.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> insertDoc(String name) => db.into(db.documents).insert(
      DocumentsCompanion.insert(
          name: name, createdAt: DateTime.now(), modifiedAt: DateTime.now()));

  Future<int> insertPage(int docId, int pos, {String? ocr}) =>
      db.into(db.pages).insert(PagesCompanion.insert(
            documentId: docId,
            position: pos,
            relativeImagePath: 'documents/$docId/page_$pos.jpg',
            ocrText: Value(ocr),
          ));

  // Doc ids whose concatenated OCR text matches the trigram expression.
  Future<List<int>> matchDocs(String expr) async {
    final rows = await db.customSelect(
      'SELECT rowid AS did FROM doc_fts WHERE doc_fts MATCH ?',
      variables: [Variable.withString(expr)],
    ).get();
    return rows.map((r) => r.read<int>('did')).toList();
  }

  test('multi-word AND matches across DIFFERENT pages of one document',
      () async {
    final id = await insertDoc('Report');
    await insertPage(id, 1, ocr: 'ACME corporation header');
    await insertPage(id, 3, ocr: 'final INVOICE total');
    expect(await matchDocs('"acme" AND "invoice"'), [id]);
  });

  test('trigger fills the index when ocr_text is set via UPDATE', () async {
    final id = await insertDoc('Doc');
    final pageId = await insertPage(id, 1); // ocr null → not indexed yet
    expect(await matchDocs('"keyword"'), isEmpty);
    await (db.update(db.pages)..where((t) => t.id.equals(pageId)))
        .write(const PagesCompanion(ocrText: Value('a KEYWORD here')));
    expect(await matchDocs('"keyword"'), [id]);
  });

  test('clearing ocr_text and deleting pages leaves no orphan doc_fts row',
      () async {
    final id = await insertDoc('Doc');
    final p1 = await insertPage(id, 1, ocr: 'alpha KEYWORD');
    await insertPage(id, 2, ocr: 'beta KEYWORD');
    expect(await matchDocs('"keyword"'), [id]);
    // clear one page's text → doc still matches via the other page
    await (db.update(db.pages)..where((t) => t.id.equals(p1)))
        .write(const PagesCompanion(ocrText: Value(null)));
    expect(await matchDocs('"keyword"'), [id]);
    // delete all pages → doc drops out of the index entirely
    await (db.delete(db.pages)..where((t) => t.documentId.equals(id))).go();
    expect(await matchDocs('"keyword"'), isEmpty);
  });

  test('backfill indexes pre-existing ocr_text', () async {
    final id = await insertDoc('Old');
    await insertPage(id, 1, ocr: 'legacy CONTRACT text');
    // simulate an un-indexed (pre-v5) state, then run the backfill
    await db.customStatement('DELETE FROM doc_fts');
    expect(await matchDocs('"contract"'), isEmpty);
    await db.backfillFtsForTest();
    expect(await matchDocs('"contract"'), [id]);
  });
}
```

- [ ] **Step 2: Run it — verify it FAILS**

Run: `cd apps/mobile && flutter test test/features/library/doc_fts_sync_test.dart`
Expected: FAIL — `no such table: doc_fts` (the vtable/triggers don't exist yet).

- [ ] **Step 3: Implement the migration, triggers, and helpers**

In `apps/mobile/lib/features/library/drift/app_database.dart`, bump the version and replace the migration block. Change `int get schemaVersion => 4;` to `=> 5;`, then replace the `MigrationStrategy` getter and add the helpers:

```dart
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createFts();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(pages, pages.corners);
          if (from < 3) await m.addColumn(pages, pages.flatRelativePath);
          if (from < 4) {
            await m.addColumn(pages, pages.ocrText);
            await m.addColumn(pages, pages.ocrBoxes);
          }
          if (from < 5) {
            await _createFts();
            await _backfillFts();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Trigram FTS index over each DOCUMENT's concatenated page OCR text, plus the
  /// triggers that rebuild a document's row on any page ocr_text change. Raw SQL
  /// (the vtable is not a drift table), so it runs in BOTH onCreate and onUpgrade.
  /// One row per document — a multi-word MATCH (AND) must see all terms in one
  /// row, so terms spread across a document's pages still match.
  Future<void> _createFts() async {
    await customStatement(
        "CREATE VIRTUAL TABLE doc_fts USING fts5(text, tokenize = 'trigram')");
    // group_concat over a document's non-null pages; GROUP BY makes the SELECT
    // yield zero rows when none remain, so the row is dropped (no NULL insert).
    const rebuildNew = "DELETE FROM doc_fts WHERE rowid = NEW.document_id; "
        "INSERT INTO doc_fts(rowid, text) "
        "SELECT document_id, group_concat(ocr_text, ' ') FROM pages "
        "WHERE document_id = NEW.document_id AND ocr_text IS NOT NULL "
        "GROUP BY document_id;";
    const rebuildOld = "DELETE FROM doc_fts WHERE rowid = OLD.document_id; "
        "INSERT INTO doc_fts(rowid, text) "
        "SELECT document_id, group_concat(ocr_text, ' ') FROM pages "
        "WHERE document_id = OLD.document_id AND ocr_text IS NOT NULL "
        "GROUP BY document_id;";
    await customStatement(
        "CREATE TRIGGER doc_fts_ai AFTER INSERT ON pages "
        "WHEN NEW.ocr_text IS NOT NULL BEGIN $rebuildNew END");
    await customStatement(
        "CREATE TRIGGER doc_fts_au AFTER UPDATE OF ocr_text ON pages "
        "BEGIN $rebuildNew END");
    await customStatement(
        "CREATE TRIGGER doc_fts_ad AFTER DELETE ON pages "
        "BEGIN $rebuildOld END");
  }

  /// One-time population for documents whose pages already had ocr_text pre-v5.
  Future<void> _backfillFts() async {
    await customStatement(
        "INSERT INTO doc_fts(rowid, text) "
        "SELECT document_id, group_concat(ocr_text, ' ') FROM pages "
        "WHERE ocr_text IS NOT NULL GROUP BY document_id");
  }

  /// Test-only hook to exercise the backfill statement in isolation.
  @visibleForTesting
  Future<void> backfillFtsForTest() => _backfillFts();
```

Add the import for `@visibleForTesting` at the top of the file if not present:

```dart
import 'package:flutter/foundation.dart' show visibleForTesting;
```

- [ ] **Step 4: Run the test — verify it PASSES**

Run: `cd apps/mobile && flutter test test/features/library/doc_fts_sync_test.dart`
Expected: **PASS** (4 tests).

- [ ] **Step 5: Analyze + full host suite (guard the schema bump)**

Run: `cd apps/mobile && flutter analyze && flutter test`
Expected: analyze clean; all host tests green (existing repo tests open at v5 via `onCreate`, which now also builds `doc_fts`).

- [ ] **Step 6: Commit**

```bash
cd apps/mobile && git add lib/features/library/drift/app_database.dart \
  test/features/library/doc_fts_sync_test.dart
git commit -m "feat(search): doc_fts trigram index + triggers + v5 migration/backfill"
```

---

### Task 3: Ranked trigram `searchDocuments` (with sanitization + LIKE fallback)

**Files:**
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart` (replace `searchDocuments` ~L180-196; add private helpers)
- Test (create): `apps/mobile/test/features/library/search_ranking_test.dart`
- Verify green (do not edit): `apps/mobile/test/features/library/search_documents_test.dart`

**Interfaces:**
- Consumes: `doc_fts` MATCH contract from Task 2; existing `_summaries({Set<int>? onlyIds})` (L198), `DocumentSummary`.
- Produces: rewritten `DocumentRepository.searchDocuments(String)` — same signature/return type, now relevance-ordered on the ranked path.

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/features/library/search_ranking_test.dart`:

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
    base = await Directory.systemTemp.createTemp('ftsrank');
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

  // Seeds a doc and sets each page's ocrText from [pageTexts] (index 0 → pos 1).
  Future<int> seed(String name, List<String?> pageTexts) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: name, createdAt: now, modifiedAt: now));
    for (var i = 0; i < pageTexts.length; i++) {
      await db.into(db.pages).insert(PagesCompanion.insert(
            documentId: id,
            position: i + 1,
            relativeImagePath: 'documents/$id/page_${i + 1}.jpg',
            ocrText: Value(pageTexts[i]),
          ));
    }
    return id;
  }

  List<String> names(List<dynamic> r) =>
      r.map((s) => s.document.name as String).toList();

  test('multi-word query matches terms across different pages of one doc',
      () async {
    await seed('Report', ['ACME corporation header', null, 'final INVOICE total']);
    await seed('Decoy', ['acme only, nothing else here']);
    final r = await repo.searchDocuments('acme invoice');
    expect(names(r), ['Report']);
  });

  test('mid-word substring still matches (trigram parity with LIKE)', () async {
    await seed('Scans', ['these were all rescanned yesterday']);
    expect(names(await repo.searchDocuments('scan')), ['Scans']);
  });

  test('more/closer hits rank above an incidental single hit', () async {
    await seed('Weak', ['mentions invoice once, buried in prose about cats']);
    await seed('Strong', ['invoice invoice invoice invoice']);
    final r = await repo.searchDocuments('invoice');
    expect(names(r).first, 'Strong', reason: 'higher term frequency ranks first');
  });

  test('a name match sorts ahead of a text-only match', () async {
    await seed('Just some body text', ['this mentions mango somewhere']);
    await seed('Mango recipes', ['unrelated content']);
    final r = await repo.searchDocuments('mango');
    expect(names(r).first, 'Mango recipes');
  });

  test('operator-laden input never throws and still matches', () async {
    await seed('Doc', ['quarterly report data']);
    final r = await repo.searchDocuments('"report* (NEAR quarterly');
    expect(names(r), ['Doc']);
  });

  test('sub-3-char term falls back to LIKE and still matches substrings',
      () async {
    await seed('AB Co', ['the ab shorthand appears here']);
    expect(names(await repo.searchDocuments('ab')), ['AB Co']);
  });
}
```

- [ ] **Step 2: Run — verify it FAILS**

Run: `cd apps/mobile && flutter test test/features/library/search_ranking_test.dart`
Expected: FAIL — cross-page/ranking/name-first expectations fail against the current `LIKE` engine (e.g. `'acme invoice'` returns `[]`).

- [ ] **Step 3: Rewrite `searchDocuments` + add helpers**

In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`, replace the whole current `searchDocuments` method (the `@override Future<List<DocumentSummary>> searchDocuments...` block, ~L180-196) with:

```dart
  // FTS5 operator characters stripped from every term before it reaches MATCH.
  static final RegExp _ftsOps = RegExp(r'''["*:^()\-]''');
  static const Set<String> _ftsKeywords = {'and', 'or', 'not', 'near'};

  // Raw query → safe search terms: operator chars removed, bareword boolean
  // keywords dropped, empties discarded. Never yields FTS syntax.
  List<String> _searchTerms(String q) => q
      .split(RegExp(r'\s+'))
      .map((t) => t.replaceAll(_ftsOps, ''))
      .where((t) => t.isNotEmpty && !_ftsKeywords.contains(t.toLowerCase()))
      .toList();

  @override
  Future<List<DocumentSummary>> searchDocuments(String query) async {
    final q = query.trim();
    if (q.isEmpty) return _summaries();
    final terms = _searchTerms(q);
    // Trigram MATCH needs every term >= 3 chars; anything shorter (or a query
    // that sanitizes to nothing) falls back to the unranked LIKE scan so short
    // words still match as substrings.
    if (terms.isEmpty || terms.any((t) => t.length < 3)) {
      return _searchByLike(q);
    }
    return _searchRanked(q, terms);
  }

  // Unranked substring search (pre-FTS O5 behavior): name OR any page ocr_text
  // LIKE %q%, newest-first. Retained for short-term / degenerate queries.
  Future<List<DocumentSummary>> _searchByLike(String q) async {
    final like = '%$q%';
    final idQuery = _db.select(_db.documents).join([
      leftOuterJoin(_db.pages, _db.pages.documentId.equalsExp(_db.documents.id)),
    ])
      ..where(_db.documents.name.like(like) | _db.pages.ocrText.like(like))
      ..groupBy([_db.documents.id]);
    final ids =
        (await idQuery.get()).map((r) => r.readTable(_db.documents).id).toSet();
    if (ids.isEmpty) return const [];
    return _summaries(onlyIds: ids);
  }

  // Ranked trigram search over per-document rows: bm25 relevance, with document
  // name matches ordered first. Returns summaries in relevance order.
  Future<List<DocumentSummary>> _searchRanked(
      String q, List<String> terms) async {
    final matchExpr = terms.map((t) => '"$t"').join(' AND ');
    final rows = await _db.customSelect(
      'SELECT rowid AS did, bm25(doc_fts) AS score '
      'FROM doc_fts WHERE doc_fts MATCH ? ORDER BY score',
      variables: [Variable.withString(matchExpr)],
    ).get();
    final textIds = rows.map((r) => r.read<int>('did')).toList(); // best first

    // Name matches: strong signal, and names are not in the trigram index.
    final nameRows = await (_db.select(_db.documents)
          ..where((t) => t.name.like('%$q%'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();

    final ordered = <int>[];
    final seen = <int>{};
    for (final d in nameRows) {
      if (seen.add(d.id)) ordered.add(d.id);
    }
    for (final id in textIds) {
      if (seen.add(id)) ordered.add(id);
    }
    if (ordered.isEmpty) return const [];

    final summaries = await _summaries(onlyIds: ordered.toSet());
    final rank = {for (var i = 0; i < ordered.length; i++) ordered[i]: i};
    summaries.sort(
        (a, b) => rank[a.document.id]!.compareTo(rank[b.document.id]!));
    return summaries;
  }
```

(`Variable`, `leftOuterJoin`, `OrderingTerm` all come from the already-imported `package:drift/drift.dart`; `customSelect` is on `_db`.)

- [ ] **Step 4: Run the new tests — verify PASS**

Run: `cd apps/mobile && flutter test test/features/library/search_ranking_test.dart`
Expected: **PASS** (6 tests).

- [ ] **Step 5: Verify existing O5 search tests stay green**

Run: `cd apps/mobile && flutter test test/features/library/search_documents_test.dart test/features/library/home_search_test.dart`
Expected: **PASS** unchanged (O5 cases assert membership, not cross-doc order; the fake-backed widget test is name-only). If any O5 case fails, STOP and reconcile — do not weaken a real assertion to make it pass.

- [ ] **Step 6: Analyze + full host suite**

Run: `cd apps/mobile && flutter analyze && flutter test`
Expected: analyze clean; whole host suite green.

- [ ] **Step 7: Commit**

```bash
cd apps/mobile && git add lib/features/library/drift/drift_document_repository.dart \
  test/features/library/search_ranking_test.dart
git commit -m "feat(search): ranked trigram searchDocuments with sanitize + LIKE fallback"
```

---

### Task 4: On-device BDD (multi-word across pages) + device verification

**Files:**
- Feature (create): `apps/mobile/integration_test/fts_search.feature`
- Test (create): `apps/mobile/integration_test/fts_search_device_test.dart`
- Reference (read for the seed+launch pattern): `apps/mobile/integration_test/o5_content_search_device_test.dart`

**Interfaces:**
- Consumes: production `library_dependencies` (real `MlKitOcrEngine`, real DB with v5 migration), the seed-then-launch BDD pattern.
- Produces: device-green proof the ranked engine finds a doc when the two query words are on different pages, and excludes a decoy.

- [ ] **Step 1: Read the existing device-search test to mirror its seed + launch pattern**

Run: `sed -n '1,60p' apps/mobile/integration_test/o5_content_search_device_test.dart`
Note how it (a) seeds documents/pages into the *real* on-device DB, (b) launches the app **reading that same storage** before any UI interaction (per the BDD-seed rule — a seed step alone doesn't pump the app), and (c) matches widgets by the `documents-*` keys.

- [ ] **Step 2: Write the `.feature`**

Create `apps/mobile/integration_test/fts_search.feature`:

```gherkin
Feature: Multi-word content search ranks and spans pages
  Scenario: A query whose words are on different pages still finds the document
    Given a saved document "Report" with page 1 text "ACME corporation" and page 3 text "final INVOICE"
    And a saved document "Decoy" with page 1 text "acme only, nothing else"
    And the app launches reading that same storage
    When I open search and type "acme invoice"
    Then I see the document "Report"
    And I do not see the document "Decoy"
```

- [ ] **Step 3: Write the device test implementing those steps**

Create `apps/mobile/integration_test/fts_search_device_test.dart`, mirroring the seed-and-launch helpers from `o5_content_search_device_test.dart` (Step 1). Seed via the repository/DB (two docs; "Report" gets page 1 = "ACME corporation" and page 3 = "final INVOICE" written to `ocr_text`; "Decoy" gets page 1 = "acme only, nothing else"), then pump `HomeScreen` reading that same storage, tap `Key('documents-search')`, enter `'acme invoice'` into `Key('documents-search-field')`, `pumpAndSettle`, and assert:

```dart
expect(find.text('Report'), findsOneWidget);
expect(find.text('Decoy'), findsNothing);
```

(Copy the exact seeding + `pumpWidget(MaterialApp(home: HomeScreen(libraryDependencies: ...)))` scaffolding from the O5 device test so the real v5 migration + triggers run on device. Do not `pumpAndSettle` on any perpetual spinner — settle only after the search results render.)

- [ ] **Step 4: Run on device — verify PASS**

Run: `cd apps/mobile && flutter test integration_test/fts_search_device_test.dart -d RZCY51D0T1K`
Expected: **PASS**. (If the Android Studio Gradle daemon poisons the build with an EPERM `.lock` error, temporarily set `org.gradle.daemon=false` in `android/gradle.properties`, run, then **revert it** — never commit that line. Gradle Bash calls need `dangerouslyDisableSandbox: true`.)

- [ ] **Step 5: Commit**

```bash
cd apps/mobile && git add integration_test/fts_search.feature \
  integration_test/fts_search_device_test.dart
git commit -m "test(search): on-device BDD — multi-word search spans pages, excludes decoy"
```

---

### Task 5: Docs + index update

**Files:**
- Modify: `docs/superpowers/specs/2026-07-03-fts5-search-ranking-design.md` (flip Status to Implemented)
- Modify: the specs/plans overview if it enumerates features (`docs/superpowers/specs/00-overview-roadmap.md` — check first)

- [ ] **Step 1: Mark the spec Implemented**

Edit the spec header `**Status:** Approved (design) — revised during planning` → `**Status:** Implemented`.

- [ ] **Step 2: Update the roadmap/index if it lists search**

Run: `grep -n "O5\|search" docs/superpowers/specs/00-overview-roadmap.md`
If search is listed, add a one-line entry noting the FTS5 trigram + ranking upgrade supersedes the O5 `LIKE` engine.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-03-fts5-search-ranking-design.md \
  docs/superpowers/specs/00-overview-roadmap.md
git commit -m "docs(search): mark FTS5 trigram search implemented"
```

---

## Self-Review

**Spec coverage:**
- Trigram tokenizer, no `unicode61` → Global Constraints + Task 2 SQL. ✓
- One row per document (cross-page AND) → Task 2 `_createFts` triggers + Task 2/3/4 tests. ✓
- Triggers-only sync, all write paths → Task 2 triggers on `pages` (fire for `runOcr`/split/merge/delete). ✓
- Migration v4→v5 + backfill → Task 2 Step 3 + backfill test. ✓
- Sanitization / never pass raw text to MATCH → Task 3 `_searchTerms` + operator-laden test. ✓
- Sub-3-char LIKE fallback → Task 3 `searchDocuments` guard + `'ab'` test. ✓
- bm25 ranking, name-first → Task 3 `_searchRanked` + ranking/name tests. ✓
- Results UI unchanged; O5 tests green → Task 3 Step 5. ✓
- FTS5 host-availability risk retired first → Task 1. ✓
- Device BDD multi-word across pages → Task 4. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; the one prose-described step (Task 4 Step 3) points at an exact existing file to mirror and lists the exact keys/strings/assertions. ✓

**Type consistency:** `searchDocuments`/`_searchByLike`/`_searchRanked`/`_searchTerms` names and signatures consistent across Task 3; `doc_fts` schema (`rowid`, `text`) and the `SELECT rowid, bm25(doc_fts) ... MATCH ?` contract identical in Task 2 (producer) and Task 3 (consumer); `backfillFtsForTest` defined in Task 2, used in Task 2 test only. ✓
