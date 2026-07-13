# Library Organization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add on-device folders, cross-cutting tags, and OCR-based title suggestions to the document library.

**Architecture:** Pure local metadata in Drift (three new tables + one nullable FK column, `schemaVersion` 8→9). The repository interface grows *additively* (no signature changes). `DocumentSummary` gains two *optional* fields. Folder/tag *filtering* is done in-memory in `HomeScreen` over the already-loaded enriched summaries — no new query methods. Auto-title is a pure service fed by already-persisted OCR text.

**Tech Stack:** Flutter, Drift (SQLite + FTS5), `bdd_widget_test`, `flutter_test`, `build_runner`.

## Global Constraints

- All commands run from `apps/mobile/`.
- **TDD:** write the failing test first, watch it fail, then implement.
- **Zero-warning bar:** `flutter analyze` must be clean.
- **Additive interface only:** never change an existing `DocumentRepository` method signature. Only `DriftDocumentRepository` and `test/support/fake_library.dart`'s `FakeDocumentRepository` implement the interface directly; the other test repos extend the fake.
- **Optional-only `DocumentSummary` fields:** new fields must have defaults so all existing construction sites keep compiling.
- **Never persist absolute image paths** (unchanged; this feature adds no image paths).
- **Image bytes stay on disk; DB is metadata only** (unchanged).
- **Regenerate codegen** with `dart run build_runner build --delete-conflicting-outputs` after any Drift table change or new `.feature` file.
- **Feature flags default ON**, threaded through `LibraryDependencies.features`, gating every entry point.
- **Both platforms:** device integration test must pass on a real Android device AND a real iOS device (Android `RZCY51D0T1K`, iPhone `00008120-0016355C21E8201E`).
- **Commit trailers** on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01L3kDELJpCq1Hr31ACZxdH4
  ```

---

## Task 1: Schema + v9 migration (foundation — unblocks everything)

**Files:**
- Modify: `lib/features/library/drift/app_database.dart`
- Modify: `test/features/library/drift/migration_test.dart` (`schemaVersion` assertion + v8→v9 case)
- Modify: `test/features/library/schema_migration_v7_test.dart` (`schemaVersion` assertion)
- Regenerate: `lib/features/library/drift/app_database.g.dart`

**Interfaces:**
- Produces: Drift tables `Folders`, `Tags`, `DocumentTags`; new nullable `Documents.folderId` column; generated data classes `Folder`(drift), `Tag`(drift) and companions `FoldersCompanion`, `TagsCompanion`, `DocumentTagsCompanion`; table getters `db.folders`, `db.tags`, `db.documentTags`. **Note:** the generated drift row classes are named `Folder`/`Tag` — the domain models in Task 3 live in separate files and are imported where needed; inside `app_database.dart` consumers use the `hide`/`show` already present in the repo.

- [ ] **Step 1: Write the failing migration test (v8→v9)**

Add to `test/features/library/drift/migration_test.dart` (near the existing v-step tests). First read the file to reuse its raw-DB helper style; add a helper `_buildV8Db(sqlite.Database raw)` that creates the v8 shape (documents with `is_id_card`, pages with all columns through `enhancer_mode`, the FTS vtable + triggers) and sets `PRAGMA user_version = 8;`. Then:

```dart
test('v8 -> v9 adds folders/tags/document_tags and documents.folder_id, '
    'preserving existing rows', () async {
  final file = File('${Directory.systemTemp.createTempSync().path}/v8.sqlite');
  addTearDown(() => file.existsSync() ? file.deleteSync() : null);
  final raw = sqlite.sqlite3.open(file.path);
  _buildV8Db(raw);
  raw.execute(
    "INSERT INTO documents (name, created_at, modified_at, is_id_card) "
    "VALUES ('Doc A', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 0)",
  );
  raw.dispose();

  final db = AppDatabase(NativeDatabase(file));
  addTearDown(db.close);

  // Triggers migration by touching the DB.
  final docs = await db.select(db.documents).get();
  expect(docs.single.name, 'Doc A');
  expect(docs.single.folderId, isNull); // new column, defaults null

  // New tables usable.
  final now = DateTime.utc(2026, 2, 1);
  final fid = await db.into(db.folders).insert(
      FoldersCompanion.insert(name: 'Receipts', createdAt: now));
  final tid = await db.into(db.tags).insert(
      TagsCompanion.insert(name: 'tax', createdAt: now));
  await db.into(db.documentTags).insert(
      DocumentTagsCompanion.insert(documentId: docs.single.id, tagId: tid));
  expect((await db.select(db.folders).get()).single.name, 'Receipts');
  expect((await db.select(db.documentTags).get()).length, 1);
  expect(fid, isNonNegative);
});
```

- [ ] **Step 2: Update both `schemaVersion` assertions to 9**

In `test/features/library/drift/migration_test.dart:240` and `test/features/library/schema_migration_v7_test.dart:8`, change `expect(db.schemaVersion, 8)` → `expect(db.schemaVersion, 9)`.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/features/library/drift/migration_test.dart test/features/library/schema_migration_v7_test.dart`
Expected: FAIL (schemaVersion is 8; `db.folders` undefined).

- [ ] **Step 4: Add the tables + column + migration step**

In `lib/features/library/drift/app_database.dart`, add after the `Pages` class:

```dart
/// A flat (non-nested) folder. A document lives in at most one folder via
/// Documents.folderId; null there means "Unfiled".
class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
}

/// A cross-cutting label. A document carries 0+ tags via DocumentTags.
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Many-to-many join between documents and tags. Rows are cascade-deleted when
/// either side is removed (foreign_keys pragma is ON, see beforeOpen).
class DocumentTags extends Table {
  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId =>
      integer().references(Tags, #id, onDelete: KeyAction.cascade)();
  @override
  Set<Column> get primaryKey => {documentId, tagId};
}
```

Add the folder FK column to `Documents` (after `isIdCard`):

```dart
  /// Owning folder (flat). Null = "Unfiled". SET NULL on folder delete so
  /// deleting a folder never deletes its documents.
  IntColumn get folderId =>
      integer().nullable().references(Folders, #id, onDelete: KeyAction.setNull)();
```

Update the annotation and version:

```dart
@DriftDatabase(tables: [Documents, Pages, Folders, Tags, DocumentTags])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 9;
```

Add the migration step at the END of `onUpgrade` (order matters — `folders` must exist before the FK column is added):

```dart
      if (from < 9) {
        await m.createTable(folders);
        await m.createTable(tags);
        await m.createTable(documentTags);
        await m.addColumn(documents, documents.folderId);
      }
```

- [ ] **Step 5: Regenerate drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `app_database.g.dart` updated; no errors.

- [ ] **Step 6: Run the migration + full drift tests**

