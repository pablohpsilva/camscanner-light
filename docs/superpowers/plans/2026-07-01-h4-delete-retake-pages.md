# H4 Delete / Retake Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From `PageViewerScreen`, delete the current page (with confirm; deleting the only page deletes the document) or retake it (re-capture replaces it in place).

**Architecture:** Two new repository methods (`deletePage`, `replacePage`) on `DocumentRepository`, implemented in Drift (delete renumbers survivors contiguously; replace overwrites row + files in place) and in `FakeDocumentRepository`. `CameraScreen` gains an optional single-capture `onCapture` callback so retake reuses the whole capture→review→crop→enhance pipeline. `PageViewerScreen` gains an app-bar overflow menu with "Retake page" / "Delete page" acting on the current `PageView` page.

**Tech Stack:** Flutter (Material `PopupMenuButton`, `AlertDialog`), Drift (SQLite), `bdd_widget_test` + `build_runner`. All UI is Material — identical on iOS and Android.

## Global Constraints

- Material widgets only; no platform-specific (iOS/Android) branching. Every decision works on both.
- Host tests run from repo root: `pnpm nx run mobile:test --skip-nx-cache`; success marker is `All tests passed!`.
- `flutter analyze --no-fatal-infos` (from `apps/mobile`) must print `No issues found`.
- Pages are addressed by their stored `relativeImagePath` / `flatRelativePath` columns — never derive a file path from `position` at read time; renumbering positions is a column-only update (no file moves).
- File cleanup is best-effort and happens AFTER the DB commit; the DB is authoritative (worst case = harmless orphan file). Drift transactions wrap multi-row writes.
- BDD scenarios are authored as `.feature` files under `apps/mobile/integration_test/`, generated to `*_test.dart` via `pnpm nx run mobile:build_runner`; generated files are committed. Step defs live in `apps/mobile/test/step/`.
- Commit with explicit file paths (never `git add -A`). End every commit message with the trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- DO NOT stage or touch the pre-existing uncommitted files: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`.
- `DocumentSaveException` (existing, in `document_repository.dart`) is the error type both new methods throw for a missing page row.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `apps/mobile/lib/features/library/document_repository.dart` | Persistence interface | Add `deletePage`, `replacePage` signatures |
| `apps/mobile/lib/features/library/drift/drift_document_repository.dart` | Drift implementation | Implement both |
| `apps/mobile/test/support/fake_library.dart` | Test double | Implement both (in-memory renumber + throw flags) |
| `apps/mobile/lib/features/scan/camera_screen.dart` | Scan/capture screen | Optional single-capture `onCapture` mode |
| `apps/mobile/lib/features/library/page_viewer_screen.dart` | Page viewer | `dependencies` param, overflow menu, delete/retake handlers |
| `apps/mobile/lib/features/library/home_screen.dart` | Composition | Pass `dependencies:` to `PageViewerScreen` |
| `apps/mobile/integration_test/h4_delete_retake.feature` (+ generated `_test.dart`) | On-device BDD | New |
| `apps/mobile/test/step/*.dart` | BDD step defs | New |
| `scripts/verify/h4.sh` | Acceptance gate | New |

---

### Task 1: `deletePage` — interface + Drift + Fake

Adds `deletePage` to the interface (which forces all implementers to define it, so Drift and Fake are done in the same task to keep the tree compiling).

**Files:**
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`
- Test: `apps/mobile/test/features/library/delete_page_test.dart` (create)

**Interfaces:**
- Consumes: `DocumentSaveException` (existing), `_fileStore.deleteDocumentDir(int)`, `_fileStore.absoluteFor(String)`, `_clock()`, the `pages`/`documents` Drift tables.
- Produces: `Future<int> deletePage(int documentId, int position)` — returns pages remaining (0 = document deleted). `FakeDocumentRepository.throwOnDeletePage` (bool), `FakeDocumentRepository.lastDeletedPagePosition` (int?).

- [ ] **Step 1: Add the interface method**

  In `apps/mobile/lib/features/library/document_repository.dart`, add after `reorderPages`'s declaration (inside the `abstract interface class DocumentRepository`):

  ```dart
  /// Deletes the page at [position] of [documentId]: removes its row, best-effort
  /// deletes its image and flat files, and renumbers the remaining pages so their
  /// positions stay contiguous (1..N-1). If it was the only page, the whole
  /// document (row + dir) is deleted.
  ///
  /// Returns the number of pages remaining (0 => the document was deleted).
  /// Throws [DocumentSaveException] when no page exists at ([documentId], [position]).
  Future<int> deletePage(int documentId, int position);
  ```

- [ ] **Step 2: Write the failing Drift tests**

  Create `apps/mobile/test/features/library/delete_page_test.dart`:

  ```dart
  import 'dart:io';
  import 'package:drift/native.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:mobile/features/library/document_file_store.dart';
  import 'package:mobile/features/library/document_repository.dart';
  import 'package:mobile/features/library/drift/app_database.dart';
  import 'package:mobile/features/library/drift/drift_document_repository.dart';
  import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
  import 'package:mobile/features/library/pdf/pdf_builder.dart';
  import 'package:mobile/features/scan/captured_image.dart';

  import '../../support/fake_library.dart'; // provides FakeDocumentRepository + FakeImageWarper

  void main() {
    late Directory base;
    late AppDatabase db;
    // ignore: prefer_function_declarations_over_variables
    final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

    setUp(() {
      base = Directory.systemTemp.createTempSync('h4del');
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() async {
      await db.close();
      if (base.existsSync()) base.deleteSync(recursive: true);
    });

    DriftDocumentRepository repo() => DriftDocumentRepository(
          db: db,
          scrubber: const JpegExifScrubber(),
          fileStore: DocumentFileStore(base),
          clock: clock,
          pdfBuilder: const PdfBuilder(),
          warper: FakeImageWarper(),
        );

    CapturedImage freshCapture(String filename) {
      final src = File('${base.path}/$filename')
        ..writeAsBytesSync(
            File('test/fixtures/exif_sample.jpg').readAsBytesSync());
      return CapturedImage(src.path);
    }

    test('deleting a middle page renumbers survivors and removes its files',
        () async {
      final r = repo();
      final doc = await r.createFromCapture(freshCapture('c1.jpg')); // pos 1
      await r.addPageToDocument(doc.id, freshCapture('c2.jpg')); // pos 2
      await r.addPageToDocument(doc.id, freshCapture('c3.jpg')); // pos 3

      final before = await r.getDocumentPages(doc.id);
      final page2Path = before[1].imagePath; // absolute path of page at pos 2
      expect(File(page2Path).existsSync(), isTrue);

      final remaining = await r.deletePage(doc.id, 2);

      expect(remaining, 2);
      final after = await r.getDocumentPages(doc.id);
      expect(after.map((p) => p.position), [1, 2],
          reason: 'survivors renumbered contiguously');
      expect(File(page2Path).existsSync(), isFalse,
          reason: "deleted page's image file removed (best-effort)");
    });

    test('deleting the only page deletes the whole document (returns 0)',
        () async {
      final r = repo();
      final doc = await r.createFromCapture(freshCapture('c1.jpg'));

      final remaining = await r.deletePage(doc.id, 1);

      expect(remaining, 0);
      expect(await db.select(db.documents).get(), isEmpty,
          reason: 'last-page rule: document row deleted');
      expect(Directory('${base.path}/documents/${doc.id}').existsSync(), isFalse,
          reason: 'document dir nuked');
    });

    test('deleting a non-existent position throws DocumentSaveException',
        () async {
      final r = repo();
      final doc = await r.createFromCapture(freshCapture('c1.jpg'));
      await expectLater(
        r.deletePage(doc.id, 99),
        throwsA(isA<DocumentSaveException>()),
      );
    });
  }
  ```

- [ ] **Step 3: Run tests to verify they fail**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "deletePage|deleting"
  ```
  Expected: FAIL — `deletePage` not defined on `DriftDocumentRepository` / `FakeDocumentRepository` (analyzer/compile error until Steps 4–5).

- [ ] **Step 4: Implement `deletePage` in Drift**

  In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`, add after `reorderPages`:

  ```dart
  @override
  Future<int> deletePage(int documentId, int position) async {
    final row = await (_db.select(_db.pages)
          ..where((t) =>
              t.documentId.equals(documentId) & t.position.equals(position)))
        .getSingleOrNull();
    if (row == null) {
      throw DocumentSaveException('deletePage: no page ($documentId, $position)');
    }
    final rows = await (_db.select(_db.pages)
          ..where((t) => t.documentId.equals(documentId))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final remaining = rows.length - 1;

    await _db.transaction(() async {
      await (_db.delete(_db.pages)..where((t) => t.id.equals(row.id))).go();
      if (remaining > 0) {
        // Renumber survivors whose position was above the deleted one: -1.
        for (final r in rows) {
          if (r.id == row.id) continue;
          if (r.position > position) {
            await (_db.update(_db.pages)..where((t) => t.id.equals(r.id)))
                .write(PagesCompanion(position: Value(r.position - 1)));
          }
        }
        await (_db.update(_db.documents)
              ..where((d) => d.id.equals(documentId)))
            .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
      } else {
        await (_db.delete(_db.documents)..where((d) => d.id.equals(documentId)))
            .go();
      }
    });

    // Best-effort file cleanup AFTER commit (DB is authoritative).
    if (remaining == 0) {
      await _fileStore.deleteDocumentDir(documentId);
    } else {
      try {
        await _fileStore.absoluteFor(row.relativeImagePath).delete();
      } on FileSystemException {/* already gone — fine */}
      final flat = row.flatRelativePath;
      if (flat != null) {
        try {
          await _fileStore.absoluteFor(flat).delete();
        } on FileSystemException {/* already gone — fine */}
      }
    }
    return remaining;
  }
  ```

- [ ] **Step 5: Implement `deletePage` on the Fake**

  In `apps/mobile/test/support/fake_library.dart`:

  1. Add the ctor field + flag. Near the other `throwOn*` fields add:
     ```dart
     final bool throwOnDeletePage;
     ```
     and in the constructor parameter list add:
     ```dart
     this.throwOnDeletePage = false,
     ```
  2. Add recorder field near the other recorders (e.g. after `lastReorderedPositions`):
     ```dart
     int? lastDeletedPagePosition;
     ```
  3. Add a mutable working copy of `pages` so deletions are visible to later `getDocumentPages` calls. Add this field:
     ```dart
     late final List<PageImage>? _working =
         pages == null ? null : List<PageImage>.from(pages!);
     ```
  4. Change `getDocumentPages` to read the working copy (behavior identical when `pages == null`):
     ```dart
     @override
     Future<List<PageImage>> getDocumentPages(int documentId) async {
       if (throwOnGetPages) throw StateError('fake: getDocumentPages failed');
       final w = _working;
       return w == null
           ? [PageImage(position: 1, imagePath: '/nonexistent/page-$documentId-1.jpg')]
           : List<PageImage>.from(w);
     }
     ```
  5. Add the method (anywhere among the overrides):
     ```dart
     @override
     Future<int> deletePage(int documentId, int position) async {
       if (throwOnDeletePage) {
         throw const DocumentSaveException('fake: deletePage failed');
       }
       final w = _working;
       if (w == null) {
         // Synthesized single page: deleting it removes the document.
         if (position != 1) {
           throw const DocumentSaveException('fake: no such page');
         }
         lastDeletedPagePosition = position;
         return 0;
       }
       final idx = w.indexWhere((p) => p.position == position);
       if (idx < 0) {
         throw const DocumentSaveException('fake: no such page');
       }
       w.removeAt(idx);
       // Renumber survivors contiguously 1..N.
       for (var i = 0; i < w.length; i++) {
         final p = w[i];
         w[i] = PageImage(
           position: i + 1,
           imagePath: p.imagePath,
           corners: p.corners,
           flatImagePath: p.flatImagePath,
         );
       }
       lastDeletedPagePosition = position;
       return w.length;
     }
     ```

- [ ] **Step 6: Run tests to verify they pass**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "deletePage|deleting"
  ```
  Expected: PASS (3 tests).

