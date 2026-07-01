# L1 — Merge documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Merge another document's pages into the currently-open document (in order), then delete the source.

**Architecture:** `mergeInto(targetId, sourceId)` copies each source page's image/flat/corners/OCR verbatim into the target dir under collision-free names (`page_m<sourceId>_<sourcePos>.jpg`), inserts target rows at continuing positions, bumps modifiedAt, then reuses `deleteDocument(sourceId)`. A viewer menu item opens a picker dialog of the other documents.

**Tech Stack:** Flutter/Dart, drift, `bdd_widget_test` + `build_runner`.

## Global Constraints

- **iOS + Android**: pure Dart file IO + drift + a Material dialog; no platform channels.
- **On-device only**: pages stay in the app's document folders.
- **Collision-free naming**: merged files are named from `<sourceId>_<sourcePos>` (NOT target position) — a leftover file from a deleted page must never be overwritten. Nothing parses page filenames (order is the position column).
- **Copy verbatim**: image + flat + corners + `ocrText` + `ocrBoxes` copied as-is (no re-encode, no re-OCR) — preserves orientation and text-layer alignment.
- **TDD/BDD first**; SOLID/KISS/DRY (reuse `deleteDocument`, `flatForImage`, `listDocumentSummaries`).
- **Commits**: explicit file paths (never `git add -A`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Do NOT commit report files.
- **Do NOT touch**: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, `.superpowers/`.
- **On-device gate**: BDD + integration tests pass on Samsung `RZCY51D0T1K`.
- Paths relative to `apps/mobile/` unless noted (`scripts/`, `docs/` are repo-root).

---

### Task 1: `mergeInto` repository method

**Files:**
- Modify: `lib/features/library/document_repository.dart` (interface)
- Modify: `lib/features/library/drift/drift_document_repository.dart` (impl)
- Modify: `test/support/fake_library.dart` (fake)
- Test: `test/features/library/merge_documents_test.dart` (create)

**Interfaces:**
- Consumes: `_fileStore` (`absoluteFor`, `writeRelative`, `flatForImage`), `deleteDocument`, `_clock`, drift pages/documents.
- Produces: `Future<void> mergeInto(int targetDocumentId, int sourceDocumentId)`.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/merge_documents_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('l1merge');
    db = AppDatabase(NativeDatabase.memory());
    store = DocumentFileStore(base);
    repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );
  });

  tearDown(() async {
    await db.close();
    if (await base.exists()) await base.delete(recursive: true);
  });

  Uint8List _jpeg() =>
      Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));

  // Creates a document with [pageCount] pages; page 1 optionally gets a flat + boxes.
  Future<int> seedDoc(String name, int pageCount,
      {bool firstHasFlat = false, String? firstOcrText}) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: name, createdAt: now, modifiedAt: now));
    for (var pos = 1; pos <= pageCount; pos++) {
      final rel = 'documents/$id/page_$pos.jpg';
      await store.writeRelative(rel, _jpeg());
      String? flatRel;
      if (pos == 1 && firstHasFlat) {
        flatRel = store.flatForImage(rel);
        await store.writeRelative(flatRel, _jpeg());
      }
      await db.into(db.pages).insert(PagesCompanion.insert(
            documentId: id,
            position: pos,
            relativeImagePath: rel,
            flatRelativePath: Value(flatRel),
            ocrText: Value(pos == 1 ? firstOcrText : null),
            ocrBoxes: Value(pos == 1 && firstOcrText != null
                ? const OcrResult(text: 'x', words: [
                    OcrWordBox(text: 'x', left: 0.1, top: 0.1, right: 0.2, bottom: 0.2)
                  ]).encodeBoxes()
                : null),
          ));
    }
    return id;
  }

  test('appends source pages to target in order and deletes the source',
      () async {
    final target = await seedDoc('Target', 2);
    final source =
        await seedDoc('Source', 2, firstHasFlat: true, firstOcrText: 'HELLO');

    await repo.mergeInto(target, source);

    final pages = await repo.getDocumentPages(target);
    expect(pages.length, 4);
    expect(pages.map((p) => p.position), [1, 2, 3, 4]);
    // The merged first source page (now position 3) kept its flat + OCR.
    final merged = pages[2];
    expect(merged.flatImagePath, isNotNull);
    expect(File(merged.flatImagePath!).existsSync(), isTrue);
    expect(merged.ocrText, 'HELLO');
    expect(merged.ocrWords, isNotEmpty);
    expect(File(merged.imagePath).existsSync(), isTrue);
    expect(merged.imagePath, contains('page_m${source}_1.jpg'));

    // Source is gone (rows + dir).
    expect(await repo.getDocumentPages(source), isEmpty);
    expect(Directory('${base.path}/documents/$source').existsSync(), isFalse);
  });

  test('merging a source page without a flat leaves flatImagePath null',
      () async {
    final target = await seedDoc('T', 1);
    final source = await seedDoc('S', 1); // no flat
    await repo.mergeInto(target, source);
    final pages = await repo.getDocumentPages(target);
    expect(pages.length, 2);
    expect(pages[1].flatImagePath, isNull);
  });

  test('rejects merging a document into itself', () async {
    final id = await seedDoc('Self', 1);
    expect(() => repo.mergeInto(id, id), throwsA(isA<DocumentSaveException>()));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/merge_documents_test.dart`
Expected: FAIL — `mergeInto` not defined.

- [ ] **Step 3: Add the interface method**

In `lib/features/library/document_repository.dart`, near `deleteDocument`:

```dart
  /// Appends every page of [sourceDocumentId] (in position order) to
  /// [targetDocumentId] — copying each page's image, flat derivative, corners,
  /// and cached OCR text/boxes verbatim — then deletes the source document.
  /// Merged files are named from the source id so they never collide with the
  /// target's existing files. Nothing leaves the device. Throws
  /// [DocumentSaveException] when target == source or on any IO/DB failure.
  Future<void> mergeInto(int targetDocumentId, int sourceDocumentId);
```

- [ ] **Step 4: Implement in the Drift repository**

Add to `drift_document_repository.dart` (near `deleteDocument`):

```dart
  @override
  Future<void> mergeInto(int targetDocumentId, int sourceDocumentId) async {
    if (targetDocumentId == sourceDocumentId) {
      throw const DocumentSaveException('mergeInto: target == source');
    }
    try {
      final maxRow = await (_db.select(_db.pages)
            ..where((p) => p.documentId.equals(targetDocumentId))
            ..orderBy([(p) => OrderingTerm.desc(p.position)])
            ..limit(1))
          .getSingleOrNull();
      final targetMax = maxRow?.position ?? 0;
      final sourcePages = await (_db.select(_db.pages)
            ..where((p) => p.documentId.equals(sourceDocumentId))
            ..orderBy([(p) => OrderingTerm.asc(p.position)]))
          .get();

      // Copy files first (outside the DB txn), building the row inserts.
      final inserts = <PagesCompanion>[];
      var k = 0;
      for (final src in sourcePages) {
        k++;
        final imageRel =
            'documents/$targetDocumentId/page_m${sourceDocumentId}_${src.position}.jpg';
        final srcBytes =
            await _fileStore.absoluteFor(src.relativeImagePath).readAsBytes();
        await _fileStore.writeRelative(imageRel, srcBytes);
        String? flatRel;
        if (src.flatRelativePath != null) {
          final flatBytes =
              await _fileStore.absoluteFor(src.flatRelativePath!).readAsBytes();
          flatRel = _fileStore.flatForImage(imageRel);
          await _fileStore.writeRelative(flatRel, flatBytes);
        }
        inserts.add(PagesCompanion.insert(
          documentId: targetDocumentId,
          position: targetMax + k,
          relativeImagePath: imageRel,
          corners: Value(src.corners),
          flatRelativePath: Value(flatRel),
          ocrText: Value(src.ocrText),
          ocrBoxes: Value(src.ocrBoxes),
        ));
      }
      await _db.transaction(() async {
        for (final c in inserts) {
          await _db.into(_db.pages).insert(c);
        }
      });
      await (_db.update(_db.documents)
            ..where((d) => d.id.equals(targetDocumentId)))
          .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
    } catch (e) {
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('mergeInto failed: $e');
    }
    // Remove the now-copied source (rows + dir). Separate from the txn above.
    await deleteDocument(sourceDocumentId);
  }
```

> `_db`, `_fileStore`, `_clock`, `deleteDocument`, `PagesCompanion`, `DocumentsCompanion`, `Value`, `OrderingTerm` are all already available in this file. `src.corners`/`src.ocrText`/`src.ocrBoxes` are the stored nullable strings — copied verbatim.

- [ ] **Step 5: Implement in the fake repository**

In `test/support/fake_library.dart`, add to `FakeDocumentRepository`:

```dart
  int? lastMergeTarget;
  int? lastMergeSource;

  @override
  Future<void> mergeInto(int targetDocumentId, int sourceDocumentId) async {
    if (throwOnUpdate) {
      throw const DocumentSaveException('fake: merge failed');
    }
    lastMergeTarget = targetDocumentId;
    lastMergeSource = sourceDocumentId;
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/merge_documents_test.dart`
Expected: PASS (3/3).

- [ ] **Step 7: Library group + analyze**

Run (set the DARTCV env if a test errors on `libdartcv`: `bash /Users/pablohpsilva/Documents/camscanner-light/scripts/setup-cv-host-test.sh` then export `DARTCV_LIB_PATH=/tmp/dartcv_lib/lib/libdartcv.dylib` + `DYLD_LIBRARY_PATH=/tmp/dartcv_lib/lib`):
`cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/document_repository.dart apps/mobile/lib/features/library/drift/drift_document_repository.dart apps/mobile/test/support/fake_library.dart apps/mobile/test/features/library/merge_documents_test.dart
git commit -m "feat(l1): mergeInto — append another document's pages and delete source"
```

---

### Task 2: Merge picker dialog + page-viewer wiring

**Files:**
- Create: `lib/features/library/merge_picker_dialog.dart`
- Modify: `lib/features/library/page_viewer_screen.dart`
- Test: `test/features/library/page_viewer_merge_test.dart` (create)

**Interfaces:**
- Consumes: `DocumentRepository` (`listDocumentSummaries`, `mergeInto`), `DocumentSummary`, the existing `page-viewer-page-menu`.
- Produces: `showMergePicker(context, repository, currentDocumentId) → Future<int?>`, and a `page-viewer-merge` menu item.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/library/page_viewer_merge_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Document _doc(int id, String name) => Document(
      id: id,
      name: name,
      createdAt: DateTime.utc(2026, 7, 1),
      modifiedAt: DateTime.utc(2026, 7, 1));

  testWidgets('Merge lists other documents and merges the chosen one',
      (tester) async {
    final repo = FakeDocumentRepository(
      documents: [_doc(1, 'Alpha'), _doc(2, 'Beta')],
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Alpha', repository: repo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-merge')));
    await tester.pumpAndSettle();

    // Dialog shows the OTHER document, not the current one.
    expect(find.byKey(const Key('merge-picker-dialog')), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);

    await tester.tap(find.byKey(const Key('merge-picker-item-2')));
    await tester.pumpAndSettle();

    expect(repo.lastMergeTarget, 1);
    expect(repo.lastMergeSource, 2);
  });

  testWidgets('Merge shows an empty message when there are no other documents',
      (tester) async {
    final repo = FakeDocumentRepository(
      documents: [_doc(1, 'Only')],
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Only', repository: repo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-merge')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('merge-picker-empty')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_merge_test.dart`
Expected: FAIL — no `page-viewer-merge` item.

- [ ] **Step 3: Create the picker dialog**

Create `lib/features/library/merge_picker_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import 'document_repository.dart';
import 'document_summary.dart';

/// Shows a dialog listing every document EXCEPT [currentDocumentId] and resolves
/// to the chosen document's id (or null if cancelled / none available).
Future<int?> showMergePicker(
    BuildContext context, DocumentRepository repository, int currentDocumentId) {
  return showDialog<int>(
    context: context,
    builder: (_) => MergePickerDialog(
        repository: repository, currentDocumentId: currentDocumentId),
  );
}

class MergePickerDialog extends StatefulWidget {
  final DocumentRepository repository;
  final int currentDocumentId;
  const MergePickerDialog({
    super.key,
    required this.repository,
    required this.currentDocumentId,
  });

  @override
  State<MergePickerDialog> createState() => _MergePickerDialogState();
}

class _MergePickerDialogState extends State<MergePickerDialog> {
  List<DocumentSummary>? _others;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.repository.listDocumentSummaries();
      if (!mounted) return;
      setState(() => _others = all
          .where((s) => s.document.id != widget.currentDocumentId)
          .toList());
    } catch (_) {
      if (mounted) setState(() => _others = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final others = _others;
    return AlertDialog(
      key: const Key('merge-picker-dialog'),
      title: const Text('Merge another document'),
      content: SizedBox(
        width: double.maxFinite,
        child: others == null
            ? const SizedBox(
                height: 64,
                child: Center(child: CircularProgressIndicator()))
            : others.isEmpty
                ? const Padding(
                    key: Key('merge-picker-empty'),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No other documents to merge.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in others)
                        ListTile(
                          key: Key('merge-picker-item-${s.document.id}'),
                          title: Text(s.document.name),
                          subtitle: Text(s.pageCount == 1
                              ? '1 page'
                              : '${s.pageCount} pages'),
                          onTap: () =>
                              Navigator.of(context).pop(s.document.id),
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          key: const Key('merge-picker-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Wire the viewer**

In `lib/features/library/page_viewer_screen.dart`, add the import:

```dart
import 'merge_picker_dialog.dart';
```

Add a handler near `_editCrop`:

```dart
  Future<void> _mergeAnother() async {
    final sourceId =
        await showMergePicker(context, widget.repository, widget.documentId);
    if (sourceId == null || !mounted) return;
    try {
      await widget.repository.mergeInto(widget.documentId, sourceId);
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't merge")),
      );
    }
  }
```

In the `PopupMenuButton`'s `onSelected`, add:

```dart
              if (v == 'merge') unawaited(_mergeAnother());
```

In `itemBuilder`'s list, add after the `rotate` item:

```dart
              PopupMenuItem<String>(
                value: 'merge',
                key: Key('page-viewer-merge'),
                child: Text('Merge another document…'),
              ),
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_merge_test.dart`
Expected: PASS (2/2).

- [ ] **Step 6: Library group + analyze**

Run (with the DARTCV env if needed): `cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/merge_picker_dialog.dart apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/test/features/library/page_viewer_merge_test.dart
git commit -m "feat(l1): merge picker dialog + page viewer 'Merge another document'"
```

---

### Task 3: BDD, on-device test, verify script, plans index

**Files:**
- Create: `integration_test/l1_merge_documents.feature`
- Create step defs: `test/step/i_merge_the_other_document.dart`, `test/step/i_see_two_page_thumbnails.dart`
- Generate: `integration_test/l1_merge_documents_test.dart` (build_runner; committed)
- Create: `integration_test/l1_merge_documents_device_test.dart` (deterministic Drift merge on device)
- Create: `scripts/verify/l1.sh` (repo root)
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Write the `.feature`** (two real scans, then merge)

Create `integration_test/l1_merge_documents.feature`:

```gherkin
Feature: Merge documents

  Scenario: Merge another document into the open one
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I merge the other document
    Then I see two page thumbnails
```

> The two scans each create a separate one-page document. "I open the first document" opens the newest (`document-tile-1`); "I merge the other document" merges the other one into it, yielding two pages.

- [ ] **Step 2: Write the new step definitions**

Create `test/step/i_merge_the_other_document.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I merge the other document
Future<void> iMergeTheOtherDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-merge')));
  await tester.pumpAndSettle();
  // Pick the first document in the merge picker (the other document).
  await tester.tap(find.byWidgetPredicate((w) =>
      w is ListTile && w.key.toString().contains('merge-picker-item-')));
  await tester.pumpAndSettle();
}
```

Create `test/step/i_see_two_page_thumbnails.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see two page thumbnails
Future<void> iSeeTwoPageThumbnails(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // The thumbnail strip renders one keyed thumbnail per page (index-based).
  // Two thumbnails ⇒ the merge produced a 2-page document. (This mirrors the
  // proven `i_see_the_page_thumbnail_strip` step's keys.)
  expect(find.byKey(const Key('page-thumbnail-strip')), findsOneWidget);
  expect(find.byKey(const Key('page-thumb-0')), findsOneWidget);
  expect(find.byKey(const Key('page-thumb-1')), findsOneWidget);
}
```

> `the app is launched…`, `I tap the Scan button`, `I capture and accept the first page`, `I tap Done`, `I open the first document` already exist — reuse. Verify the generated step-function names match the generator's derivation; rename to match if needed.
> **Implementer note:** the thumbnail strip keys each thumbnail `page-thumb-<index>` (0-based) and renders ALL of them (proven by the existing `i_see_the_page_thumbnail_strip` step asserting `page-thumb-0`+`page-thumb-1`). Do NOT assert `page-viewer-page-2` — the `PageView.builder` builds pages lazily, so the off-screen second page may not be in the tree. The thumbnail-count assertion is the reliable proof of a 2-page merge result.

- [ ] **Step 3: Generate the BDD test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `integration_test/l1_merge_documents_test.dart` generated, importing the new steps + reused ones. If build_runner rewrote unrelated generated files, `git checkout` them so the commit stays scoped to L1.

- [ ] **Step 4: Write the deterministic on-device test**

Create `integration_test/l1_merge_documents_device_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mergeInto appends pages and deletes source on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('l1dev');
    final db = AppDatabase(NativeDatabase.memory());
    final store = DocumentFileStore(base);
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );

    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));
    Future<int> mk(String name, int pages) async {
      final now = DateTime.now();
      final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
          name: name, createdAt: now, modifiedAt: now));
      for (var p = 1; p <= pages; p++) {
        final rel = 'documents/$id/page_$p.jpg';
        await store.writeRelative(rel, jpeg);
        await db.into(db.pages).insert(PagesCompanion.insert(
            documentId: id, position: p, relativeImagePath: rel));
      }
      return id;
    }

    final target = await mk('T', 2);
    final source = await mk('S', 1);
    await repo.mergeInto(target, source);

    expect((await repo.getDocumentPages(target)).length, 3);
    expect((await repo.getDocumentPages(source)), isEmpty);

    await db.close();
    await base.delete(recursive: true);
  });
}
```

- [ ] **Step 5: Write the verify script**

Create `scripts/verify/l1.sh` (repo root), mirroring `scripts/verify/o1.sh`:

```bash
#!/usr/bin/env bash
# Verify L1 (merge documents) acceptance criteria.
# Run from repository root: bash scripts/verify/l1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== L1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "mergeInto on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "mergeInto"

