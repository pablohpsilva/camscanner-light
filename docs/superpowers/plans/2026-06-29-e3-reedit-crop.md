# E3 — Re-edit Crop Corners Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user open a saved document's crop overlay from the page viewer, adjust the corner handles, and re-trigger perspective flatten — replacing the stored flat image in-place.

**Architecture:** New `updatePageCorners` method on `DocumentRepository` interface, implemented in `DriftDocumentRepository` (read original JPEG → warp → write flat → update DB row). A small new `EditCropScreen` wraps the existing `CropOverlay` widget and returns accepted corners via `Navigator.pop`. `PageViewerScreen` gains a crop-edit icon in its AppBar that pushes `EditCropScreen`, awaits corners, calls the repo, and reloads.

**Tech Stack:** Flutter/Dart, Drift ORM, `image` package (already present), `bdd_widget_test` build_runner

## Global Constraints

- No new pub dependencies — all required packages already in `pubspec.yaml`.
- No schema migration — `Pages.corners` (v2) and `Pages.flatRelativePath` (v3) already exist.
- `library_dependencies.dart` unchanged — `updatePageCorners` adds no new injected services.
- DIP preserved — `PageViewerScreen` never imports `PerspectiveWarper`, `DocumentFileStore`, or Drift directly.
- TDD — write the failing test first, run to see it fail, then implement.
- Non-loadable paths (`/nonexistent/...`) in widget tests — do not load real images in host tests.
- Keys: `'page-viewer-edit'` (AppBar button), `'edit-crop-accept'` (EditCropScreen AppBar accept).
- Positions are 1-indexed (`position = 1` for the first page).

---

### Task 1: `DocumentRepository` interface + `FakeDocumentRepository` stub

**Files:**
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`

**Interfaces:**
- Produces: `Future<void> updatePageCorners(int documentId, int position, CropCorners corners)` on `DocumentRepository`. All later tasks depend on this signature.

- [ ] **Step 1: Add `updatePageCorners` to the `DocumentRepository` interface**

Open `apps/mobile/lib/features/library/document_repository.dart`. Add the new method after `rename`:

```dart
  /// Re-warps the page at [position] using [corners] and updates the stored
  /// flat image. If [corners] == [CropCorners.fullFrame], deletes the flat
  /// file (best-effort) and clears [flatRelativePath] in the DB. Throws
  /// [DocumentSaveException] when the page row does not exist. Rethrows
  /// [WarpException] or IO errors on warp/write failure (DB unchanged).
  Future<void> updatePageCorners(
      int documentId, int position, CropCorners corners);
```

The complete file after the edit:

```dart
import 'dart:io';

import '../scan/captured_image.dart';
import 'crop_corners.dart';
import 'document.dart';
import 'document_summary.dart';
import 'page_image.dart';

/// The only persistence surface the widget layer knows (DIP). The Drift
/// implementation hides the DB, scrubber, file store, and clock.
abstract interface class DocumentRepository {
  /// Persists [capture] (EXIF-scrubbed) and creates a one-page document with the
  /// page's crop [corners] (defaults to full-frame). Image bytes are NOT
  /// transformed — corners are metadata (E1). Throws [DocumentSaveException] on
  /// failure (the capture is not lost).
  Future<Document> createFromCapture(CapturedImage capture, {CropCorners? corners});

  /// All documents (newest first) with page count and first-page thumbnail path
  /// (absolute, resolved at read time; null when the document has no page).
  Future<List<DocumentSummary>> listDocumentSummaries();

  /// Pages of [documentId], position ascending, with ABSOLUTE image paths
  /// (resolved at read time). Empty when the document has no pages.
  Future<List<PageImage>> getDocumentPages(int documentId);

  /// Deletes [documentId], its pages, and its on-disk image files. Row-first:
  /// an authoritative DB delete (pages then document, one transaction), then a
  /// best-effort file cleanup. A non-existent id is a no-op.
  Future<void> deleteDocument(int documentId);

  /// Generates a PDF of [documentId] to on-device storage and returns the file.
  /// Throws [DocumentExportException] on any failure (e.g. a missing page file).
  Future<File> exportPdf(int documentId);

  /// Renames [documentId] to [newName] (trimmed) and bumps modifiedAt. Returns
  /// the updated document. Throws [DocumentRenameException] when the trimmed
  /// name is empty or no document with that id exists. The name stays on-device.
  Future<Document> rename(int documentId, String newName);