- [ ] **Step 7: Analyze + commit**

  ```bash
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  git add apps/mobile/lib/features/library/document_repository.dart \
          apps/mobile/lib/features/library/drift/drift_document_repository.dart \
          apps/mobile/test/support/fake_library.dart \
          apps/mobile/test/features/library/delete_page_test.dart
  git commit -m "feat(h4): deletePage — renumber survivors, last-page deletes document

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```
  Expected: `No issues found`, then commit succeeds.

---

### Task 2: `replacePage` — interface + Drift + Fake

**Files:**
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`
- Test: `apps/mobile/test/features/library/replace_page_test.dart` (create)

**Interfaces:**
- Consumes: `_scrubber.scrub`, `_warper.warp`, `_fileStore.writeRelative/absoluteFor/flatRelativeFor`, `_deleteTempSource` (existing private method), `CapturedImage`, `CropCorners`, `ImageEnhancer`, `DocumentSaveException`.
- Produces: `Future<void> replacePage(int documentId, int position, CapturedImage capture, {CropCorners? corners, ImageEnhancer? enhancer})`. `FakeDocumentRepository.throwOnReplacePage` (bool), `FakeDocumentRepository.lastReplacedPagePosition` (int?).

- [ ] **Step 1: Add the interface method**

  In `document_repository.dart`, add after the `deletePage` declaration:

  ```dart
  /// Replaces the page at [position] of [documentId] in place with [capture]
  /// (EXIF-scrubbed), applying [corners] (default full-frame) and [enhancer]
  /// exactly as [addPageToDocument] does. Overwrites the page's stored image and
  /// flat derivative, updates its corners, and bumps `modifiedAt`. The page keeps
  /// its [position]. Throws [DocumentSaveException] when no page exists at
  /// ([documentId], [position]).
  Future<void> replacePage(
    int documentId,
    int position,
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  });
  ```

- [ ] **Step 2: Write the failing Drift tests**

  Create `apps/mobile/test/features/library/replace_page_test.dart`:

  ```dart
  import 'dart:io';
  import 'package:drift/native.dart';
  import 'package:flutter/material.dart'; // Offset for CropCorners literals
  import 'package:flutter_test/flutter_test.dart';
  import 'package:mobile/features/library/crop_corners.dart';
  import 'package:mobile/features/library/document_file_store.dart';
  import 'package:mobile/features/library/document_repository.dart';
  import 'package:mobile/features/library/drift/app_database.dart';
  import 'package:mobile/features/library/drift/drift_document_repository.dart';
  import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
  import 'package:mobile/features/library/pdf/pdf_builder.dart';
  import 'package:mobile/features/scan/captured_image.dart';

  import '../../support/fake_library.dart'; // provides FakeDocumentRepository + FakeImageWarper

  void main() {
    late Directory base;
    late AppDatabase db;
    // ignore: prefer_function_declarations_over_variables
    final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

    setUp(() {
      base = Directory.systemTemp.createTempSync('h4rep');
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() async {
      await db.close();
      if (base.existsSync()) base.deleteSync(recursive: true);
    });

    DriftDocumentRepository repo() => DriftDocumentRepository(
          db: db,
          scrubber: const JpegExifScrubber(),
          fileStore: DocumentFileStore(base),
          clock: clock,
          pdfBuilder: const PdfBuilder(),
          warper: FakeImageWarper(),
        );

    CapturedImage freshCapture(String filename) {
      final src = File('${base.path}/$filename')
        ..writeAsBytesSync(
            File('test/fixtures/exif_sample.jpg').readAsBytesSync());
      return CapturedImage(src.path);
    }

    const corners = CropCorners(
      topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9));

    test('replacePage (full-frame) overwrites the image and clears corners',
        () async {
      final r = repo();
      final doc = await r.createFromCapture(freshCapture('c1.jpg'),
          corners: corners); // page 1 starts with a flat + corners
      final rel = 'documents/${doc.id}/page_1.jpg';
      final absPath = '${base.path}/$rel';

      await r.replacePage(doc.id, 1, freshCapture('c1b.jpg')); // full-frame

      expect(File(absPath).existsSync(), isTrue,
          reason: 'image overwritten in place at the same path');
      final page = (await db.select(db.pages).get()).single;
      expect(page.position, 1);
      expect(page.corners, isNull, reason: 'corners cleared for full-frame');
      expect(page.flatRelativePath, isNull,
          reason: 'flat derivative dropped for full-frame');
    });

    test('replacePage with corners writes a flat and stores corners', () async {
      final r = repo();
      final doc = await r.createFromCapture(freshCapture('c1.jpg')); // full-frame

      await r.replacePage(doc.id, 1, freshCapture('c1b.jpg'), corners: corners);

      final page = (await db.select(db.pages).get()).single;
      expect(page.corners, isNotNull, reason: 'corners stored');
      expect(page.flatRelativePath, isNotNull, reason: 'flat written');
      expect(File('${base.path}/${page.flatRelativePath}').existsSync(), isTrue);
    });

    test('replacePage on a non-existent position throws DocumentSaveException',
        () async {
      final r = repo();
      final doc = await r.createFromCapture(freshCapture('c1.jpg'));
      await expectLater(
        r.replacePage(doc.id, 99, freshCapture('c2.jpg')),
        throwsA(isA<DocumentSaveException>()),
      );
    });
  }
  ```

  > NOTE: `FakeImageWarper` returns non-null bytes (so a flat is written); confirm it does — the existing `reorderPages`/`addPage` tests rely on the same fake warper producing a flat for non-full-frame corners.

- [ ] **Step 3: Run tests to verify they fail**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "replacePage"
  ```
  Expected: FAIL — `replacePage` not defined.