Run: `flutter test test/features/library/drift/ test/features/library/schema_migration_v7_test.dart`
Expected: PASS (incl. the pre-existing v3→ and v5→ step-through tests, which now traverse v9).

- [ ] **Step 7: Analyze + commit**

Run: `flutter analyze lib/features/library/drift`
Expected: no issues.

```bash
git add lib/features/library/drift/app_database.dart lib/features/library/drift/app_database.g.dart test/features/library/drift/migration_test.dart test/features/library/schema_migration_v7_test.dart
git commit -m "feat(library): v9 schema — folders, tags, document_tags, documents.folderId"
```

---

## Task 2: Domain models `Folder` and `Tag`

**Files:**
- Create: `lib/features/library/folder.dart`
- Create: `lib/features/library/tag.dart`
- Create: `test/features/library/folder_test.dart`

**Interfaces:**
- Produces: `Folder({required int id, required String name, required DateTime createdAt})` and `Tag({required int id, required String name, required DateTime createdAt})`, both `const`-constructible with value equality.

- [ ] **Step 1: Write the failing test**

`test/features/library/folder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/folder.dart';
import 'package:mobile/features/library/tag.dart';

void main() {
  test('Folder has value equality', () {
    final a = Folder(id: 1, name: 'Receipts', createdAt: DateTime.utc(2026));
    final b = Folder(id: 1, name: 'Receipts', createdAt: DateTime.utc(2026));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('Tag has value equality', () {
    final a = Tag(id: 2, name: 'tax', createdAt: DateTime.utc(2026));
    final b = Tag(id: 2, name: 'tax', createdAt: DateTime.utc(2026));
    expect(a, b);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/library/folder_test.dart`
Expected: FAIL ("folder.dart" not found).

- [ ] **Step 3: Implement the models**

`lib/features/library/folder.dart`:

```dart
/// A flat (non-nested) folder that groups documents. Domain model, decoupled
/// from the generated drift row of the same name.
class Folder {
  final int id;
  final String name;
  final DateTime createdAt;
  const Folder({required this.id, required this.name, required this.createdAt});

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, createdAt);
}
```

`lib/features/library/tag.dart`:

```dart
/// A cross-cutting label attached to 0+ documents. Domain model, decoupled from
/// the generated drift row of the same name.
class Tag {
  final int id;
  final String name;
  final DateTime createdAt;
  const Tag({required this.id, required this.name, required this.createdAt});

  @override
  bool operator ==(Object other) =>
      other is Tag &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, createdAt);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/library/folder_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/folder.dart lib/features/library/tag.dart test/features/library/folder_test.dart
git commit -m "feat(library): Folder and Tag domain models"
```

---

## Task 3: `TitleSuggester` pure service (no schema dependency)

**Files:**
- Create: `lib/features/library/title_suggester.dart`
- Create: `test/features/library/title_suggester_test.dart`

**Interfaces:**
- Produces: `class TitleSuggester { const TitleSuggester(); String? suggest(String ocrText); }` — returns the first usable title line (≤40 chars, ellipsized if longer), or `null` for empty/garbage.

- [ ] **Step 1: Write the failing tests**

`test/features/library/title_suggester_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/title_suggester.dart';

void main() {
  const s = TitleSuggester();

  test('returns null for empty/whitespace/garbage', () {
    expect(s.suggest(''), isNull);
    expect(s.suggest('   \n  \n'), isNull);
    expect(s.suggest('!!! ---'), isNull);
  });

  test('uses the first meaningful line', () {
    expect(s.suggest('INVOICE\nAcme Corp\n2026'), 'INVOICE');
  });

  test('skips short/noise leading lines', () {
    expect(s.suggest('#\nCity Water Bill\n...'), 'City Water Bill');
  });

  test('collapses internal whitespace and trims punctuation edges', () {
    expect(s.suggest('  ***  Receipt   #42  ***  '), 'Receipt   #42');
  });

  test('ellipsizes very long lines to 40 chars', () {
    final long = 'A' * 60;
    final out = s.suggest(long)!;
    expect(out.length, 41); // 40 chars + ellipsis
    expect(out.endsWith('…'), isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/library/title_suggester_test.dart`
Expected: FAIL ("title_suggester.dart" not found).

- [ ] **Step 3: Implement**

`lib/features/library/title_suggester.dart`:

```dart
/// Suggests a document title from recognized OCR text. Pure — no DB, no native
/// deps — so it is exhaustively unit-testable on the host. Returns the first
/// "meaningful" line (has letters/digits, >= 3 chars after edge-punctuation is
/// trimmed), capped at [_maxLen] with an ellipsis, or null when nothing usable.
class TitleSuggester {
  const TitleSuggester();

  static const int _maxLen = 40;
  static final RegExp _ws = RegExp(r'\s+');
  static final RegExp _edgePunct = RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$');
  static final RegExp _alnum = RegExp(r'[A-Za-z0-9]');

  String? suggest(String ocrText) {
    for (final rawLine in ocrText.split('\n')) {
      final collapsed = rawLine.replaceAll(_ws, ' ').trim();
      final cleaned = collapsed.replaceAll(_edgePunct, '');
      if (cleaned.length < 3) continue;
      if (!_alnum.hasMatch(cleaned)) continue;
      if (cleaned.length <= _maxLen) return cleaned;
      return '${cleaned.substring(0, _maxLen).trimRight()}…';
    }
    return null;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/library/title_suggester_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/title_suggester.dart test/features/library/title_suggester_test.dart
git commit -m "feat(library): TitleSuggester pure service"
```

---

## Task 4: `DocumentSummary` optional enrichment fields

**Files:**
- Modify: `lib/features/library/document_summary.dart`
- Create: `test/features/library/document_summary_test.dart`

**Interfaces:**
- Consumes: `Tag` (Task 2).
- Produces: `DocumentSummary` gains `final int? folderId;` (default `null`) and `final List<Tag> tags;` (default `const []`). Existing positional/named usage is unaffected.

- [ ] **Step 1: Write the failing test**

`test/features/library/document_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/tag.dart';

void main() {
  final doc = Document(
    id: 1, name: 'D', createdAt: DateTime.utc(2026), modifiedAt: DateTime.utc(2026));

  test('defaults: folderId null, tags empty', () {
    final s = DocumentSummary(document: doc, pageCount: 1);
    expect(s.folderId, isNull);
    expect(s.tags, isEmpty);
  });

  test('carries folderId and tags when provided', () {
    final s = DocumentSummary(
      document: doc, pageCount: 1, folderId: 7,
      tags: [Tag(id: 2, name: 'tax', createdAt: DateTime.utc(2026))]);
    expect(s.folderId, 7);
    expect(s.tags.single.name, 'tax');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/library/document_summary_test.dart`
Expected: FAIL (no `folderId`/`tags`).

- [ ] **Step 3: Add the optional fields**

In `lib/features/library/document_summary.dart`, add the import and fields:

```dart
import 'document.dart';
import 'tag.dart';

class DocumentSummary {
  final Document document;
  final int pageCount;
  final String? thumbnailPath;
  final int? folderId;
  final List<Tag> tags;

  const DocumentSummary({
    required this.document,
    required this.pageCount,
    this.thumbnailPath,
    this.folderId,
    this.tags = const [],
  });
}
```

- [ ] **Step 4: Run to verify it passes + whole library suite still compiles**

Run: `flutter test test/features/library/document_summary_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/library test/features/library test/support`
Expected: no issues (all existing `DocumentSummary(...)` sites still valid).

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/document_summary.dart test/features/library/document_summary_test.dart
git commit -m "feat(library): optional folderId + tags on DocumentSummary"
```

---

## Task 5: Repository interface additions + fake stubs

**Files:**
- Modify: `lib/features/library/document_repository.dart` (interface + imports)
- Modify: `test/support/fake_library.dart` (`FakeDocumentRepository` in-memory impl)
- Create: `test/support/fake_library_org_test.dart` (drives the fake's folder/tag behavior)

**Interfaces:**
- Consumes: `Folder`, `Tag` (Task 2).
- Produces (added to `DocumentRepository`):
  ```dart
  Future<List<Folder>> listFolders();
  Future<Folder> createFolder(String name);
  Future<Folder> renameFolder(int folderId, String newName);
  Future<void> deleteFolder(int folderId);
  Future<void> moveToFolder(int documentId, int? folderId);
  Future<List<Tag>> listTags();
  Future<Tag> createTag(String name);
  Future<void> deleteTag(int tagId);
  Future<List<Tag>> tagsForDocument(int documentId);
  Future<void> setDocumentTags(int documentId, Set<int> tagIds);
  Future<String?> suggestTitleFor(int documentId);
  ```

- [ ] **Step 1: Add the interface methods (with dartdoc)**

In `lib/features/library/document_repository.dart`, add `import 'folder.dart';` and `import 'tag.dart';`, then declare the eleven methods above inside `abstract interface class DocumentRepository`, each with a one-line dartdoc (e.g. `/// Lists all folders, name-ascending.`). `moveToFolder`: `null` folderId = Unfiled. `createTag`: dedupes by case-insensitive name. `suggestTitleFor`: returns null when page-1 OCR is absent/unusable.

- [ ] **Step 2: Run analyze to see the fake break**

Run: `flutter analyze test/support/fake_library.dart`
Expected: FAIL — `FakeDocumentRepository` is missing 11 members.

- [ ] **Step 3: Write the failing fake test**

`test/support/fake_library_org_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'fake_library.dart';

void main() {
  test('fake folders: create/list/move/delete-to-unfiled', () async {
    final repo = FakeDocumentRepository();
    final f = await repo.createFolder('Receipts');
    expect((await repo.listFolders()).single.id, f.id);

    final doc = await repo.createDocumentForTest(name: 'D'); // existing helper
    await repo.moveToFolder(doc.id, f.id);
    expect((await repo.listDocumentSummaries()).single.folderId, f.id);

    await repo.deleteFolder(f.id);
    expect(await repo.listFolders(), isEmpty);
    expect((await repo.listDocumentSummaries()).single.folderId, isNull);
  });

  test('fake tags: create dedupes, setDocumentTags, enrichment', () async {
    final repo = FakeDocumentRepository();
    final t1 = await repo.createTag('Tax');
    final t2 = await repo.createTag('tax'); // dedupe
    expect(t2.id, t1.id);

    final doc = await repo.createDocumentForTest(name: 'D');
    await repo.setDocumentTags(doc.id, {t1.id});
    expect((await repo.listDocumentSummaries()).single.tags.single.name, 'Tax');
  });
}
```

> If `FakeDocumentRepository` has no `createDocumentForTest` helper, read the top of `fake_library.dart` first and use whatever existing seeding entry point it exposes (e.g. adding to its `documents` list). Adjust the test to that API rather than inventing one.

- [ ] **Step 4: Implement the fake methods in-memory**