  /// Re-warps the page at [position] using [corners] and updates the stored
  /// flat image. If [corners] == [CropCorners.fullFrame], deletes the flat
  /// file (best-effort) and clears [flatRelativePath] in the DB. Throws
  /// [DocumentSaveException] when the page row does not exist. Rethrows
  /// [WarpException] or IO errors on warp/write failure (DB unchanged).
  Future<void> updatePageCorners(
      int documentId, int position, CropCorners corners);
}

class DocumentSaveException implements Exception {
  final String message;
  const DocumentSaveException(this.message);
  @override
  String toString() => 'DocumentSaveException: $message';
}

class DocumentExportException implements Exception {
  final String message;
  const DocumentExportException(this.message);
  @override
  String toString() => 'DocumentExportException: $message';
}

class DocumentRenameException implements Exception {
  final String message;
  const DocumentRenameException(this.message);
  @override
  String toString() => 'DocumentRenameException: $message';
}
```

- [ ] **Step 2: Run tests to confirm compile error on unimplemented interface**

Run:
```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/mobile && flutter test 2>&1 | head -30
```

Expected: compilation error — `FakeDocumentRepository` (in `test/support/fake_library.dart`) does not implement `updatePageCorners`.

- [ ] **Step 3: Add `updatePageCorners` stub + tracking fields to `FakeDocumentRepository`**

Open `apps/mobile/test/support/fake_library.dart`. Add the following to `FakeDocumentRepository`:

Add to the constructor parameter list (after `throwOnRename`):
```dart
  final bool throwOnUpdate;
```

Add to the field declarations (after `renamedTo`):
```dart
  int? lastUpdatedPosition;
  CropCorners? lastUpdatedCorners;
```

Update the constructor to include `this.throwOnUpdate = false,`.

Add the new method after `rename`:
```dart
  @override
  Future<void> updatePageCorners(
      int documentId, int position, CropCorners corners) async {
    if (throwOnUpdate) {
      throw DocumentSaveException('fake: update failed');
    }
    lastUpdatedPosition = position;
    lastUpdatedCorners = corners;
  }
```

The complete updated `FakeDocumentRepository` class (replace lines 23–143):

```dart
/// In-memory fake repository for host tests. Optionally throws, or blocks on a
/// [gate] so a test can observe the transient `saving` state.
class FakeDocumentRepository implements DocumentRepository {
  final bool throwOnCreate;
  final bool throwOnList;
  final bool throwOnGetPages;
  final bool throwOnDelete;
  final bool throwOnExport;
  final bool throwOnRename;
  final bool throwOnUpdate;
  final Completer<void>? gate;
  final Completer<void>? exportGate;
  final Completer<void>? listGate;
  final List<Document> documents;
  final List<PageImage>? pages; // null => synthesize one non-loadable page
  int createCalls = 0;
  int listCalls = 0;
  CropCorners? lastSavedCorners;
  int? lastUpdatedPosition;
  CropCorners? lastUpdatedCorners;
  final List<int> deletedIds = <int>[];
  final List<int> exportedIds = <int>[];
  final List<String> renamedTo = <String>[];

  FakeDocumentRepository({
    this.throwOnCreate = false,
    this.throwOnList = false,
    this.throwOnGetPages = false,
    this.throwOnDelete = false,
    this.throwOnExport = false,
    this.throwOnRename = false,
    this.throwOnUpdate = false,
    this.gate,
    this.exportGate,
    this.listGate,
    List<Document>? documents,
    this.pages,
  }) : documents = documents ?? <Document>[];

  @override
  Future<Document> createFromCapture(CapturedImage capture, {CropCorners? corners}) async {
    createCalls++;
    lastSavedCorners = corners;
    if (gate != null) await gate!.future;
    if (throwOnCreate) {
      throw const DocumentSaveException('fake: save failed');
    }
    final doc = Document(
      id: documents.length + 1,
      name: 'Scan 2026-06-27 20.26.42',
      createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
      modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    );
    documents.insert(0, doc);
    return doc;
  }

  @override
  Future<List<PageImage>> getDocumentPages(int documentId) async {
    if (throwOnGetPages) throw StateError('fake: getDocumentPages failed');
    return pages ??
        [PageImage(position: 1, imagePath: '/nonexistent/page-$documentId-1.jpg')];
  }

  @override
  Future<void> deleteDocument(int documentId) async {
    if (throwOnDelete) throw StateError('fake: delete failed');
    deletedIds.add(documentId);
    documents.removeWhere((d) => d.id == documentId);
  }