- [ ] **Step 4: Implement `replacePage` in Drift**

  In `drift_document_repository.dart`, add after `deletePage`:

  ```dart
  @override
  Future<void> replacePage(
    int documentId,
    int position,
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  }) async {
    try {
      final row = await (_db.select(_db.pages)
            ..where((t) =>
                t.documentId.equals(documentId) & t.position.equals(position)))
          .getSingleOrNull();
      if (row == null) {
        throw DocumentSaveException('replacePage: no page ($documentId, $position)');
      }

      final raw = await File(capture.path).readAsBytes();
      final Uint8List scrubbed = _scrubber.scrub(raw);
      final isFullFrame = corners == null || corners == CropCorners.fullFrame;

      Uint8List bytesToStore = scrubbed;
      if (enhancer != null && isFullFrame) {
        try {
          bytesToStore = await enhancer.enhance(scrubbed);
        } catch (_) {}
      }
      // Overwrite the original image in place (same stored relative path).
      await _fileStore.writeRelative(row.relativeImagePath, bytesToStore);

      String? flatRel;
      if (!isFullFrame) {
        try {
          final Uint8List? flat = await _warper.warp(scrubbed, corners);
          if (flat != null) {
            Uint8List flatBytes = flat;
            if (enhancer != null) {
              try {
                flatBytes = await enhancer.enhance(flat);
              } catch (_) {}
            }
            // Reuse the existing flat path when present → overwrite in place,
            // never orphan a stale derivative (positions can drift after reorders).
            flatRel = row.flatRelativePath ??
                _fileStore.flatRelativeFor(documentId, position);
            await _fileStore.writeRelative(flatRel, flatBytes);
          }
        } catch (_) {}
      }

      // Corners now full-frame (or warp produced nothing) → drop the old flat.
      if (flatRel == null && row.flatRelativePath != null) {
        try {
          await _fileStore.absoluteFor(row.flatRelativePath!).delete();
        } on FileSystemException {/* already gone — fine */}
      }

      await _db.transaction(() async {
        await (_db.update(_db.pages)..where((t) => t.id.equals(row.id))).write(
            PagesCompanion(
                corners: Value(corners?.toStorage()),
                flatRelativePath: Value(flatRel)));
        await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
            .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
      });

      await _deleteTempSource(capture.path);
    } catch (e) {
      if (e is DocumentSaveException) rethrow;
      throw DocumentSaveException('replacePage failed: $e');
    }
  }
  ```