assert_file_has "mergeInto in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "mergeInto"

assert_file_has "merge picker dialog exists" \
  "apps/mobile/lib/features/library/merge_picker_dialog.dart" \
  "MergePickerDialog"

assert_file_has "page viewer wires Merge" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-merge"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/l1_merge_documents.feature" \
  "Merge documents"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/l1_merge_documents_test.dart" \
  "merge"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device L1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device merge test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/l1_merge_documents_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/l1_merge_documents_test.dart"
fi

echo "== L1 verification complete =="
```

Make it executable: `chmod +x scripts/verify/l1.sh`.

- [ ] **Step 6: Host verify + analyze**

Run: `cd apps/mobile && flutter test && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 7: Update the plans index**

In `docs/superpowers/plans/00-plans-index.md`, add after the K1 row:

```markdown
| L1 | Merge documents | 09 | `2026-07-01-l1-merge-documents.md` | ✅ **built & gated** |
```

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/integration_test/l1_merge_documents.feature apps/mobile/integration_test/l1_merge_documents_test.dart apps/mobile/integration_test/l1_merge_documents_device_test.dart apps/mobile/test/step/i_merge_the_other_document.dart apps/mobile/test/step/i_see_two_page_thumbnails.dart scripts/verify/l1.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(l1): BDD + on-device merge tests, verify script, index"
```

---

## Self-Review

- **Spec coverage:** repo mergeInto copy+delete (Task 1), picker dialog + viewer wiring (Task 2), BDD + device + verify + index (Task 3). ✅
- **Collision-free naming:** merged files use `page_m<sourceId>_<sourcePos>.jpg` — unique in the target dir. ✅
- **Verbatim copy:** image + flat + corners + ocrText + ocrBoxes copied; no re-encode/re-OCR → alignment preserved. ✅
- **Placeholder scan:** complete code in every step; the one BDD assertion nuance (PageView lazy build) is flagged with a concrete fallback. ✅
- **Type consistency:** `mergeInto(int,int) → Future<void>` identical across interface/Drift/fake; picker keys consistent between dialog + tests. ✅
- **Out of scope kept out:** no multi-select, no split, no external-PDF import. ✅