  @override
  Future<File> exportPdf(int documentId) async {
    if (throwOnExport) {
      throw const DocumentExportException('fake: export failed');
    }
    if (exportGate != null) await exportGate!.future;
    exportedIds.add(documentId);
    return File('${Directory.systemTemp.path}/fake-export-$documentId.pdf');
  }

  @override
  Future<List<DocumentSummary>> listDocumentSummaries() async {
    listCalls++;
    if (listGate != null) await listGate!.future;
    if (throwOnList) {
      throw StateError('fake: list failed');
    }
    return List<DocumentSummary>.unmodifiable(documents.map((d) =>
        DocumentSummary(
            document: d,
            pageCount: 1,
            thumbnailPath: '/nonexistent/thumb-${d.id}.jpg')));
  }

  @override
  Future<Document> rename(int documentId, String newName) async {
    if (throwOnRename) {
      throw const DocumentRenameException('fake: rename failed');
    }
    final trimmed = newName.trim();
    renamedTo.add(trimmed);
    final i = documents.indexWhere((d) => d.id == documentId);
    final base = i >= 0
        ? documents[i]
        : Document(
            id: documentId,
            name: trimmed,
            createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
            modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42));
    final updated = Document(
      id: base.id,
      name: trimmed,
      createdAt: base.createdAt,
      modifiedAt: base.modifiedAt,
    );
    if (i >= 0) documents[i] = updated;
    return updated;
  }

  @override
  Future<void> updatePageCorners(
      int documentId, int position, CropCorners corners) async {
    if (throwOnUpdate) {
      throw DocumentSaveException('fake: update failed');
    }
    lastUpdatedPosition = position;
    lastUpdatedCorners = corners;
  }
}
```

- [ ] **Step 4: Run tests to verify compilation succeeds**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/mobile && flutter test 2>&1 | tail -5
```

Expected: all previously passing tests still pass; no compile errors.

- [ ] **Step 5: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/lib/features/library/document_repository.dart \
        apps/mobile/test/support/fake_library.dart
git commit -m "feat(e3): updatePageCorners interface + FakeDocumentRepository stub"
```

---

### Task 2: `DriftDocumentRepository.updatePageCorners`

**Files:**
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Test: `apps/mobile/test/features/library/drift_document_repository_test.dart`

**Interfaces:**
- Consumes: `DocumentRepository.updatePageCorners` (Task 1), `_warper.warp(Uint8List, CropCorners)`, `_fileStore.absoluteFor(String)`, `_fileStore.flatRelativeFor(int, int)`, `_fileStore.writeRelative(String, List<int>)`, `CropCorners.fullFrame`, `CropCorners.toStorage()`, `PagesCompanion`
- Produces: working `updatePageCorners` implementation; 4 passing unit tests

- [ ] **Step 1: Write the four failing tests**

Open `apps/mobile/test/features/library/drift_document_repository_test.dart`. Add after the closing `}` of the `'E2 — warp on save'` group (around line 443), before the final `}` of `main()`:

```dart
  group('E3 — updatePageCorners', () {
    test('non-fullFrame corners: flat written to disk and DB updated', () async {
      final fakeFlat = Uint8List.fromList([0xFF, 0xD8, 0x03]);
      // Create document with NO flat (FakeImageWarper returns null by default).
      final doc = await repo().createFromCapture(capture);
      final before = await repo().getDocumentPages(doc.id);
      expect(before.single.flatImagePath, isNull);

      const newCorners = CropCorners(
        topLeft: Offset(0.05, 0.05),
        topRight: Offset(0.95, 0.05),
        bottomRight: Offset(0.95, 0.95),
        bottomLeft: Offset(0.05, 0.95),
      );
      await repo(warper: FakeImageWarper(returnValue: fakeFlat))
          .updatePageCorners(doc.id, 1, newCorners);

      final flatFile =
          File('${base.path}/documents/${doc.id}/page_1_flat.jpg');
      expect(flatFile.existsSync(), isTrue);
      expect(flatFile.readAsBytesSync(), fakeFlat);

      final after = await repo().getDocumentPages(doc.id);
      expect(after.single.flatImagePath, flatFile.path);
      expect(after.single.corners, newCorners);
    });

    test('fullFrame corners: flat file deleted and DB cleared', () async {
      final fakeFlat = Uint8List.fromList([0xFF, 0xD8, 0x04]);
      const initCorners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );
      // Create document WITH a flat.
      final doc = await repo(warper: FakeImageWarper(returnValue: fakeFlat))
          .createFromCapture(capture, corners: initCorners);
      final flatFile =
          File('${base.path}/documents/${doc.id}/page_1_flat.jpg');
      expect(flatFile.existsSync(), isTrue, reason: 'pre-condition: flat exists');

      // Re-edit to fullFrame.
      await repo().updatePageCorners(doc.id, 1, CropCorners.fullFrame);

      expect(flatFile.existsSync(), isFalse,
          reason: 'flat file must be deleted on fullFrame reset');
      final after = await repo().getDocumentPages(doc.id);
      expect(after.single.flatImagePath, isNull);
      expect(after.single.corners, CropCorners.fullFrame);
    });

    test('warp throws: method rethrows and DB is unchanged', () async {
      final doc = await repo().createFromCapture(capture);
      const badCorners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );

      await expectLater(
        repo(warper: FakeImageWarper(throws: true))
            .updatePageCorners(doc.id, 1, badCorners),
        throwsA(isA<WarpException>()),
      );

      // DB must remain unchanged: no flatRelativePath set.
      final after = await repo().getDocumentPages(doc.id);
      expect(after.single.flatImagePath, isNull,
          reason: 'rethrow must not update DB');
    });

    test('unknown page: throws DocumentSaveException', () async {
      await expectLater(
        repo().updatePageCorners(99999, 1, CropCorners.fullFrame),
        throwsA(isA<DocumentSaveException>()),
      );
    });
  });