- [ ] **Step 5: Implement `replacePage` on the Fake**

  In `apps/mobile/test/support/fake_library.dart`:

  1. Add ctor field + flag:
     ```dart
     final bool throwOnReplacePage;
     ```
     constructor param:
     ```dart
     this.throwOnReplacePage = false,
     ```
  2. Add recorder near `lastDeletedPagePosition`:
     ```dart
     int? lastReplacedPagePosition;
     ```
  3. Add the method:
     ```dart
     @override
     Future<void> replacePage(
       int documentId,
       int position,
       CapturedImage capture, {
       CropCorners? corners,
       ImageEnhancer? enhancer,
     }) async {
       if (throwOnReplacePage) {
         throw const DocumentSaveException('fake: replacePage failed');
       }
       final w = _working;
       if (w != null && w.indexWhere((p) => p.position == position) < 0) {
         throw const DocumentSaveException('fake: no such page');
       }
       lastReplacedPagePosition = position;
     }
     ```

- [ ] **Step 6: Run tests to verify they pass**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "replacePage"
  ```
  Expected: PASS (3 tests).

- [ ] **Step 7: Analyze + commit**

  ```bash
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  git add apps/mobile/lib/features/library/document_repository.dart \
          apps/mobile/lib/features/library/drift/drift_document_repository.dart \
          apps/mobile/test/support/fake_library.dart \
          apps/mobile/test/features/library/replace_page_test.dart
  git commit -m "feat(h4): replacePage — overwrite image/flat/corners in place

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```
  Expected: `No issues found`, commit succeeds.

---

### Task 3: `CameraScreen` single-capture (retake) mode

**Files:**
- Modify: `apps/mobile/lib/features/scan/camera_screen.dart`
- Test: `apps/mobile/test/features/scan/camera_screen_h4_test.dart` (create)

**Interfaces:**
- Consumes: existing `_onAccept(CapturedImage, CropCorners, ImageEnhancer)` flow; keys `scan-shutter`, `review-accept`.
- Produces: new optional `CameraScreen` param `final Future<bool> Function(CapturedImage, CropCorners, ImageEnhancer)? onCapture;` — when non-null, accept invokes it and (on true) pops the camera; when null, behavior is unchanged.

- [ ] **Step 1: Write the failing tests**

  Create `apps/mobile/test/features/scan/camera_screen_h4_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:mobile/features/scan/camera_permission_service.dart';
  import 'package:mobile/features/scan/camera_screen.dart';
  import 'package:mobile/features/scan/captured_image.dart';
  import 'package:mobile/features/library/crop_corners.dart';
  import 'package:mobile/features/library/image_enhancer.dart';
  import 'package:mobile/features/scan/scan_dependencies.dart';

  import '../../support/fake_library.dart';
  import '../../support/fake_scan.dart';

  ScanDependencies _granted() => ScanDependencies(
        createPermissionService: () =>
            FakeCameraPermissionService(CameraPermissionStatus.granted),
        createPreviewController: () => FakeCameraPreviewController(
            captureReturnPath: '/nonexistent/h4test.jpg'),
      );

  void main() {
    testWidgets('single-capture mode: accept invokes onCapture and pops',
        (tester) async {
      var called = 0;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            key: const Key('caller'),
            body: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                builder: (_) => CameraScreen(
                  dependencies: _granted(),
                  repository: FakeDocumentRepository(),
                  onCapture: (CapturedImage img, CropCorners c, ImageEnhancer e) async {
                    called++;
                    return true;
                  },
                ),
              )),
              child: const Text('go'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scan-shutter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-accept')));
      await tester.pumpAndSettle();

      expect(called, 1, reason: 'onCapture invoked on accept');
      expect(find.byKey(const Key('caller')), findsOneWidget,
          reason: 'camera popped back to caller after successful capture');
      expect(find.byType(CameraScreen), findsNothing);
    });

    testWidgets('single-capture failure: snackbar shown, stays in camera',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CameraScreen(
          dependencies: _granted(),
          repository: FakeDocumentRepository(),
          onCapture: (_, __, ___) async => false,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scan-shutter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-accept')));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't replace page. Try again."), findsOneWidget);
      expect(find.byType(CameraScreen), findsOneWidget,
          reason: 'still in camera to retry');
    });
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "single-capture"
  ```
  Expected: FAIL — `onCapture` is not a parameter of `CameraScreen`.

- [ ] **Step 3: Add the parameter**

  In `apps/mobile/lib/features/scan/camera_screen.dart`, in the `CameraScreen` widget class, add the field and constructor param:

  ```dart
  /// When non-null, the screen is in single-capture (retake) mode: after the
  /// user accepts a capture in review, [onCapture] is invoked with the image,
  /// crop corners, and enhancer. If it returns true the camera screen pops back
  /// to its caller (one page only — no accumulation, no "Done"). When null
  /// (default) the screen keeps its create/append behavior.
  final Future<bool> Function(CapturedImage, CropCorners, ImageEnhancer)? onCapture;
  ```
  In the constructor add `this.onCapture,` (after `required this.repository,`).

- [ ] **Step 4: Branch in `_onAccept`**

  In `camera_screen.dart`, at the TOP of `_onAccept` (before the `if (_activeDocId == null)` block), insert:

  ```dart
  if (widget.onCapture != null) {
    final ok = await widget.onCapture!(image, corners, enhancer);
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't replace page. Try again.")),
      );
      navigator.pop(); // dismiss review, stay in camera to retry
      return;
    }
    navigator.pop(); // dismiss review
    navigator.pop(); // leave camera, back to viewer
    return;
  }
  ```

  (No import needed — `CapturedImage`, `CropCorners`, `ImageEnhancer` are already imported in this file.)

- [ ] **Step 5: Run tests to verify they pass**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "single-capture"
  ```
  Expected: PASS (2 tests).