In `FakeDocumentRepository`, add fields and methods (adapt to the fake's existing storage style — it keeps a `List<Document> documents`):

```dart
final List<Folder> _folders = [];
final List<Tag> _tags = [];
int _nextFolderId = 1;
int _nextTagId = 1;
final Map<int, int?> _docFolder = {};        // documentId -> folderId
final Map<int, Set<int>> _docTags = {};       // documentId -> tagIds

@override
Future<List<Folder>> listFolders() async =>
    [..._folders]..sort((a, b) => a.name.compareTo(b.name));

@override
Future<Folder> createFolder(String name) async {
  final f = Folder(id: _nextFolderId++, name: name.trim(), createdAt: DateTime.utc(2026));
  _folders.add(f);
  return f;
}

@override
Future<Folder> renameFolder(int folderId, String newName) async {
  final i = _folders.indexWhere((f) => f.id == folderId);
  final updated = Folder(id: folderId, name: newName.trim(), createdAt: _folders[i].createdAt);
  _folders[i] = updated;
  return updated;
}

@override
Future<void> deleteFolder(int folderId) async {
  _folders.removeWhere((f) => f.id == folderId);
  _docFolder.updateAll((k, v) => v == folderId ? null : v); // setNull semantics
}

@override
Future<void> moveToFolder(int documentId, int? folderId) async =>
    _docFolder[documentId] = folderId;

@override
Future<List<Tag>> listTags() async =>
    [..._tags]..sort((a, b) => a.name.compareTo(b.name));

@override
Future<Tag> createTag(String name) async {
  final trimmed = name.trim();
  final existing = _tags.where((t) => t.name.toLowerCase() == trimmed.toLowerCase());
  if (existing.isNotEmpty) return existing.first;
  final t = Tag(id: _nextTagId++, name: trimmed, createdAt: DateTime.utc(2026));
  _tags.add(t);
  return t;
}

@override
Future<void> deleteTag(int tagId) async {
  _tags.removeWhere((t) => t.id == tagId);
  for (final s in _docTags.values) {
    s.remove(tagId);
  }
}

@override
Future<List<Tag>> tagsForDocument(int documentId) async {
  final ids = _docTags[documentId] ?? const <int>{};
  return _tags.where((t) => ids.contains(t.id)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
}

@override
Future<void> setDocumentTags(int documentId, Set<int> tagIds) async =>
    _docTags[documentId] = {...tagIds};

@override
Future<String?> suggestTitleFor(int documentId) async => null; // no OCR in fake
```

Then, in the fake's existing `listDocumentSummaries()` builder, set `folderId: _docFolder[doc.id]` and `tags: await tagsForDocument(doc.id)` on each `DocumentSummary`. Add `import` lines for `folder.dart`, `tag.dart`, and `title_suggester.dart` as needed.

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/support/fake_library_org_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/library test/support`
Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/document_repository.dart test/support/fake_library.dart test/support/fake_library_org_test.dart
git commit -m "feat(library): repository folder/tag/suggest-title interface + fake"
```

---

## Task 6: Drift repository — folder methods

**Files:**
- Modify: `lib/features/library/drift/drift_document_repository.dart`
- Create: `test/features/library/drift/folder_repository_test.dart`

**Interfaces:**
- Consumes: Task 1 tables, Task 5 interface, `Folder` (Task 2).
- Produces: `DriftDocumentRepository` implementations of `listFolders/createFolder/renameFolder/deleteFolder/moveToFolder`.

- [ ] **Step 1: Write the failing tests**

`test/features/library/drift/folder_repository_test.dart` — build a repo over an in-memory DB (copy the repo-construction helper from the existing `drift_document_repository_test.dart`; it wires a `NativeDatabase.memory()`, temp `DocumentFileStore`, a fixed clock, and a stub warper). Cover:

```dart
test('createFolder trims and lists name-ascending', () async {
  final r = repo();
  await r.createFolder('  Zed ');
  await r.createFolder('Alpha');
  final names = (await r.listFolders()).map((f) => f.name).toList();
  expect(names, ['Alpha', 'Zed']);
});

test('createFolder rejects empty name', () async {
  expect(() => repo().createFolder('   '), throwsA(isA<DocumentSaveException>()));
});

test('moveToFolder sets folderId on the summary; null unfiles it', () async {
  final r = repo();
  final doc = await _seedOneDoc(r); // helper: creates a doc via createFromCapture
  final f = await r.createFolder('Receipts');
  await r.moveToFolder(doc.id, f.id);
  expect((await r.listDocumentSummaries()).single.folderId, f.id);
  await r.moveToFolder(doc.id, null);
  expect((await r.listDocumentSummaries()).single.folderId, isNull);
});

test('deleteFolder unfiles member documents (SET NULL), keeps the document', () async {
  final r = repo();
  final doc = await _seedOneDoc(r);
  final f = await r.createFolder('Receipts');
  await r.moveToFolder(doc.id, f.id);
  await r.deleteFolder(f.id);
  expect(await r.listFolders(), isEmpty);
  final s = await r.listDocumentSummaries();
  expect(s.single.document.id, doc.id); // document survived
  expect(s.single.folderId, isNull);    // unfiled
});

test('renameFolder updates name; unknown id throws', () async {
  final r = repo();
  final f = await r.createFolder('Old');
  final renamed = await r.renameFolder(f.id, 'New');
  expect(renamed.name, 'New');
  expect(() => r.renameFolder(9999, 'X'), throwsA(isA<DocumentSaveException>()));
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/library/drift/folder_repository_test.dart`
Expected: FAIL (methods throw `UnimplementedError`/missing).

- [ ] **Step 3: Implement folder methods**

Add to `DriftDocumentRepository` (and `import '../folder.dart';`):

```dart
@override
Future<List<Folder>> listFolders() async {
  final rows = await (_db.select(_db.folders)
        ..orderBy([(f) => OrderingTerm.asc(f.name)]))
      .get();
  return [
    for (final r in rows) Folder(id: r.id, name: r.name, createdAt: r.createdAt),
  ];
}

@override
Future<Folder> createFolder(String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    throw const DocumentSaveException('createFolder: empty name');
  }
  final now = _clock().toUtc();
  final id = await _db
      .into(_db.folders)
      .insert(FoldersCompanion.insert(name: trimmed, createdAt: now));
  return Folder(id: id, name: trimmed, createdAt: now);
}

@override
Future<Folder> renameFolder(int folderId, String newName) async {
  final trimmed = newName.trim();
  if (trimmed.isEmpty) {
    throw const DocumentSaveException('renameFolder: empty name');
  }
  final updated = await (_db.update(_db.folders)
        ..where((f) => f.id.equals(folderId)))
      .write(FoldersCompanion(name: Value(trimmed)));
  if (updated == 0) {
    throw const DocumentSaveException('renameFolder: no such folder');
  }
  final row = await (_db.select(_db.folders)
        ..where((f) => f.id.equals(folderId)))
      .getSingle();
  return Folder(id: row.id, name: row.name, createdAt: row.createdAt);
}

@override
Future<void> deleteFolder(int folderId) async {
  // Member documents are unfiled automatically by the FK's ON DELETE SET NULL
  // (foreign_keys pragma is ON). The document rows and files are untouched.
  await (_db.delete(_db.folders)..where((f) => f.id.equals(folderId))).go();
}

@override
Future<void> moveToFolder(int documentId, int? folderId) async {
  final updated = await (_db.update(_db.documents)
        ..where((d) => d.id.equals(documentId)))
      .write(DocumentsCompanion(
        folderId: Value(folderId),
        modifiedAt: Value(_clock().toUtc()),
      ));
  if (updated == 0) {
    throw const DocumentSaveException('moveToFolder: no such document');
  }
}
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/features/library/drift/folder_repository_test.dart`
Expected: PASS. (If `deleteFolder`'s SET-NULL assertion fails on the in-memory DB, confirm `PRAGMA foreign_keys = ON` is active — it is set in `beforeOpen`; the in-memory repo helper must open through `AppDatabase` so `beforeOpen` runs.)
Run: `flutter analyze lib/features/library/drift`

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/drift/drift_document_repository.dart test/features/library/drift/folder_repository_test.dart
git commit -m "feat(library): drift folder methods"
```

---

## Task 7: Drift repository — tag methods + `suggestTitleFor` + summary enrichment

**Files:**
- Modify: `lib/features/library/drift/drift_document_repository.dart`
- Create: `test/features/library/drift/tag_repository_test.dart`
- Modify: `test/features/library/drift_document_repository_test.dart` (add enrichment assertions)

**Interfaces:**
- Consumes: Task 1 tables, Task 3 `TitleSuggester`, Task 2 `Tag`.
- Produces: tag methods, `suggestTitleFor`, and enriched `_summaries()` (populates `folderId` + `tags` with no N+1).

- [ ] **Step 1: Write the failing tag tests**

`test/features/library/drift/tag_repository_test.dart` (same in-memory repo helper):

```dart
test('createTag dedupes case-insensitively', () async {
  final r = repo();
  final a = await r.createTag('Tax');
  final b = await r.createTag('tax');
  expect(b.id, a.id);
  expect((await r.listTags()).length, 1);
});

test('setDocumentTags replaces the set; tagsForDocument reflects it', () async {
  final r = repo();
  final doc = await _seedOneDoc(r);
  final t1 = await r.createTag('a');
  final t2 = await r.createTag('b');
  await r.setDocumentTags(doc.id, {t1.id, t2.id});
  expect((await r.tagsForDocument(doc.id)).map((t) => t.name), ['a', 'b']);
  await r.setDocumentTags(doc.id, {t2.id});
  expect((await r.tagsForDocument(doc.id)).map((t) => t.name), ['b']);
});

test('summary is enriched with tags', () async {
  final r = repo();
  final doc = await _seedOneDoc(r);
  final t = await r.createTag('tax');
  await r.setDocumentTags(doc.id, {t.id});
  expect((await r.listDocumentSummaries()).single.tags.single.name, 'tax');
});

test('deleting a document cascade-removes its tag links (no leak)', () async {
  final r = repo();
  final doc = await _seedOneDoc(r);
  final t = await r.createTag('tax');
  await r.setDocumentTags(doc.id, {t.id});
  await r.deleteDocument(doc.id);
  expect(await r.tagsForDocument(doc.id), isEmpty);
  expect((await r.listTags()).length, 1); // the tag itself survives
});

test('suggestTitleFor returns null before OCR, value after', () async {
  final r = repo(); // repo() uses NoOpOcrEngine by default
  final doc = await _seedOneDoc(r);
  expect(await r.suggestTitleFor(doc.id), isNull);
  // simulate OCR having run by writing ocr_text directly through the repo's DB
  await setPageOcrText(doc.id, 1, 'INVOICE\nAcme'); // test helper via db update
  expect(await r.suggestTitleFor(doc.id), 'INVOICE');
});
```

> Add a small test helper `setPageOcrText` that runs `db.update(db.pages)` on the test DB, mirroring how existing tests reach into the in-memory DB. If the repo helper does not expose the `AppDatabase`, construct the repo with a DB handle you keep a reference to.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/library/drift/tag_repository_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement tag methods + suggestTitleFor**

Add to `DriftDocumentRepository` (`import '../tag.dart';`, `import '../title_suggester.dart';`):

```dart
@override
Future<List<Tag>> listTags() async {
  final rows = await (_db.select(_db.tags)
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();
  return [
    for (final r in rows) Tag(id: r.id, name: r.name, createdAt: r.createdAt),
  ];
}

@override
Future<Tag> createTag(String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    throw const DocumentSaveException('createTag: empty name');
  }
  final existing = await (_db.select(_db.tags)
        ..where((t) => t.name.lower().equals(trimmed.toLowerCase())))
      .getSingleOrNull();
  if (existing != null) {
    return Tag(id: existing.id, name: existing.name, createdAt: existing.createdAt);
  }
  final now = _clock().toUtc();
  final id = await _db
      .into(_db.tags)
      .insert(TagsCompanion.insert(name: trimmed, createdAt: now));
  return Tag(id: id, name: trimmed, createdAt: now);
}

@override
Future<void> deleteTag(int tagId) async {
  await (_db.delete(_db.tags)..where((t) => t.id.equals(tagId))).go();
}

@override
Future<List<Tag>> tagsForDocument(int documentId) async {
  final query = _db.select(_db.tags).join([
    innerJoin(_db.documentTags, _db.documentTags.tagId.equalsExp(_db.tags.id)),
  ])
    ..where(_db.documentTags.documentId.equals(documentId))
    ..orderBy([OrderingTerm.asc(_db.tags.name)]);
  final rows = await query.get();
  return [
    for (final r in rows)
      () {
        final t = r.readTable(_db.tags);
        return Tag(id: t.id, name: t.name, createdAt: t.createdAt);
      }(),
  ];
}

@override
Future<void> setDocumentTags(int documentId, Set<int> tagIds) async {
  await _db.transaction(() async {
    await (_db.delete(_db.documentTags)
          ..where((dt) => dt.documentId.equals(documentId)))
        .go();
    for (final tid in tagIds) {
      await _db
          .into(_db.documentTags)
          .insert(DocumentTagsCompanion.insert(documentId: documentId, tagId: tid));
    }
  });
}

@override
Future<String?> suggestTitleFor(int documentId) async {
  final page = await (_db.select(_db.pages)
        ..where((p) => p.documentId.equals(documentId))
        ..orderBy([(p) => OrderingTerm.asc(p.position)])
        ..limit(1))
      .getSingleOrNull();
  final text = page?.ocrText;
  if (text == null || text.trim().isEmpty) return null;
  return const TitleSuggester().suggest(text);
}
```

- [ ] **Step 4: Enrich `_summaries()`**

In `_summaries()`, after the first-page-path map (block 2), add a tags map (block 3), then set `folderId` + `tags` on each returned `DocumentSummary`:

```dart
    // (3) tags per document — one join query, no N+1.
    final tagRows = await (_db.select(_db.documentTags).join([
      innerJoin(_db.tags, _db.tags.id.equalsExp(_db.documentTags.tagId)),
    ])..orderBy([OrderingTerm.asc(_db.tags.name)]))
        .get();
    final tagsByDoc = <int, List<Tag>>{};
    for (final r in tagRows) {
      final dt = r.readTable(_db.documentTags);
      final t = r.readTable(_db.tags);
      (tagsByDoc[dt.documentId] ??= []).add(
        Tag(id: t.id, name: t.name, createdAt: t.createdAt),
      );
    }
```

and in the `rows.map((row) {...})` return:

```dart
      return DocumentSummary(
        document: Document(
          id: d.id,
          name: d.name,
          createdAt: d.createdAt,
          modifiedAt: d.modifiedAt,
        ),
        pageCount: row.read(pageCount)!,
        thumbnailPath: rel == null ? null : _fileStore.absoluteFor(rel).path,
        folderId: d.folderId,
        tags: tagsByDoc[d.id] ?? const [],
      );
```

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/features/library/drift/`
Expected: PASS.
Run: `flutter analyze lib/features/library/drift`

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/drift/drift_document_repository.dart test/features/library/drift/tag_repository_test.dart test/features/library/drift_document_repository_test.dart
git commit -m "feat(library): drift tag methods, suggestTitleFor, summary enrichment"
```

---

## Task 8: Feature flags

**Files:**
- Modify: `lib/features/library/feature_flags.dart`
- Modify: `test/features/library/feature_flags_test.dart` (create if absent)

**Interfaces:**
- Produces: `FeatureFlags` gains `folders`, `tags`, `smartTitles` (all default `true`, from `FEATURE_FOLDERS`/`FEATURE_TAGS`/`FEATURE_SMART_TITLES`).

- [ ] **Step 1: Write the failing test**

`test/features/library/feature_flags_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';

void main() {
  test('new org flags default on', () {
    const f = FeatureFlags();
    expect(f.folders, isTrue);
    expect(f.tags, isTrue);
    expect(f.smartTitles, isTrue);
  });

  test('flags are overridable for tests', () {
    const f = FeatureFlags(folders: false, tags: false, smartTitles: false);
    expect(f.folders, isFalse);
    expect(f.tags, isFalse);
    expect(f.smartTitles, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/library/feature_flags_test.dart`
Expected: FAIL (no `folders` getter).

- [ ] **Step 3: Add the flags**

In `lib/features/library/feature_flags.dart`, add three fields and constructor defaults following the existing pattern:

```dart
  final bool folders;
  final bool tags;
  final bool smartTitles;
```
```dart
    this.folders =
        const bool.fromEnvironment('FEATURE_FOLDERS', defaultValue: true),
    this.tags =
        const bool.fromEnvironment('FEATURE_TAGS', defaultValue: true),
    this.smartTitles =
        const bool.fromEnvironment('FEATURE_SMART_TITLES', defaultValue: true),
```

- [ ] **Step 4: Run to verify pass + analyze**

Run: `flutter test test/features/library/feature_flags_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/library/feature_flags.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/feature_flags.dart test/features/library/feature_flags_test.dart
git commit -m "feat(library): FEATURE_FOLDERS/TAGS/SMART_TITLES flags"
```

---

## Task 9: Folder filter bar widget + in-memory filtering (UI)

**Files:**
- Create: `lib/features/library/widgets/folder_filter_bar.dart`
- Create: `lib/features/library/widgets/create_folder_dialog.dart`
- Modify: `lib/features/library/home_screen.dart` (state: active folder; render bar; filter `_displayed`)
- Create: `test/features/library/widgets/folder_filter_bar_test.dart`
- Create: `test/bdd/library/folder_filter.feature`
- Create/modify: `test/step/*.dart` steps (regenerated)

**Interfaces:**
- Consumes: `Folder` (Task 2), `FeatureFlags.folders` (Task 8), repo folder methods (Task 6), enriched summaries (Task 7).
- Produces: `FolderFilterBar` widget; `HomeScreen` filters `_displayed` by `_activeFolderId` (a sentinel enum: all / unfiled / a specific id).

- [ ] **Step 1: Write the failing widget test**

`test/features/library/widgets/folder_filter_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/folder.dart';
import 'package:mobile/features/library/widgets/folder_filter_bar.dart';

void main() {
  testWidgets('renders All/Unfiled + folder chips with counts; taps callback',
      (tester) async {
    FolderFilter? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FolderFilterBar(
          folders: [Folder(id: 1, name: 'Receipts', createdAt: DateTime.utc(2026))],
          counts: const {1: 3, null: 5}, // folderId -> count; null = unfiled
          active: const FolderFilter.all(),
          onChanged: (f) => picked = f,
          onCreateFolder: () {},
        ),
      ),
    ));
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Unfiled'), findsOneWidget);
    expect(find.text('Receipts'), findsOneWidget);
    await tester.tap(find.text('Receipts'));
    expect(picked, const FolderFilter.folder(1));
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/library/widgets/folder_filter_bar_test.dart`
Expected: FAIL (widget missing).

- [ ] **Step 3: Implement `FolderFilter` + `FolderFilterBar`**

`lib/features/library/widgets/folder_filter_bar.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../theme/ream_colors.dart';
import '../folder.dart';

/// The active folder filter: everything, only unfiled, or one folder id.
sealed class FolderFilter {
  const FolderFilter();
  const factory FolderFilter.all() = _AllFilter;
  const factory FolderFilter.unfiled() = _UnfiledFilter;
  const factory FolderFilter.folder(int id) = _FolderFilter;
}

class _AllFilter extends FolderFilter {
  const _AllFilter();
  @override
  bool operator ==(Object other) => other is _AllFilter;
  @override
  int get hashCode => 0;
}

class _UnfiledFilter extends FolderFilter {
  const _UnfiledFilter();
  @override
  bool operator ==(Object other) => other is _UnfiledFilter;
  @override
  int get hashCode => 1;
}

class _FolderFilter extends FolderFilter {
  final int id;
  const _FolderFilter(this.id);
  @override
  bool operator ==(Object other) => other is _FolderFilter && other.id == id;
  @override
  int get hashCode => Object.hash(2, id);
}

/// Horizontal, single-select filter chips: All · Unfiled · <folder> (n) · ＋.
/// Rendered by HomeScreen only when at least one folder exists.
class FolderFilterBar extends StatelessWidget {
  final List<Folder> folders;
  final Map<int?, int> counts; // folderId (null=unfiled) -> document count
  final FolderFilter active;
  final ValueChanged<FolderFilter> onChanged;
  final VoidCallback onCreateFolder;

  const FolderFilterBar({
    super.key,
    required this.folders,
    required this.counts,
    required this.active,
    required this.onChanged,
    required this.onCreateFolder,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _chip(context, const FolderFilter.all(), 'All', null),
          _chip(context, const FolderFilter.unfiled(), 'Unfiled', counts[null]),
          for (final f in folders)
            _chip(context, FolderFilter.folder(f.id), f.name, counts[f.id]),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ActionChip(
              key: const Key('folder-create'),
              label: const Icon(Icons.add, size: 18),
              onPressed: onCreateFolder,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, FolderFilter f, String label, int? count) {
    final selected = f == active;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(count == null ? label : '$label ($count)'),
        selected: selected,
        onSelected: (_) => onChanged(f),
      ),
    );
  }
}
```

`lib/features/library/widgets/create_folder_dialog.dart` — a text-field dialog returning the entered name (mirror `rename_dialog.dart`'s structure; read that file and follow its pattern). Return `String?` (null on cancel).

- [ ] **Step 4: Run widget test to pass**

Run: `flutter test test/features/library/widgets/folder_filter_bar_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire into `HomeScreen`**

In `home_screen.dart`:
- Add state: `List<Folder> _folders = const []; FolderFilter _folderFilter = const FolderFilter.all();`
- In `_load()`, after loading summaries, also `_folders = await repo.listFolders();`
- Add a folder-count getter computed from `_summaries` (`folderId` on each).
- In `_buildHeader`, after the search field, add (gated):
  ```dart
  if (widget.libraryDependencies.features.folders && _folders.isNotEmpty)
    FolderFilterBar(
      folders: _folders,
      counts: _folderCounts(),
      active: _folderFilter,
      onChanged: (f) => setState(() => _folderFilter = f),
      onCreateFolder: _createFolder,
    ),
  ```
- Add `_createFolder()` (show dialog → `repo.createFolder` → `_load()`).
- Change `_displayed` to apply the folder filter:
  ```dart
  List<DocumentSummary> get _displayed {
    final base = _searching ? _searchResults : sortDocuments(_summaries, _sort);
    return base.where(_matchesFolder).toList();
  }
  bool _matchesFolder(DocumentSummary s) => switch (_folderFilter) {
    _AllFilter() => true,
    _UnfiledFilter() => s.folderId == null,
    _FolderFilter(:final id) => s.folderId == id,
  };
  ```
  (Expose the sealed subtype patterns by importing `folder_filter_bar.dart`; if the private subclasses can't be pattern-matched across files, add a public `bool matches(DocumentSummary)` method to `FolderFilter` instead and call `_folderFilter.matches(s)`.)
- Replace the two `_buildDocuments(...)` call sites in `_buildBody()` to use `_displayed` consistently.

> **Preserve existing tests:** the bar only renders when `_folders.isNotEmpty`, so home tests that seed no folders see an unchanged header.

- [ ] **Step 6: Add host BDD feature + steps**

`test/bdd/library/folder_filter.feature`:

```gherkin
Feature: Folder filtering
  Scenario: Filter documents by folder
    Given the library has a document "Invoice" in folder "Work"
    And the library has a document "Recipe" with no folder
    And the app launches reading that same storage
    When I tap the folder chip "Work"
    Then I see the document "Invoice"
    And I do not see the document "Recipe"
```

Regenerate: `dart run build_runner build --delete-conflicting-outputs`. Implement the new steps in `test/step/` (reuse existing library seed steps; add a seed step that sets a document's folder). Follow the existing seed-step pattern noted in the repo (persistent-storage seed + an explicit "the app launches reading that same storage" step — required or finders match 0 widgets).

- [ ] **Step 7: Run tests + analyze**

Run: `flutter test test/bdd/library/folder_filter_test.dart test/features/library/widgets/folder_filter_bar_test.dart test/features/library/home_screen_test.dart`
Expected: PASS (incl. the unchanged existing home tests).
Run: `flutter analyze lib/features/library`

- [ ] **Step 8: Commit**

```bash
git add lib/features/library/widgets/folder_filter_bar.dart lib/features/library/widgets/create_folder_dialog.dart lib/features/library/home_screen.dart test/features/library/widgets/folder_filter_bar_test.dart test/bdd/library/folder_filter.feature test/bdd/library/folder_filter_test.dart test/step
git commit -m "feat(library): folder filter bar + in-memory folder filtering"
```

---

## Task 10: Tag chips + tag filter sheet (UI)

**Files:**
- Create: `lib/features/library/widgets/tag_filter_sheet.dart`
- Create: `lib/features/library/widgets/tag_chips.dart`
- Modify: `lib/features/library/home_screen.dart` (active tag set; filter `_displayed`; tag-filter affordance)
- Modify: `lib/features/library/widgets/documents_list_view.dart` and `documents_grid_view.dart` (render `summary.tags` chips)
- Create: `test/features/library/widgets/tag_filter_sheet_test.dart`
- Create: `test/bdd/library/tag_filter.feature` + steps

**Interfaces:**
- Consumes: `Tag`, `FeatureFlags.tags`, repo tag methods, enriched summaries.
- Produces: `TagFilterSheet` (multi-select, AND); `TagChips` (read-only display); `HomeScreen._activeTagIds` filtering `_displayed`.

- [ ] **Step 1: Write the failing widget test** for `TagFilterSheet` (renders tag chips, toggling selection calls back with the new `Set<int>`). Structure mirrors Task 9 Step 1.

- [ ] **Step 2: Run to verify failure.** `flutter test test/features/library/widgets/tag_filter_sheet_test.dart` → FAIL.

- [ ] **Step 3: Implement `TagFilterSheet` and `TagChips`.** `TagFilterSheet` is a `StatefulWidget` bottom-sheet body holding `Set<int> _selected`, a `Wrap` of `FilterChip`s from a `List<Tag>`, and a "Done" button returning the set. `TagChips` is a stateless `Wrap` of small `Chip`s from `List<Tag>` (skip render when empty).

- [ ] **Step 4: Run widget test to pass.**

- [ ] **Step 5: Wire into `HomeScreen`.** Add `Set<int> _activeTagIds = {}` and `List<Tag> _tags = const []` (load in `_load()`). Add a filter affordance (an icon button near the search field, gated by `features.tags && _tags.isNotEmpty`) that opens `TagFilterSheet` and stores the result. Extend `_displayed`'s filter to also require `_activeTagIds.isEmpty || _activeTagIds.every((id) => s.tags.any((t) => t.id == id))`. Render `TagChips(summary.tags)` inside the list/grid card widgets (gated by `features.tags`).

- [ ] **Step 6: Add host BDD** `test/bdd/library/tag_filter.feature` (tag two documents, filter by a tag, assert visibility), regenerate, implement steps.

- [ ] **Step 7: Run tests + analyze** (`flutter test test/bdd/library/tag_filter_test.dart test/features/library/widgets/ test/features/library/documents_list_view_test.dart` and the grid/list view tests; ensure existing list/grid tests still pass — `TagChips` on empty tags renders nothing so they stay green). `flutter analyze lib/features/library`.

- [ ] **Step 8: Commit** (`feat(library): tag chips + tag filter sheet`).

---

## Task 11: Move-to-folder + manage-tags actions (per-doc menu + selection bar)

**Files:**
- Modify: `lib/features/library/widgets/documents_list_view.dart` / `documents_grid_view.dart` (menu items)
- Modify: `lib/features/library/home_screen.dart` (`_moveDocument`, `_manageTags`, bulk variants; selection-bar buttons)
- Create: `lib/features/library/widgets/move_to_folder_sheet.dart` (pick a folder or Unfiled or create new)
- Create: `lib/features/library/widgets/manage_tags_sheet.dart` (toggle tags for a document, create new tag)
- Create: `test/bdd/library/organize_actions.feature` + steps
- Create: `test/features/library/widgets/move_to_folder_sheet_test.dart`

**Interfaces:**
- Consumes: repo `moveToFolder`, `setDocumentTags`, `listFolders`, `listTags`, `createFolder`, `createTag`; `FeatureFlags.folders`/`tags`.
- Produces: per-document "Move to folder" and "Tags…" menu actions; selection-mode "Move" and "Tag" bulk actions operating on `_selectedIds ∩ _displayed`.

- [ ] **Step 1: Write the failing widget test** for `MoveToFolderSheet` (lists folders + Unfiled + create; selecting one returns the folder id or null). Mirror Task 9 Step 1.

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement `MoveToFolderSheet` and `ManageTagsSheet`** (bottom-sheet bodies; `ManageTagsSheet` seeds selection from `repo.tagsForDocument`).

- [ ] **Step 4: Run widget test → PASS.**

- [ ] **Step 5: Wire menu + selection-bar actions in `HomeScreen`.** Add menu items to the per-doc context menu (gated). Add `_moveDocument(s)`/`_manageTags(s)` (single) and `_bulkMove()`/`_bulkTag()` (over selected) that show the sheets, call the repo, then `_load()` and `_clearSelection()`. Add two `IconButton`s to `_buildSelectionBar` (gated), next to export.

- [ ] **Step 6: Add host BDD** `organize_actions.feature`: move a document to a folder from the menu → it appears under that folder; add a tag → it shows a tag chip. Regenerate + steps.

- [ ] **Step 7: Run tests + analyze.**

- [ ] **Step 8: Commit** (`feat(library): move-to-folder and manage-tags actions`).

---

## Task 12: "Suggest name" in the rename dialog (auto-title)

**Files:**
- Modify: `lib/features/library/widgets/rename_dialog.dart` (optional suggestion affordance)
- Modify: `lib/features/library/home_screen.dart` (`_renameDocument` passes a suggestion provider)
- Modify: `lib/features/library/page_viewer_screen.dart` if it also hosts rename (check; wire the same)
- Create: `test/features/library/widgets/rename_dialog_suggest_test.dart`
- Create: `test/bdd/library/suggest_title.feature` + steps

**Interfaces:**
- Consumes: `repo.suggestTitleFor` (Task 7), `FeatureFlags.smartTitles`.
- Produces: `showRenameDialog(..., {Future<String?> Function()? suggest})` — when `suggest` is provided and returns non-null, the dialog shows a "Suggest: <title>" chip that fills the field. Signature stays backward-compatible (new optional named param).

- [ ] **Step 1: Read `rename_dialog.dart`** to learn its exact current signature and structure.

- [ ] **Step 2: Write the failing widget test**

`test/features/library/widgets/rename_dialog_suggest_test.dart`: pump a host that calls `showRenameDialog(context, 'Old', suggest: () async => 'INVOICE')`; expect a tappable "INVOICE" suggestion; tapping it sets the text field to "INVOICE"; confirming returns "INVOICE". Also: when `suggest` returns null, no suggestion chip renders.

- [ ] **Step 3: Run → FAIL.**

- [ ] **Step 4: Implement** the optional `suggest` param and the chip (calls `suggest()` in `initState`/`FutureBuilder`; chip hidden while null or when `!features.smartTitles` — gate at the call site by passing `suggest: null`).

- [ ] **Step 5: Run widget test → PASS.**

- [ ] **Step 6: Wire call sites.** In `_renameDocument` (and the viewer's rename if present), pass `suggest: features.smartTitles ? () => repo.suggestTitleFor(s.document.id) : null`.

- [ ] **Step 7: Add host BDD** `suggest_title.feature`: given a document whose page has OCR text, opening rename shows a suggestion that fills the name. (Seed OCR text directly in a step.) Regenerate + steps.

- [ ] **Step 8: Run tests + analyze.**

- [ ] **Step 9: Commit** (`feat(library): suggest-name affordance in rename dialog`).

---

## Task 13: Device integration test (Android + iOS)

**Files:**
- Create: `integration_test/org_migration_device_test.dart`
- Create (if needed): `test/step/` device-shared steps

**Interfaces:**
- Consumes: production wiring (real sqlite, real ML Kit via `LibraryDependencies` defaults).

- [ ] **Step 1: Write the device test** that, on a real device: opens the production `AppDatabase` path, creates a folder + tag, moves a seeded doc, sets a tag, kills and reopens the DB, and asserts the folder/tag/membership survived (proves the v9 migration ran on real sqlite and `SET NULL`/cascade behave). If a pre-v9 fixture DB can be bundled, prefer upgrading it; otherwise assert on a freshly-created v9 DB and note the fixture gap explicitly.

- [ ] **Step 2: Run on Android**

Run: `flutter test integration_test/org_migration_device_test.dart -d RZCY51D0T1K`
Expected: PASS. Paste the green summary.

- [ ] **Step 3: Run on iOS**

Run: `flutter test integration_test/org_migration_device_test.dart -d 00008120-0016355C21E8201E`
Expected: PASS. Paste the green summary. **This is the step that proves the SQLite `ADD COLUMN … REFERENCES … ON DELETE SET NULL` migration is real on both platforms** — do not claim done until both are green (or a named, explicit gap is recorded).

- [ ] **Step 4: Commit** (`test(library): device migration + org persistence, Android+iOS`).

---

## Task 14: Full-suite gate + coverage

- [ ] **Step 1: Full host suite** — `flutter test` → all green. Fix any regression in existing home/list/grid tests caused by the new UI (should be none due to conditional rendering; if a golden/layout test trips, update it deliberately and note why).
- [ ] **Step 2: Analyze** — `flutter analyze` → zero issues.
- [ ] **Step 3: Coverage gate** — `bash scripts/coverage.sh` → holds at/above policy (~90%). Add tests for any uncovered new branch.
- [ ] **Step 4: Rebuild + install release on both devices** (per CLAUDE.md — build first, then install; verify iOS artifact is Release, not a Debug stub):
  ```bash
  flutter build apk --release && flutter install -d RZCY51D0T1K
  flutter build ios --release && flutter install -d 00008120-0016355C21E8201E
  ```
- [ ] **Step 5: Commit** any coverage top-ups (`test(library): coverage top-ups for organization`).

---

## Wave 3 — Independent verification (do NOT trust "done")

Dispatch a **separate** verifier subagent per item; each re-runs the named tests and reads the diff adversarially. None may rely on the implementer's self-report.

- **V1 — migration/data-loss:** re-run all of `test/features/library/drift/` + `schema_migration_v7_test.dart`; confirm table-creation-before-addColumn ordering, `SET NULL` on folder delete, cascade on doc delete, FTS triggers untouched, all three migration tests updated. Adversarially seed a v8 DB with rows and assert zero loss.
- **V2 — repo SQL/transaction:** read Tasks 6–7 diff; confirm no N+1 in `_summaries()`, `setDocumentTags` is transactional, `createTag` dedupe is case-insensitive, no existing method signature changed.
- **V3 — UI + flags + BDD:** confirm every entry point (folder bar, tag sheet, per-doc menu, selection bar, suggest chip) is gated by its flag; confirm conditional rendering keeps existing home/list/grid tests green; confirm `_displayed` filtering and selection-export operate on the same visible set; confirm each new `.feature` has generated tests + steps.
- **V4 — device (Android + iOS):** independently run Task 13 on both device ids; paste both green summaries; confirm the store-screenshot/seed harness still opens the v9 DB.
- **V5 — whole-suite:** independently run `flutter test`, `flutter analyze`, `bash scripts/coverage.sh`; report exact numbers.

## Spec coverage self-check

- Folders (flat, one-per-doc, SET NULL): Tasks 1, 6, 9, 11. ✓
- Tags (many-to-many, cascade): Tasks 1, 7, 10, 11. ✓
- Smart auto-titles (pure service, post-OCR, suggest-confirm): Tasks 3, 7, 12. ✓
- Additive interface / optional summary fields: Tasks 4, 5. ✓
- Client-side filtering: Tasks 9, 10. ✓
- Feature flags gating every entry point: Task 8 + gating in 9–12, verified in V3. ✓
- Three migration tests updated + device-verified migration: Tasks 1, 13, V1, V4. ✓
- Both platforms, coverage, zero-warning: Tasks 13, 14, V4, V5. ✓