```

Also add `import 'package:mobile/features/library/image_warper.dart';` to the test imports if not already present (it is — `WarpException` is in `image_warper.dart`).

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/mobile && \
  flutter test test/features/library/drift_document_repository_test.dart 2>&1 | tail -15
```

Expected: 4 new tests fail with "Unimplemented" or similar (the interface method is not yet implemented in `DriftDocumentRepository`).

- [ ] **Step 3: Implement `updatePageCorners` in `DriftDocumentRepository`**

Open `apps/mobile/lib/features/library/drift/drift_document_repository.dart`. Add the following method after `rename` (before the `_defaultName` helper):

```dart
  @override
  Future<void> updatePageCorners(
      int documentId, int position, CropCorners corners) async {
    final page = await (_db.select(_db.pages)
          ..where((t) =>
              t.documentId.equals(documentId) & t.position.equals(position)))
        .getSingleOrNull();
    if (page == null) {
      throw DocumentSaveException(
          'updatePageCorners: no page ($documentId, $position)');
    }

    if (corners == CropCorners.fullFrame) {
      final flatRel = page.flatRelativePath;
      if (flatRel != null) {
        try {
          await _fileStore.absoluteFor(flatRel).delete();
        } on FileSystemException {/* already gone — fine */}
      }
      await (_db.update(_db.pages)
            ..where((t) =>
                t.documentId.equals(documentId) & t.position.equals(position)))
          .write(PagesCompanion(
              corners: const Value<String?>(null),
              flatRelativePath: const Value<String?>(null)));
      return;
    }

    // Non-fullFrame: read original JPEG, warp, write flat, update row.
    final bytes =
        await _fileStore.absoluteFor(page.relativeImagePath).readAsBytes();
    final flat = await _warper.warp(bytes, corners);
    if (flat == null) return; // warper returned null — fullFrame guarded above, no-op here
    final flatRel = _fileStore.flatRelativeFor(documentId, position);
    await _fileStore.writeRelative(flatRel, flat);
    await (_db.update(_db.pages)
          ..where((t) =>
              t.documentId.equals(documentId) & t.position.equals(position)))
        .write(PagesCompanion(
            corners: Value(corners.toStorage()),
            flatRelativePath: Value(flatRel)));
  }
```

Note: `File.readAsBytes()` returns `Uint8List` directly; no conversion needed.
Note: `const PagesCompanion(corners: Value(null), flatRelativePath: Value(null))` — Drift's `Value(null)` for nullable text columns sets the column to SQL NULL.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/mobile && \
  flutter test test/features/library/drift_document_repository_test.dart 2>&1 | tail -10
```

Expected: all tests in the file pass (existing + 4 new E3 tests).

- [ ] **Step 5: Run full suite**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light && \
  pnpm nx run mobile:test --skip-nx-cache 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/lib/features/library/drift/drift_document_repository.dart \
        apps/mobile/test/features/library/drift_document_repository_test.dart
git commit -m "feat(e3): DriftDocumentRepository.updatePageCorners + unit tests"
```

---

### Task 3: `EditCropScreen`

**Files:**
- Create: `apps/mobile/lib/features/library/edit_crop_screen.dart`