- [ ] **Step 6: Analyze + commit**

  ```bash
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  git add apps/mobile/lib/features/scan/camera_screen.dart \
          apps/mobile/test/features/scan/camera_screen_h4_test.dart
  git commit -m "feat(h4): CameraScreen single-capture (retake) mode via onCapture

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 4: `PageViewerScreen` overflow menu — delete / retake

**Files:**
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart`
- Modify: `apps/mobile/lib/features/library/home_screen.dart`
- Test: `apps/mobile/test/features/library/page_viewer_h4_test.dart` (create)

**Interfaces:**
- Consumes: `deletePage` / `replacePage` (Tasks 1–2), `CameraScreen.onCapture` (Task 3), `ScanDependencies` (const-constructible), existing `_load`, `_controller`, `_current`, `_pages`.
- Produces: app-bar `PopupMenuButton` key `page-viewer-page-menu`; items keyed `page-viewer-retake`, `page-viewer-delete-page`; dialog buttons keyed `page-viewer-delete-page-cancel` / `page-viewer-delete-page-confirm`. New ctor param `ScanDependencies dependencies` (default `const ScanDependencies()`).

- [ ] **Step 1: Write the failing widget tests**

  Create `apps/mobile/test/features/library/page_viewer_h4_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:mobile/features/library/page_image.dart';
  import 'package:mobile/features/library/page_viewer_screen.dart';
  import 'package:mobile/features/scan/camera_permission_service.dart';
  import 'package:mobile/features/scan/camera_screen.dart';
  import 'package:mobile/features/scan/scan_dependencies.dart';

  import '../../support/fake_library.dart';
  import '../../support/fake_scan.dart';

  void main() {
    Future<void> pushViewer(WidgetTester tester, FakeDocumentRepository repo,
        {ScanDependencies? deps}) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PageViewerScreen(
                    documentId: 1,
                    name: 'Doc',
                    repository: repo,
                    dependencies: deps ?? const ScanDependencies(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
    }

    FakeDocumentRepository twoPageRepo() => FakeDocumentRepository(pages: [
          const PageImage(position: 1, imagePath: '/nonexistent/p1.jpg'),
          const PageImage(position: 2, imagePath: '/nonexistent/p2.jpg'),
        ]);

    testWidgets('overflow menu exposes Retake page and Delete page',
        (tester) async {
      await pushViewer(tester, twoPageRepo());
      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-viewer-retake')), findsOneWidget);
      expect(find.byKey(const Key('page-viewer-delete-page')), findsOneWidget);
    });

    testWidgets('Delete page: confirm calls deletePage', (tester) async {
      final repo = twoPageRepo();
      await pushViewer(tester, repo);
      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-delete-page-confirm')));
      await tester.pumpAndSettle();
      expect(repo.lastDeletedPagePosition, 1);
    });

    testWidgets('Delete page: cancel does NOT call deletePage', (tester) async {
      final repo = twoPageRepo();
      await pushViewer(tester, repo);
      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-delete-page-cancel')));
      await tester.pumpAndSettle();
      expect(repo.lastDeletedPagePosition, isNull);
    });

    testWidgets('Delete the only page: whole-document copy + pops viewer',
        (tester) async {
      final repo = FakeDocumentRepository(pages: [
        const PageImage(position: 1, imagePath: '/nonexistent/p1.jpg'),
      ]);
      await pushViewer(tester, repo);
      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'This is the only page. Deleting it removes the whole document.'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('page-viewer-delete-page-confirm')));
      await tester.pumpAndSettle();
      // remaining == 0 → viewer popped back to the opener button.
      expect(find.byKey(const Key('open')), findsOneWidget);
      expect(find.byType(PageViewerScreen), findsNothing);
    });

    testWidgets('Delete page failure shows a snackbar, stays on viewer',
        (tester) async {
      final repo = FakeDocumentRepository(
        throwOnDeletePage: true,
        pages: [
          const PageImage(position: 1, imagePath: '/nonexistent/p1.jpg'),
          const PageImage(position: 2, imagePath: '/nonexistent/p2.jpg'),
        ],
      );
      await pushViewer(tester, repo);
      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-delete-page-confirm')));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't delete page"), findsOneWidget);
      expect(find.byType(PageViewerScreen), findsOneWidget);
    });

    testWidgets('Retake page pushes the camera', (tester) async {
      final repo = twoPageRepo();
      // Camera-unavailable deps: builds CameraScreen without platform channels.
      final deps = ScanDependencies(
        createPermissionService: () =>
            FakeCameraPermissionService(CameraPermissionStatus.granted),
        createPreviewController: () =>
            FakeCameraPreviewController(captureReturnPath: '/nonexistent/r.jpg'),
      );
      await pushViewer(tester, repo, deps: deps);
      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-retake')));
      await tester.pumpAndSettle();
      expect(find.byType(CameraScreen), findsOneWidget);
    });
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "overflow menu|Delete page|Delete the only page|Retake page"
  ```
  Expected: FAIL — `dependencies` not a param; menu keys absent.

