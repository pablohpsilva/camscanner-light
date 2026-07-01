# M1 — Split a document Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** "Split after this page" — move the pages after the current one into a new document.

**Architecture:** `splitAfter(docId, position)` creates a new document, copies the trailing pages verbatim (image/flat/corners/OCR) into its fresh dir (`page_<k>.jpg`, collision-free), then deletes those pages from the source (which keeps its contiguous head pages — no renumber). A viewer menu item wires it with a last-page guard.

**Tech Stack:** Flutter/Dart, drift, `bdd_widget_test` + `build_runner`.

## Global Constraints

- **iOS + Android**: pure Dart file IO + drift + Material menu/snackbar; no platform channels.
- **On-device only**: pages stay in the app's document folders.
- **Verbatim copy** into a FRESH doc dir → `page_<k>.jpg` names are collision-free; source keeps head pages 1..position (already contiguous — no renumber).
- **TDD/BDD first**; SOLID/KISS/DRY (mirror L1's copy + deletePage's best-effort file cleanup).
- **Commits**: explicit file paths (never `git add -A`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Do NOT commit report files.
- **Do NOT touch**: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, `.superpowers/`.
- **On-device gate**: BDD + integration tests pass on Samsung `RZCY51D0T1K`.
- Paths relative to `apps/mobile/` unless noted (`scripts/`, `docs/` are repo-root).

---

### Task 1: `splitAfter` repository method

**Files:**
- Modify: `lib/features/library/document_repository.dart` (interface)
- Modify: `lib/features/library/drift/drift_document_repository.dart` (impl)
- Modify: `test/support/fake_library.dart` (fake)
- Test: `test/features/library/split_document_test.dart` (create)

**Interfaces:**
- Consumes: `_fileStore`, `_clock`, drift pages/documents, `Document`, `DocumentSaveException`.
- Produces: `Future<Document> splitAfter(int documentId, int position)`.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/split_document_test.dart`:

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
    base = await Directory.systemTemp.createTemp('m1split');
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

  Uint8List jpeg() =>
      Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));

  // Creates a document with [pageCount] pages; the LAST page optionally gets a
  // flat + OCR so we can prove they are carried across a split.
  Future<int> seedDoc(int pageCount, {bool lastHasFlatOcr = false}) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
    for (var pos = 1; pos <= pageCount; pos++) {
      final rel = 'documents/$id/page_$pos.jpg';
      await store.writeRelative(rel, jpeg());
      String? flatRel;
      String? ocrText;
      String? ocrBoxes;
      if (pos == pageCount && lastHasFlatOcr) {
        flatRel = store.flatForImage(rel);
        await store.writeRelative(flatRel, jpeg());
        ocrText = 'TAIL';
        ocrBoxes = const OcrResult(text: 'TAIL', words: [
          OcrWordBox(text: 'TAIL', left: 0.1, top: 0.1, right: 0.2, bottom: 0.2)
        ]).encodeBoxes();
      }
      await db.into(db.pages).insert(PagesCompanion.insert(
            documentId: id,
            position: pos,
            relativeImagePath: rel,
            flatRelativePath: Value(flatRel),
            ocrText: Value(ocrText),
            ocrBoxes: Value(ocrBoxes),
          ));
    }
    return id;
  }

  test('moves trailing pages into a new document; source keeps the head',
      () async {
    final id = await seedDoc(3, lastHasFlatOcr: true);
    final created = await repo.splitAfter(id, 1);

    // Source keeps only page 1.
    final srcPages = await repo.getDocumentPages(id);
    expect(srcPages.length, 1);
    expect(srcPages.single.position, 1);

    // New document has the former pages 2 and 3, renumbered 1 and 2.
    expect(created.name, endsWith('(split)'));
    final newPages = await repo.getDocumentPages(created.id);
    expect(newPages.length, 2);
    expect(newPages.map((p) => p.position), [1, 2]);
    for (final p in newPages) {
      expect(File(p.imagePath).existsSync(), isTrue);
    }
    // The former last page (now position 2) kept its flat + OCR.
    final tail = newPages[1];
    expect(tail.flatImagePath, isNotNull);
    expect(File(tail.flatImagePath!).existsSync(), isTrue);
    expect(tail.ocrText, 'TAIL');
    expect(tail.ocrWords, isNotEmpty);
  });

  test('splitting after the last page throws', () async {
    final id = await seedDoc(2);
    expect(() => repo.splitAfter(id, 2), throwsA(isA<DocumentSaveException>()));
  });

  test('splitting after position 0 throws', () async {
    final id = await seedDoc(2);
    expect(() => repo.splitAfter(id, 0), throwsA(isA<DocumentSaveException>()));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/split_document_test.dart`
Expected: FAIL — `splitAfter` not defined.

- [ ] **Step 3: Add the interface method**

In `lib/features/library/document_repository.dart`, near `mergeInto`:

```dart
  /// Splits [documentId] after [position]: the pages after [position] are moved
  /// (image, flat, corners, OCR copied verbatim) into a NEW document named
  /// "<name> (split)", and removed from the source (which keeps pages
  /// 1..[position]). Returns the new document. Nothing leaves the device. Throws
  /// [DocumentSaveException] when [position] is < 1, is the last page (nothing to
  /// split off), or on any IO/DB failure.
  Future<Document> splitAfter(int documentId, int position);
```

- [ ] **Step 4: Implement in the Drift repository**

Add to `drift_document_repository.dart` (near `mergeInto`):

```dart
  @override
  Future<Document> splitAfter(int documentId, int position) async {
    try {
      final pages = await (_db.select(_db.pages)
            ..where((p) => p.documentId.equals(documentId))
            ..orderBy([(p) => OrderingTerm.asc(p.position)]))
          .get();
      if (pages.isEmpty) {
        throw DocumentSaveException('splitAfter: no pages ($documentId)');
      }
      final maxPos = pages.last.position;
      if (position < 1 || position >= maxPos) {
        throw DocumentSaveException(
            'splitAfter: nothing after position $position');
      }
      final doc = await (_db.select(_db.documents)
            ..where((d) => d.id.equals(documentId)))
          .getSingleOrNull();
      if (doc == null) {
        throw DocumentSaveException('splitAfter: no document $documentId');
      }
      final now = _clock().toUtc();
      final newName = '${doc.name} (split)';
      final newId = await _db.into(_db.documents).insert(
          DocumentsCompanion.insert(
              name: newName, createdAt: now, modifiedAt: now));

      final moved = pages.where((p) => p.position > position).toList();
      var k = 0;
      for (final src in moved) {
        k++;
        final imageRel = 'documents/$newId/page_$k.jpg';
        final bytes =
            await _fileStore.absoluteFor(src.relativeImagePath).readAsBytes();
        await _fileStore.writeRelative(imageRel, bytes);
        String? flatRel;
        if (src.flatRelativePath != null) {
          final flatBytes =
              await _fileStore.absoluteFor(src.flatRelativePath!).readAsBytes();
          flatRel = _fileStore.flatForImage(imageRel);
          await _fileStore.writeRelative(flatRel, flatBytes);
        }
        await _db.into(_db.pages).insert(PagesCompanion.insert(
          documentId: newId,
          position: k,
          relativeImagePath: imageRel,
          corners: Value(src.corners),
          flatRelativePath: Value(flatRel),
          ocrText: Value(src.ocrText),
          ocrBoxes: Value(src.ocrBoxes),
        ));
      }

      await _db.transaction(() async {
        for (final src in moved) {
          await (_db.delete(_db.pages)..where((t) => t.id.equals(src.id))).go();
        }
        await (_db.update(_db.documents)
              ..where((d) => d.id.equals(documentId)))
            .write(DocumentsCompanion(modifiedAt: Value(now)));
      });

      // Best-effort cleanup of the moved pages' source files (after commit).
      for (final src in moved) {
        try {
          await _fileStore.absoluteFor(src.relativeImagePath).delete();
        } on FileSystemException {/* already gone */}
        final f = src.flatRelativePath;
        if (f != null) {
          try {
            await _fileStore.absoluteFor(f).delete();
          } on FileSystemException {/* already gone */}
        }
      }

      return Document(
          id: newId, name: newName, createdAt: now, modifiedAt: now);
    } catch (e) {
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('splitAfter failed: $e');
    }
  }
```

> `Document` is the domain type (imported via `../document.dart`; the file imports `app_database.dart` with `hide Document`). `_db`, `_fileStore`, `_clock`, `PagesCompanion`, `DocumentsCompanion`, `Value`, `OrderingTerm`, `FileSystemException` (dart:io) are all already available.

- [ ] **Step 5: Implement in the fake repository**

In `test/support/fake_library.dart`, add to `FakeDocumentRepository`:

```dart
  int? lastSplitDoc;
  int? lastSplitPosition;

  @override
  Future<Document> splitAfter(int documentId, int position) async {
    if (throwOnUpdate) {
      throw const DocumentSaveException('fake: split failed');
    }
    lastSplitDoc = documentId;
    lastSplitPosition = position;
    return Document(
      id: 999,
      name: 'Split',
      createdAt: DateTime.utc(2026, 7, 1),
      modifiedAt: DateTime.utc(2026, 7, 1),
    );
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/split_document_test.dart`
Expected: PASS (3/3).

- [ ] **Step 7: Library group + analyze**

Run (set the DARTCV env if a test errors on `libdartcv`: `bash /Users/pablohpsilva/Documents/camscanner-light/scripts/setup-cv-host-test.sh` then export `DARTCV_LIB_PATH=/tmp/dartcv_lib/lib/libdartcv.dylib` + `DYLD_LIBRARY_PATH=/tmp/dartcv_lib/lib`):
`cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/document_repository.dart apps/mobile/lib/features/library/drift/drift_document_repository.dart apps/mobile/test/support/fake_library.dart apps/mobile/test/features/library/split_document_test.dart
git commit -m "feat(m1): splitAfter — move trailing pages into a new document"
```

---

### Task 2: Page-viewer "Split after this page" action

**Files:**
- Modify: `lib/features/library/page_viewer_screen.dart`
- Test: `test/features/library/page_viewer_split_test.dart` (create)

**Interfaces:**
- Consumes: `DocumentRepository.splitAfter`, the existing `page-viewer-page-menu`.
- Produces: `page-viewer-split` menu item + `_splitAfter()`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/library/page_viewer_split_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Future<void> openMenuAndSplit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-split')));
    await tester.pumpAndSettle();
  }

  testWidgets('Split after this page splits when not on the last page',
      (tester) async {
    final repo = FakeDocumentRepository(pages: const [
      PageImage(position: 1, imagePath: '/a.jpg'),
      PageImage(position: 2, imagePath: '/b.jpg'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 7, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await openMenuAndSplit(tester);

    expect(repo.lastSplitDoc, 7);
    expect(repo.lastSplitPosition, 1);
    expect(find.text('Split into a new document'), findsOneWidget);
  });

  testWidgets('Split on the only (last) page shows a message and does not split',
      (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 7, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await openMenuAndSplit(tester);

    expect(repo.lastSplitDoc, isNull);
    expect(find.textContaining('last page'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_split_test.dart`
Expected: FAIL — no `page-viewer-split` item.

- [ ] **Step 3: Add the handler**

In `lib/features/library/page_viewer_screen.dart`, add a method near `_mergeAnother`:

```dart
  Future<void> _splitAfter() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    if (_current >= pages.length - 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('This is the last page — nothing to split after.')),
      );
      return;
    }
    final page = pages[_current];
    try {
      await widget.repository.splitAfter(widget.documentId, page.position);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split into a new document')),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't split")),
      );
    }
  }
```

- [ ] **Step 4: Add the menu item**

In the `PopupMenuButton`'s `onSelected`, add:

```dart
              if (v == 'split') unawaited(_splitAfter());
```

In `itemBuilder`'s list, add after the `merge` item:

```dart
              PopupMenuItem<String>(
                value: 'split',
                key: Key('page-viewer-split'),
                child: Text('Split after this page'),
              ),
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_split_test.dart`
Expected: PASS (2/2).

- [ ] **Step 6: Library group + analyze**

Run (with the DARTCV env if needed): `cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/test/features/library/page_viewer_split_test.dart
git commit -m "feat(m1): page viewer 'Split after this page' with last-page guard"
```

---

### Task 3: BDD, on-device test, verify script, plans index

**Files:**
- Create: `integration_test/m1_split_document.feature`
- Create step defs: `test/step/i_split_after_the_first_page.dart`, `test/step/i_see_the_split_confirmation.dart`
- Generate: `integration_test/m1_split_document_test.dart` (build_runner; committed)
- Create: `integration_test/m1_split_document_device_test.dart` (deterministic Drift split on device)
- Create: `scripts/verify/m1.sh` (repo root)
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Write the `.feature`** (two captures in one scan, then split)

Create `integration_test/m1_split_document.feature`:

```gherkin
Feature: Split a document

  Scenario: Split after the first page
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I capture and accept the second page
    And I tap Done
    And I open the first document
    And I split after the first page
    Then I see the split confirmation
```

- [ ] **Step 2: Write the new step definitions**

Create `test/step/i_split_after_the_first_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I split after the first page
Future<void> iSplitAfterTheFirstPage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-split')));
  await tester.pumpAndSettle();
}
```

Create `test/step/i_see_the_split_confirmation.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the split confirmation
Future<void> iSeeTheSplitConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Split into a new document'), findsOneWidget);
}
```

> `the app is launched…`, `I tap the Scan button`, `I capture and accept the first page`, `I capture and accept the second page`, `I tap Done`, `I open the first document` already exist — reuse. Verify the generated step-function names match the generator's derivation; rename to match if needed.
> **Implementer note:** the open camera stays after the first accepted page (its `_activeDocId` is set), so the second capture+accept appends a page to the same document — after `I tap Done` the document has two pages, so "split after the first page" has something to split off.

- [ ] **Step 3: Generate the BDD test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `integration_test/m1_split_document_test.dart` generated, importing the new steps + reused ones. If build_runner rewrote unrelated generated files, `git checkout` them so the commit stays scoped to M1.

- [ ] **Step 4: Write the deterministic on-device test**

Create `integration_test/m1_split_document_device_test.dart`:

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

  testWidgets('splitAfter moves trailing pages to a new document on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('m1dev');
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
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Doc', createdAt: now, modifiedAt: now));
    for (var p = 1; p <= 3; p++) {
      final rel = 'documents/$id/page_$p.jpg';
      await store.writeRelative(rel, jpeg);
      await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id, position: p, relativeImagePath: rel));
    }

    final created = await repo.splitAfter(id, 1);
    expect((await repo.getDocumentPages(id)).length, 1);
    expect((await repo.getDocumentPages(created.id)).length, 2);

    await db.close();
    await base.delete(recursive: true);
  });
}
```

- [ ] **Step 5: Write the verify script**

Create `scripts/verify/m1.sh` (repo root), mirroring `scripts/verify/o1.sh`:

```bash
#!/usr/bin/env bash
# Verify M1 (split a document) acceptance criteria.
# Run from repository root: bash scripts/verify/m1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== M1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "splitAfter on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "splitAfter"

assert_file_has "splitAfter in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "splitAfter"

assert_file_has "page viewer wires Split" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-split"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/m1_split_document.feature" \
  "Split a document"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/m1_split_document_test.dart" \
  "split"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device M1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device split test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/m1_split_document_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/m1_split_document_test.dart"
fi

echo "== M1 verification complete =="
```

Make it executable: `chmod +x scripts/verify/m1.sh`.

- [ ] **Step 6: Host verify + analyze**

Run: `cd apps/mobile && flutter test && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 7: Update the plans index**

In `docs/superpowers/plans/00-plans-index.md`, add after the L1 row:

```markdown
| M1 | Split a document | 09 | `2026-07-01-m1-split-document.md` | ✅ **built & gated** |
```

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/integration_test/m1_split_document.feature apps/mobile/integration_test/m1_split_document_test.dart apps/mobile/integration_test/m1_split_document_device_test.dart apps/mobile/test/step/i_split_after_the_first_page.dart apps/mobile/test/step/i_see_the_split_confirmation.dart scripts/verify/m1.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(m1): BDD + on-device split tests, verify script, index"
```

---

## Self-Review

- **Spec coverage:** repo splitAfter (Task 1), viewer action + last-page guard (Task 2), BDD + device + verify + index (Task 3). ✅
- **Collision-free:** fresh new-doc dir → `page_<k>.jpg` unique; source keeps contiguous head pages (no renumber). ✅
- **Verbatim copy:** image + flat + corners + ocrText + ocrBoxes copied; alignment preserved. ✅
- **Placeholder scan:** complete code in every step; last-page widget test uses a 1-page doc (no PageView nav needed). ✅
- **Type consistency:** `splitAfter(int,int) → Future<Document>` identical across interface/Drift/fake; viewer key `page-viewer-split` consistent with tests. ✅
- **Out of scope kept out:** no split-at-arbitrary-range UI, no multi-select. ✅