**Interfaces:**
- Consumes: `CropOverlay` (from `lib/features/scan/widgets/crop_overlay.dart`), `CropCorners` (from `lib/features/library/crop_corners.dart`).
- Produces: `EditCropScreen({required String imagePath, required CropCorners initialCorners, Future<Size> Function(String) decodeImageSize = _resolveImageSize})`. Returns `CropCorners?` via `Navigator.pop` — non-null on Accept, null on Cancel.

- [ ] **Step 1: Create `edit_crop_screen.dart`**

Create `apps/mobile/lib/features/library/edit_crop_screen.dart` with this exact content:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../scan/widgets/crop_overlay.dart';
import 'crop_corners.dart';

/// Resolves the EXIF-applied natural size of the image at [path].
/// Uses the same approach as CaptureReviewScreen — the framework decoder bakes
/// the Orientation tag so this size matches the displayed image.
Future<Size> _resolveImageSize(String path) {
  final completer = Completer<Size>();
  final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) {
        completer.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
      stream.removeListener(listener);
    },
    onError: (e, st) {
      if (!completer.isCompleted) completer.completeError(e);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// Full-screen crop editor. Shows the original JPEG (at [imagePath]) with a
/// draggable [CropOverlay] seeded from [initialCorners]. Accept pops with the
/// chosen [CropCorners]; Cancel (back button) pops with null.
///
/// [decodeImageSize] is injectable for tests — defaults to [_resolveImageSize].
/// Until the size resolves, the image is shown without handles (same pattern as
/// CaptureReviewScreen). If size resolution fails, the screen stays overlay-free.
class EditCropScreen extends StatefulWidget {
  final String imagePath;
  final CropCorners initialCorners;
  final Future<Size> Function(String) decodeImageSize;

  const EditCropScreen({
    super.key,
    required this.imagePath,
    required this.initialCorners,
    this.decodeImageSize = _resolveImageSize,
  });

  @override
  State<EditCropScreen> createState() => _EditCropScreenState();
}

class _EditCropScreenState extends State<EditCropScreen> {
  late CropCorners _corners;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _corners = widget.initialCorners;
    widget.decodeImageSize(widget.imagePath).then((size) {
      if (!mounted) return;
      setState(() => _imageSize = size);
    }).catchError((_) {/* leave _imageSize null — overlay skipped, image still shown */});
  }

  Widget _imageWidget() => Image.file(
        File(widget.imagePath),
        key: const Key('edit-crop-image'),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white54, size: 64),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit crop'),
        actions: [
          TextButton(
            key: const Key('edit-crop-accept'),
            onPressed: () => Navigator.of(context).pop(_corners),
            child: const Text('Accept'),
          ),
        ],
      ),
      body: ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: size == null
              ? Center(child: _imageWidget())
              : CropOverlay(
                  imageSize: size,
                  image: _imageWidget(),
                  corners: _corners,
                  onCornersChanged: (c) => setState(() => _corners = c),
                ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/mobile && \
  flutter analyze lib/features/library/edit_crop_screen.dart 2>&1
```

Expected: `No issues found!`

- [ ] **Step 3: Run full suite to check no regressions**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light && \
  pnpm nx run mobile:test --skip-nx-cache 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/lib/features/library/edit_crop_screen.dart
git commit -m "feat(e3): EditCropScreen — crop overlay over saved original JPEG"
```

---

### Task 4: `PageViewerScreen` edit button + widget tests

**Files:**
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart`
- Modify: `apps/mobile/test/features/library/page_viewer_screen_test.dart`

**Interfaces:**
- Consumes: `EditCropScreen` (Task 3), `repository.updatePageCorners` (Task 1/2), `CropCorners` (already in scope via `page_image.dart` → `crop_corners.dart`)

- [ ] **Step 1: Write the failing widget tests**

Open `apps/mobile/test/features/library/page_viewer_screen_test.dart`.

Add `import 'package:mobile/features/library/crop_corners.dart';` to the imports section (after the existing imports).

Add the following test block at the end of `main()`, just before the final closing `}`:

```dart
  // ── E3 — re-edit crop corners ──────────────────────────────────────────

  testWidgets('edit crop: button is present, enabled, and has correct tooltip',
      (tester) async {
    await pushViewer(tester, FakeDocumentRepository());
    final btn = tester.widget<IconButton>(
        find.byKey(const Key('page-viewer-edit')));
    expect(btn.onPressed, isNotNull);
    expect(btn.tooltip, 'Edit crop');
  });

  testWidgets(
      'edit crop: accept returns corners, calls updatePageCorners, reloads viewer',
      (tester) async {
    const testCorners = CropCorners(
      topLeft: Offset(0.1, 0.1),
      topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9),
      bottomLeft: Offset(0.1, 0.9),
    );
    final repo = FakeDocumentRepository(
      pages: [
        const PageImage(
          position: 1,
          imagePath: '/nonexistent/page_1.jpg',
          corners: testCorners,
        ),
      ],
    );
    await pushViewer(tester, repo, id: 5);

    await tester.tap(find.byKey(const Key('page-viewer-edit')));
    await tester.pumpAndSettle();

    // EditCropScreen is now on top; Accept button is in AppBar (always visible).
    expect(find.byKey(const Key('edit-crop-accept')), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-crop-accept')));
    await tester.pumpAndSettle();

    expect(repo.lastUpdatedCorners, testCorners);
    expect(repo.lastUpdatedPosition, 1);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });

  testWidgets('edit crop: failure shows SnackBar and stays on viewer',
      (tester) async {
    final repo = FakeDocumentRepository(throwOnUpdate: true);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-crop-accept')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't update crop"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });

  testWidgets('edit crop is disabled in the error state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(throwOnGetPages: true));
    final btn = tester.widget<IconButton>(
        find.byKey(const Key('page-viewer-edit')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('edit crop is disabled in the empty state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(pages: const []));
    final btn = tester.widget<IconButton>(
        find.byKey(const Key('page-viewer-edit')));
    expect(btn.onPressed, isNull);
  });
```

Also update two existing tests:

**Update "all AppBar actions are disabled while an export is in flight"** (around line 182–199). After `expect(btn('page-viewer-rename').onPressed, isNull);`, add:
```dart
    expect(btn('page-viewer-edit').onPressed, isNull);
```

**Update "the AppBar actions carry screen-reader tooltips"** (around line 262–270). After `expect(tip('page-viewer-rename'), 'Rename');`, add:
```dart
    expect(tip('page-viewer-edit'), 'Edit crop');
```

- [ ] **Step 2: Run tests to see them fail**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/mobile && \
  flutter test test/features/library/page_viewer_screen_test.dart 2>&1 | tail -20
```

Expected: new E3 tests fail (button not found); existing tooltip/in-flight tests fail (missing `page-viewer-edit` key).

- [ ] **Step 3: Update `PageViewerScreen`**

Open `apps/mobile/lib/features/library/page_viewer_screen.dart`. Make the following changes:

**Add two imports** (after `import 'dart:io';`):
```dart
import 'crop_corners.dart';
import 'edit_crop_screen.dart';
```

**Add `_editCrop` method** (after `_confirmAndDelete` and before `build`):
```dart
  Future<void> _editCrop(PageImage pg) async {
    final corners = await Navigator.of(context).push<CropCorners>(
      MaterialPageRoute<CropCorners>(
        builder: (_) => EditCropScreen(
          imagePath: pg.imagePath,
          initialCorners: pg.corners,
        ),
      ),
    );
    if (corners == null || !mounted) return;
    try {
      await widget.repository.updatePageCorners(
          widget.documentId, pg.position, corners);
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update crop")),
      );
    }
  }
```

**Add the edit crop button** in the `AppBar.actions` list, between the rename and export buttons:
```dart
          IconButton(
            key: const Key('page-viewer-edit'),
            tooltip: 'Edit crop',
            icon: const Icon(Icons.crop),
            onPressed: (_loading || _error || _exporting ||
                    (_pages?.isEmpty ?? true))
                ? null
                : () => _editCrop(_pages![_current]),
          ),
```

The complete updated `build` method's AppBar actions list (replace the existing `actions:` block):
```dart
        actions: [
          IconButton(
            key: const Key('page-viewer-rename'),
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed:
                (_loading || _error || _exporting) ? null : _rename,
          ),
          IconButton(
            key: const Key('page-viewer-edit'),
            tooltip: 'Edit crop',
            icon: const Icon(Icons.crop),
            onPressed: (_loading || _error || _exporting ||
                    (_pages?.isEmpty ?? true))
                ? null
                : () => _editCrop(_pages![_current]),
          ),
          IconButton(
            key: const Key('page-viewer-export'),
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: (_loading || _error || _exporting ||
                    (_pages?.isEmpty ?? true))
                ? null
                : _exportPdf,
          ),
          IconButton(
            key: const Key('page-viewer-delete'),
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: (_loading || _error || _exporting) ? null : _confirmAndDelete,
          ),
        ],
```

- [ ] **Step 4: Run widget tests to verify they pass**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/mobile && \
  flutter test test/features/library/page_viewer_screen_test.dart 2>&1 | tail -10
```

Expected: all tests in the file pass.

- [ ] **Step 5: Run full suite**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light && \
  pnpm nx run mobile:test --skip-nx-cache 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/lib/features/library/page_viewer_screen.dart \
        apps/mobile/test/features/library/page_viewer_screen_test.dart
git commit -m "feat(e3): page viewer edit-crop button + widget tests"
```

---

### Task 5: BDD integration test

**Files:**
- Create: `apps/mobile/test/step/i_tap_the_edit_crop_button.dart`
- Create: `apps/mobile/test/step/i_tap_accept_on_the_viewer.dart`
- Create: `apps/mobile/integration_test/e3_reedit.feature`
- Create: `apps/mobile/integration_test/e3_reedit_test.dart` (generated — do not write manually)

**Interfaces:**
- Consumes: `Key('page-viewer-edit')`, `Key('edit-crop-accept')`, `Key('crop-overlay')`, `Key('crop-handle-tl')`, `Key('page-viewer-page-1')`.
- Reused steps (no changes): `i_see_the_crop_overlay.dart`, `i_drag_the_top_left_crop_corner.dart`, `i_tap_accept.dart` (taps `review-accept`), `i_see_the_page_viewer.dart`, `i_open_the_first_document.dart`.

- [ ] **Step 1: Create `i_tap_the_edit_crop_button.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> iTapTheEditCropButton(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-edit')));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 2: Create `i_tap_accept_on_the_viewer.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> iTapAcceptOnTheViewer(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('edit-crop-accept')));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 3: Create `integration_test/e3_reedit.feature`**

```gherkin
Feature: Re-edit crop
  Scenario: User re-adjusts corners on a saved document and sees the updated page
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I see the crop overlay
    And I drag the top left crop corner
    And I tap Accept
    Then I see a saved document on the home
    When I open the first document
    Then I see the page viewer
    When I tap the edit crop button
    Then I see the crop overlay
    When I drag the top left crop corner
    And I tap Accept on the viewer
    Then I see the page viewer
```

- [ ] **Step 4: Run build_runner to generate `e3_reedit_test.dart`**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/mobile && \
  dart run build_runner build 2>&1 | tail -5
```

Expected: output includes `Built with build_runner` or `build succeeded`. The file `integration_test/e3_reedit_test.dart` is created.

- [ ] **Step 5: Verify the generated file imports both new step files**

```bash
grep "i_tap_the_edit_crop_button\|i_tap_accept_on_the_viewer" \
  /Users/pablohpsilva/Documents/camscanner-light/apps/mobile/integration_test/e3_reedit_test.dart
```

Expected: both step file paths appear in the output.

- [ ] **Step 6: Run full suite**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light && \
  pnpm nx run mobile:test --skip-nx-cache 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/test/step/i_tap_the_edit_crop_button.dart \
        apps/mobile/test/step/i_tap_accept_on_the_viewer.dart \
        apps/mobile/integration_test/e3_reedit.feature \
        apps/mobile/integration_test/e3_reedit_test.dart
git commit -m "test(e3): BDD re-edit crop scenario + step definitions"
```

---

### Task 6: `scripts/verify/e3.sh`

**Files:**
- Create: `scripts/verify/e3.sh`

**Interfaces:**
- Consumes: `scripts/verify/lib.sh` (shared helpers: `assert_file_has`, `assert_cmd`, `assert_coverage_floor`, `verify_integration_android`, `verify_integration_ios`, `fail`, `pass`, `verify_summary`).

- [ ] **Step 1: Check `lib.sh` path**

```bash
ls /Users/pablohpsilva/Documents/camscanner-light/scripts/verify/lib.sh
```

Expected: file exists.

- [ ] **Step 2: Create `scripts/verify/e3.sh`**

```bash
#!/usr/bin/env bash
# Verify E3 (re-edit crop corners) acceptance criteria.
# VERIFY_SKIP_DEVICE=1  — skips device launches (reported FAIL, never silent).
# REAL_DEVICE=1         — Tier-3 manual lane (open saved doc, re-edit corners, confirm new flat).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== E3 verification =="

require_tool flutter
require_tool pnpm
require_tool git

# ── Interface ──────────────────────────────────────────────────────────────
assert_file_has "updatePageCorners on DocumentRepository interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "updatePageCorners"

# ── DriftDocumentRepository implementation ────────────────────────────────
assert_file_has "updatePageCorners implemented in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "updatePageCorners"

assert_file_has "fullFrame branch: flat file delete in impl" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "CropCorners.fullFrame"

# ── EditCropScreen ─────────────────────────────────────────────────────────
assert_file_has "EditCropScreen class exists" \
  "apps/mobile/lib/features/library/edit_crop_screen.dart" \
  "class EditCropScreen"

assert_file_has "edit-crop-accept key in EditCropScreen" \
  "apps/mobile/lib/features/library/edit_crop_screen.dart" \
  "edit-crop-accept"

assert_file_has "CropOverlay used in EditCropScreen" \
  "apps/mobile/lib/features/library/edit_crop_screen.dart" \
  "CropOverlay("

# ── PageViewerScreen wiring ────────────────────────────────────────────────
assert_file_has "edit_crop_screen imported in viewer" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "edit_crop_screen"

assert_file_has "page-viewer-edit key in viewer" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-edit"

assert_file_has "_editCrop method in viewer" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "_editCrop"

# ── DIP check: viewer does not import PerspectiveWarper ───────────────────
if grep -q "perspective_warper" \
    "apps/mobile/lib/features/library/page_viewer_screen.dart" 2>/dev/null; then
  fail "PerspectiveWarper imported by viewer — DIP violation"
else
  pass "DIP: PerspectiveWarper not imported by viewer"
fi

# ── Test helpers ───────────────────────────────────────────────────────────
assert_file_has "FakeDocumentRepository.updatePageCorners stub" \
  "apps/mobile/test/support/fake_library.dart" \
  "updatePageCorners"

assert_file_has "lastUpdatedCorners tracking field in fake" \
  "apps/mobile/test/support/fake_library.dart" \
  "lastUpdatedCorners"

assert_file_has "throwOnUpdate flag in fake" \
  "apps/mobile/test/support/fake_library.dart" \
  "throwOnUpdate"

# ── BDD steps ──────────────────────────────────────────────────────────────
assert_file_has "i_tap_the_edit_crop_button taps page-viewer-edit" \
  "apps/mobile/test/step/i_tap_the_edit_crop_button.dart" \
  "page-viewer-edit"

assert_file_has "i_tap_accept_on_the_viewer taps edit-crop-accept" \
  "apps/mobile/test/step/i_tap_accept_on_the_viewer.dart" \
  "edit-crop-accept"

# ── Feature + generated test ───────────────────────────────────────────────
assert_file_has "e3 feature file exists" \
  "apps/mobile/integration_test/e3_reedit.feature" \
  "Re-edit crop"

assert_file_has "e3 generated test file exists" \
  "apps/mobile/integration_test/e3_reedit_test.dart" \
  "Re-edit crop"

# ── Generated code current ─────────────────────────────────────────────────
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"

assert_cmd "no uncommitted generated diff" "" \
  bash -c "git diff --exit-code -- \
    apps/mobile/integration_test/e3_reedit_test.dart \
    >/dev/null 2>&1 && echo OK \
    || (echo 'GENERATED FILES STALE'; exit 1)"

# ── Suite ──────────────────────────────────────────────────────────────────
assert_cmd "unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ── Device ─────────────────────────────────────────────────────────────────
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android e3_reedit_test.dart
verify_integration_ios e3_reedit_test.dart

# ── Opt-in REAL_DEVICE Tier-3 ─────────────────────────────────────────────
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "MANUAL: Capture an angled document, accept with adjusted corners."
  echo "Open the document; confirm flat image is shown."
  echo "Tap Edit crop. Adjust at least one corner. Accept."
  echo "Verify the page viewer now shows the newly re-warped flat image."
  echo "Tap Edit crop again; drag all corners to fullFrame positions. Accept."
  echo "Verify the original (un-warped) image is shown."
fi

verify_summary
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x /Users/pablohpsilva/Documents/camscanner-light/scripts/verify/e3.sh
```

- [ ] **Step 4: Run with `VERIFY_SKIP_DEVICE=1` to confirm static assertions pass**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light && \
  VERIFY_SKIP_DEVICE=1 bash scripts/verify/e3.sh 2>&1
```

Expected: all static assertions `PASS`; `DEVICE CHECKS SKIPPED` printed; `VERIFY FAILED` at the end (because device check is skipped, which is the correct fail-closed behavior — not a problem).

- [ ] **Step 5: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add scripts/verify/e3.sh
git commit -m "test(e3): verify/e3.sh — static asserts + suite + integration gate"
```