- [ ] **Step 3: Add the `dependencies` param + imports**

  In `apps/mobile/lib/features/library/page_viewer_screen.dart`:
  - Add imports at the top. `dart:async` goes with the other `dart:` import
    (`dart:io` is already there); the two feature imports go with the rest:
    ```dart
    import 'dart:async'; // unawaited

    import '../scan/camera_screen.dart';
    import '../scan/scan_dependencies.dart';
    ```
  - Add the field to `PageViewerScreen`:
    ```dart
    final ScanDependencies dependencies;
    ```
  - Add to the constructor (after `required this.repository,`):
    ```dart
    this.dependencies = const ScanDependencies(),
    ```

- [ ] **Step 4: Add the handlers**

  In `_PageViewerScreenState`, add these two methods (near `_confirmAndDelete`):

  ```dart
  Future<void> _confirmAndDeletePage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    final isLast = pages.length == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(isLast
            ? 'This is the only page. Deleting it removes the whole document.'
            : "Delete this page? This can't be undone."),
        actions: [
          TextButton(
            key: const Key('page-viewer-delete-page-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('page-viewer-delete-page-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final remaining =
          await widget.repository.deletePage(widget.documentId, page.position);
      if (!mounted) return;
      if (remaining == 0) {
        Navigator.of(context).pop(); // document gone → back to Home
        return;
      }
      if (_current >= remaining) _current = remaining - 1; // clamp
      await _load();
      if (mounted && _controller.hasClients) _controller.jumpToPage(_current);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete page")),
      );
    }
  }

  Future<void> _retakePage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraScreen(
          dependencies: widget.dependencies,
          repository: widget.repository,
          onCapture: (image, corners, enhancer) async {
            try {
              await widget.repository.replacePage(
                  widget.documentId, page.position, image,
                  corners: corners, enhancer: enhancer);
              return true;
            } catch (_) {
              return false;
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }
  ```

- [ ] **Step 5: Add the overflow menu to the app bar**

  In `build`, inside the `AppBar.actions` list, add a `PopupMenuButton` after the existing export `IconButton` (and keep the document-delete `IconButton` as-is):

  ```dart
  PopupMenuButton<String>(
    key: const Key('page-viewer-page-menu'),
    enabled: !(_loading || _error || _exporting || (_pages?.isEmpty ?? true)),
    onSelected: (v) {
      if (v == 'retake') unawaited(_retakePage());
      if (v == 'delete') unawaited(_confirmAndDeletePage());
    },
    itemBuilder: (_) => const [
      PopupMenuItem<String>(
        value: 'retake',
        key: Key('page-viewer-retake'),
        child: Text('Retake page'),
      ),
      PopupMenuItem<String>(
        value: 'delete',
        key: Key('page-viewer-delete-page'),
        child: Text('Delete page'),
      ),
    ],
  ),
  ```

  > `unawaited(...)` (from `dart:async`, added in Step 3) fire-and-forgets these UI actions without tripping the `discarded_futures` lint that the repo has enabled (the same reason `_reorderPages` uses an ignore comment for `_persistReorder`).

- [ ] **Step 6: Pass `dependencies` from HomeScreen**

  In `apps/mobile/lib/features/library/home_screen.dart`, in `_openDocument`, add `dependencies: widget.dependencies,` to the `PageViewerScreen(...)` constructor call:

  ```dart
  builder: (_) => PageViewerScreen(
    documentId: s.document.id,
    name: s.document.name,
    repository: repo,
    dependencies: widget.dependencies,
  ),
  ```

- [ ] **Step 7: Run tests to verify they pass**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache -- --name "overflow menu|Delete page|Delete the only page|Retake page"
  ```
  Expected: PASS (6 tests).

- [ ] **Step 8: Full suite + analyze**

  ```bash
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  pnpm nx run mobile:test --skip-nx-cache
  ```
  Expected: `No issues found`; `All tests passed!`.

- [ ] **Step 9: Commit**

  ```bash
  git add apps/mobile/lib/features/library/page_viewer_screen.dart \
          apps/mobile/lib/features/library/home_screen.dart \
          apps/mobile/test/features/library/page_viewer_h4_test.dart
  git commit -m "feat(h4): page-viewer overflow menu — delete / retake current page

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 5: BDD feature + step defs + generated test

Write the Gherkin feature, the step defs, then run `build_runner` to generate the on-device test. Commit generated + authored files together.

**Existing step def to REUSE (do NOT recreate):**
`apps/mobile/test/step/the_page_viewer_is_open_with2_pages.dart` (from H2) — sets `h2Repo` to a 2-page `FakeDocumentRepository` and pumps the viewer.

**Files:**
- Create: `apps/mobile/integration_test/h4_delete_retake.feature`
- Create: `apps/mobile/test/step/i_delete_the_current_page.dart`
- Create: `apps/mobile/test/step/the_document_has1_page.dart`
- Create (generated): `apps/mobile/integration_test/h4_delete_retake_test.dart`

**Interfaces:**
- Consumes: `h2Repo` global + `thePageViewerIsOpenWith2Pages` from the existing step; the `page-viewer-page-menu` / `page-viewer-delete-page` / `page-viewer-delete-page-confirm` keys (Task 4).

- [ ] **Step 1: Write the feature file**

  Create `apps/mobile/integration_test/h4_delete_retake.feature`:

  ```gherkin
  Feature: H4 Delete page

    Scenario: Deleting one page of a two-page document leaves one page
      Given the page viewer is open with 2 pages
      When I delete the current page
      Then the document has 1 page
  ```

  > SCOPE NOTE: The retake gesture and last-page-deletes-document paths are proven at the Drift unit level (Tasks 1–2) and widget level (Tasks 3–4). This on-device BDD scenario asserts the end-to-end delete flow renders correctly on a real device. Do not add scenarios that require a live camera capture on-device (no deterministic capture in CI).

- [ ] **Step 2: Write the "delete" step def**

  Create `apps/mobile/test/step/i_delete_the_current_page.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';

  /// Usage: I delete the current page
  Future<void> iDeleteTheCurrentPage(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-delete-page-confirm')));
    await tester.pumpAndSettle();
  }
  ```

- [ ] **Step 3: Write the "then" step def**

  Create `apps/mobile/test/step/the_document_has1_page.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';

  /// Usage: the document has 1 page
  ///
  /// The 2-page fixture had pages at positions 1 and 2. Deleting the current
  /// (first) page renumbers the survivor to position 1, so the PageView now
  /// shows 'page-viewer-page-1' and no longer has 'page-viewer-page-2'. These
  /// keys are set by PageViewerScreen._buildPages, keyed by page position.
  Future<void> theDocumentHas1Page(WidgetTester tester) async {
    expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-page-2')), findsNothing);
  }
  ```

- [ ] **Step 4: Generate the test**

  ```bash
  pnpm nx run mobile:build_runner
  ```
  Expected: creates `apps/mobile/integration_test/h4_delete_retake_test.dart` importing the three step files. Confirm:
  ```bash
  grep "import" apps/mobile/integration_test/h4_delete_retake_test.dart
  ```
  Expected to include `the_page_viewer_is_open_with2_pages.dart`, `i_delete_the_current_page.dart`, `the_document_has1_page.dart`.

- [ ] **Step 5: Run the host suite (includes the generated BDD test)**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  ```
  Expected: `All tests passed!` (the generated H4 scenario runs under the host runner too).

- [ ] **Step 6: Commit**

  ```bash
  git add apps/mobile/integration_test/h4_delete_retake.feature \
          apps/mobile/integration_test/h4_delete_retake_test.dart \
          apps/mobile/test/step/i_delete_the_current_page.dart \
          apps/mobile/test/step/the_document_has1_page.dart
  git commit -m "test(h4): BDD feature, step defs, and generated test for delete page

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 6: Verify script + plans index

**Files:**
- Create: `scripts/verify/h4.sh`
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Create `scripts/verify/h4.sh`**

  ```bash
  #!/usr/bin/env bash
  # Verify H4 (Delete / retake page) acceptance criteria.
  # Run from repository root: bash scripts/verify/h4.sh
  # VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib.sh
  source "$DIR/lib.sh"
  cd "$ROOT"

  echo "== H4 verification =="

  require_tool flutter
  require_tool pnpm

  # ---- Static assertions ----
  assert_file_has "deletePage in DocumentRepository interface" \
    "apps/mobile/lib/features/library/document_repository.dart" \
    "deletePage"

  assert_file_has "replacePage in DocumentRepository interface" \
    "apps/mobile/lib/features/library/document_repository.dart" \
    "replacePage"

  assert_file_has "deletePage in DriftDocumentRepository" \
    "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
    "deletePage"

  assert_file_has "replacePage in DriftDocumentRepository" \
    "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
    "replacePage"

  assert_file_has "onCapture single-capture mode in CameraScreen" \
    "apps/mobile/lib/features/scan/camera_screen.dart" \
    "onCapture"

  assert_file_has "page menu in PageViewerScreen" \
    "apps/mobile/lib/features/library/page_viewer_screen.dart" \
    "page-viewer-page-menu"

  assert_file_has "retake handler in PageViewerScreen" \
    "apps/mobile/lib/features/library/page_viewer_screen.dart" \
    "_retakePage"

  assert_file_has "delete-page handler in PageViewerScreen" \
    "apps/mobile/lib/features/library/page_viewer_screen.dart" \
    "_confirmAndDeletePage"

  assert_file_has "BDD feature file exists" \
    "apps/mobile/integration_test/h4_delete_retake.feature" \
    "Delete page"

  assert_file_has "generated BDD test exists" \
    "apps/mobile/integration_test/h4_delete_retake_test.dart" \
    "iDeleteTheCurrentPage"

  # ---- OpenCV host library (scan tests in shared suite need it) ----
  bash "$ROOT/scripts/setup-cv-host-test.sh"
  export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
  export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

  # ---- Host tests + analyze ----
  assert_cmd "host tests pass" "All tests passed!" \
    pnpm nx run mobile:test --skip-nx-cache

  assert_cmd "flutter analyze clean" "No issues found" \
    bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

  # ---- On-device BDD (skippable for CI without a device) ----
  if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
    warn "VERIFY_SKIP_DEVICE=1 — on-device BDD skipped (must pass on real device before gate)"
  else
    assert_cmd "on-device BDD passes (iOS)" "All tests passed" \
      pnpm nx run mobile:verify_integration_ios -- --dart-define=INTEGRATION_TEST=h4
  fi

  echo "== H4 verification complete =="
  ```

  Make it executable:
  ```bash
  chmod +x scripts/verify/h4.sh
  ```

- [ ] **Step 2: Update the plans index**

  In `docs/superpowers/plans/00-plans-index.md`, change the H4 row status from `⏳` to `✅ **built & gated**` and set its plan-file column to `2026-07-01-h4-delete-retake-pages.md`.

- [ ] **Step 3: Run the verify script (device skipped if none attached)**

  ```bash
  VERIFY_SKIP_DEVICE=1 bash scripts/verify/h4.sh
  ```
  Expected: ends `== H4 verification complete ==` with all static + host + analyze asserts passing (device line warns, not fails). Run WITHOUT `VERIFY_SKIP_DEVICE=1` on a real device before the gate.

- [ ] **Step 4: Commit**

  ```bash
  git add scripts/verify/h4.sh docs/superpowers/plans/00-plans-index.md
  git commit -m "chore(h4): verify script and plans index update

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

## Self-Review (author checklist — completed)

**Spec coverage:**
- Delete current page (with confirm) → Task 4 handler + Task 1 repo + Task 5 BDD. ✓
- Last-page deletes whole document (confirm) → Task 1 (`remaining == 0` deletes doc) + Task 4 (pops viewer, whole-document copy) + Task 1 unit test. ✓
- Retake / replace in place → Task 2 (`replacePage`) + Task 3 (`onCapture`) + Task 4 (`_retakePage`). ✓
- Order & integrity preserved on delete → Task 1 renumbers survivors contiguously + unit test asserts `[1,2]`. ✓
- iOS + Android → all Material widgets, no platform branching (Global Constraints). ✓

**Placeholder scan:** none — every code step shows complete code; every command has an expected marker.

**Type consistency:** `deletePage(int,int)→Future<int>`, `replacePage(int,int,CapturedImage,{CropCorners?,ImageEnhancer?})→Future<void>`, `onCapture: Future<bool> Function(CapturedImage,CropCorners,ImageEnhancer)?`, keys `page-viewer-page-menu` / `page-viewer-retake` / `page-viewer-delete-page` / `page-viewer-delete-page-confirm` / `page-viewer-delete-page-cancel` — used identically across tasks and tests.
