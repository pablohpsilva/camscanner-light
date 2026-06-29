# C1 — Single-page PDF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Export-to-PDF action on a saved document generates a 1-page, metadata-clean, lossless, EXIF-auto-oriented PDF to on-device storage, with a pluggable text-layer seam for future OCR.

**Architecture:** A pure `PdfBuilder` (List<PageImage> → PDF bytes) using the `pdf` package — which embeds the JPEG losslessly (`/DCTDecode`, verbatim bytes) **and auto-orients from EXIF** (spike-confirmed), so no manual orientation code. The repository gains `exportPdf(documentId)` (orchestrates build + write), injected with the builder like `scrubber`/`fileStore`/`clock`. The B3 `PageViewerScreen` gains the Export action; it calls `repository.exportPdf` exactly like `deleteDocument`.

**Tech Stack:** Flutter 3.44.4, `pdf: ^3.11.1` (pure-Dart, on-device, version-pinned because orientation is delegated to it), Drift, `bdd_widget_test`, Nx.

## Global Constraints

- **Privacy spine (binding):** PDF generated **on-device** only — no cloud, no network. Metadata-clean **by construction** (default `pw.Document()` sets no info dict).
- **Lossless:** the stored JPEG is embedded **verbatim** (`/DCTDecode`, no decode/re-encode). `pw.MemoryImage` does this and auto-orients from EXIF — **do not** add manual orientation logic (it would double-correct).
- **No schema change:** `schemaVersion` stays **1**; the PDF is regenerated on demand to `documents/<id>/export.pdf` (no DB record).
- **`pdf` pinned to `^3.11.1`** — orientation correctness is delegated to it.
- **Host-test image hazard:** host tests never load a real `Image.file`; PDF host tests read the committed fixture bytes directly (no widget rendering).
- **REAL_DEVICE deferred-with-sign-off:** pixel-level upright/legibility (criterion 7) is the opt-in `REAL_DEVICE=1` lane, not gated.
- **Personal `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` stays uncommitted** — never `git add` it.

---

## File Structure

**Create:**
- `apps/mobile/lib/features/library/pdf/pdf_text_layer.dart` — `PdfTextLayer` + `ImageOnlyTextLayer`.
- `apps/mobile/lib/features/library/pdf/pdf_builder.dart` — `PdfBuilder` (pure).
- `apps/mobile/test/features/library/pdf/pdf_builder_test.dart` — builder unit tests.
- `apps/mobile/integration_test/c1_export_pdf.feature` — Tier-2 scenario (+ generated `_test.dart`).
- `apps/mobile/test/step/i_export_the_open_document_to_pdf.dart`
- `apps/mobile/test/step/the_pdf_is_saved.dart`
- `scripts/verify/c1.sh`.

**Modify:**
- `apps/mobile/pubspec.yaml` — add `pdf: ^3.11.1`.
- `apps/mobile/lib/features/library/document_file_store.dart` — `pdfRelativeFor`.
- `apps/mobile/lib/features/library/document_repository.dart` — `exportPdf` + `DocumentExportException` + `dart:io` import.
- `apps/mobile/lib/features/library/drift/drift_document_repository.dart` — `exportPdf` + `_pdfBuilder` field/ctor param.
- `apps/mobile/lib/features/library/library_dependencies.dart` — pass `pdfBuilder` in `_defaultCreateRepository`.
- `apps/mobile/test/support/fake_library.dart` — fake `exportPdf` + `throwOnExport`/`exportedIds`; pass `pdfBuilder` in `tempLibraryDependencies`/`persistentLibraryDependencies`.
- `apps/mobile/test/features/library/drift_document_repository_test.dart` — `repo()` helper + `exportPdf` tests.
- `apps/mobile/lib/features/library/page_viewer_screen.dart` — Export action + `_exportPdf`.
- `apps/mobile/test/features/library/page_viewer_screen_test.dart` — export tests.

**Reused as-is:** the committed `test/fixtures/landscape_exif6.jpg` (200×100 raw, EXIF Orientation 6); B1 capture/save steps + B3 `i_open_the_first_document` (Tier-2).

---

## Task 1: `PdfBuilder` + `PdfTextLayer` seam (the pure unit)

**Files:**
- Create: `apps/mobile/lib/features/library/pdf/pdf_text_layer.dart`
- Create: `apps/mobile/lib/features/library/pdf/pdf_builder.dart`
- Modify: `apps/mobile/pubspec.yaml`
- Test: `apps/mobile/test/features/library/pdf/pdf_builder_test.dart`

**Interfaces:**
- Consumes (existing): `PageImage { int position; String imagePath }`; committed fixture `test/fixtures/landscape_exif6.jpg`.
- Produces: `class PdfTextLayer { List<pw.Widget> overlayFor(PageImage page) }`; `class ImageOnlyTextLayer implements PdfTextLayer`; `class PdfBuilder { const PdfBuilder({PdfTextLayer textLayer}); Future<Uint8List> build(List<PageImage> pages, {bool compress = true}) }`.

- [ ] **Step 1: Add the `pdf` dependency**

In `apps/mobile/pubspec.yaml`, add under `dependencies:` right after the `path: ^1.9.0` line:

```yaml
  pdf: ^3.11.1
```

Run: `cd apps/mobile && flutter pub get`
Expected: `Got dependencies!` (resolves `pdf 3.11.x`).

- [ ] **Step 2: Write the failing builder tests**

Create `apps/mobile/test/features/library/pdf/pdf_builder_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/pdf/pdf_text_layer.dart';
import 'package:pdf/widgets.dart' as pw;

// A spy text layer: records the pages it was asked about and returns a fixed overlay.
class _SpyTextLayer implements PdfTextLayer {
  final List<PageImage> calls = [];
  final List<pw.Widget> overlay;
  _SpyTextLayer({this.overlay = const []});
  @override
  List<pw.Widget> overlayFor(PageImage page) {
    calls.add(page);
    return overlay;
  }
}

bool _containsBytes(Uint8List hay, Uint8List needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) { ok = false; break; }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  const fixturePath = 'test/fixtures/landscape_exif6.jpg';
  final jpeg = File(fixturePath).readAsBytesSync();
  PageImage page() => const PageImage(position: 1, imagePath: fixturePath);
  String dec(Uint8List b) => latin1.decode(b, allowInvalid: true);

  test('builds a valid single-page PDF', () async {
    final pdf = await const PdfBuilder().build([page()]);
    final s = dec(pdf);
    expect(s.startsWith('%PDF-'), isTrue);
    // robust page count: /Type /Page NOT followed by 's' (avoid /Pages)
    expect(RegExp(r'/Type\s*/Page(?![s])').allMatches(s).length, 1);
  });

  test('embeds the JPEG losslessly (DCTDecode + verbatim bytes)', () async {
    final pdf = await const PdfBuilder().build([page()]);
    expect(dec(pdf).contains('/DCTDecode'), isTrue);
    expect(
      _containsBytes(pdf, jpeg.sublist(jpeg.length - 60, jpeg.length - 20)),
      isTrue,
      reason: 'raw JPEG bytes must be embedded verbatim (no re-encode)',
    );
  });

  test('auto-orients: EXIF-6 200x100 fixture -> oriented page 100x200', () async {
    final pdf = await const PdfBuilder().build([page()]);
    final m = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)')
        .firstMatch(dec(pdf))!;
    expect(double.parse(m.group(1)!), 100, reason: 'oriented width');
    expect(double.parse(m.group(2)!), 200, reason: 'oriented height');
  });

  test('metadata-clean: no personal/device info (author/producer/creator/date)',
      () async {
    final s = dec(await const PdfBuilder().build([page()]));
    // NOTE: the pdf package emits a fixed '% .../dart_pdf' tool-attribution
    // header comment (unsuppressible, non-personal — accepted, like /ID). We
    // assert only that PERSONAL/DEVICE metadata is absent.
    for (final marker in ['/Author', '/Producer', '/Creator', '/CreationDate']) {
      expect(s.contains(marker), isFalse, reason: 'metadata leak: $marker');
    }
  });

  test('seam: overlayFor invoked per page; text injected; none when image-only',
      () async {
    final spy = _SpyTextLayer(overlay: [pw.Text('SEAMTEXT')]);
    // compress:false so the (otherwise deflated) overlay text is greppable.
    final pdf = await PdfBuilder(textLayer: spy).build([page()], compress: false);
    expect(spy.calls.single.position, 1, reason: 'overlayFor called with the page');
    expect(dec(pdf).contains('SEAMTEXT'), isTrue, reason: 'injected text present');

    final imageOnly =
        await const PdfBuilder().build([page()], compress: false);
    expect(dec(imageOnly).contains('SEAMTEXT'), isFalse);
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/pdf/pdf_builder_test.dart`
Expected: compile FAIL — `pdf_builder.dart` / `pdf_text_layer.dart` do not exist.

- [ ] **Step 4: Create the text-layer seam**

Create `apps/mobile/lib/features/library/pdf/pdf_text_layer.dart`:

```dart
import 'package:pdf/widgets.dart' as pw;

import '../page_image.dart';

/// Pluggable searchable-text seam. An implementation returns invisible text
/// widgets to Stack over a page's image (OCR injects these in Feature 08); the
/// image-only default returns none, with no change to PdfBuilder when OCR lands.
abstract interface class PdfTextLayer {
  List<pw.Widget> overlayFor(PageImage page);
}

/// C1 default: image-only PDFs (no text overlay).
class ImageOnlyTextLayer implements PdfTextLayer {
  const ImageOnlyTextLayer();
  @override
  List<pw.Widget> overlayFor(PageImage page) => const [];
}
```

- [ ] **Step 5: Create the builder**

Create `apps/mobile/lib/features/library/pdf/pdf_builder.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../page_image.dart';
import 'pdf_text_layer.dart';

/// Composes a document's pages into a PDF. Pure: reads each page's JPEG from
/// disk and returns the PDF bytes. The JPEG is embedded LOSSLESSLY
/// (/DCTDecode, verbatim) and auto-oriented from its EXIF tag by the pdf
/// package — so there is no manual orientation code here. The default
/// pw.Document() writes no info dict, so the output is metadata-clean.
class PdfBuilder {
  final PdfTextLayer textLayer;
  const PdfBuilder({this.textLayer = const ImageOnlyTextLayer()});

  /// [compress] is true in production; tests pass false to grep the (otherwise
  /// deflated) text overlay.
  Future<Uint8List> build(List<PageImage> pages, {bool compress = true}) async {
    final doc = pw.Document(compress: compress);
    for (final page in pages) {
      final bytes = await File(page.imagePath).readAsBytes();
      final image = pw.MemoryImage(bytes); // lossless + EXIF auto-orient
      final overlay = textLayer.overlayFor(page);
      doc.addPage(
        pw.Page(
          pageFormat:
              PdfPageFormat(image.width!.toDouble(), image.height!.toDouble()),
          build: (context) => pw.Stack(children: [pw.Image(image), ...overlay]),
        ),
      );
    }
    return doc.save();
  }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/pdf/pdf_builder_test.dart`
Expected: PASS (5/5). Every behavior here was spike-verified on `pdf 3.11.1`.

- [ ] **Step 7: Analyze**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock \
        apps/mobile/lib/features/library/pdf/pdf_text_layer.dart \
        apps/mobile/lib/features/library/pdf/pdf_builder.dart \
        apps/mobile/test/features/library/pdf/pdf_builder_test.dart
git commit -m "feat(c1): PdfBuilder + PdfTextLayer seam — lossless, auto-oriented, metadata-clean"
```

---

## Task 2: `exportPdf` (repository orchestration + file store)

**Files:**
- Modify: `apps/mobile/lib/features/library/document_file_store.dart`
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/lib/features/library/library_dependencies.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`
- Test: `apps/mobile/test/features/library/drift_document_repository_test.dart`

**Interfaces:**
- Consumes: `PdfBuilder` (Task 1); `DocumentFileStore.writeRelative`/`absoluteFor`; existing `DriftDocumentRepository` ctor `({required AppDatabase db, required ImageMetadataScrubber scrubber, required DocumentFileStore fileStore, required DateTime Function() clock})`.
- Produces: `DocumentFileStore.pdfRelativeFor(int) → String`; `DocumentRepository.exportPdf(int) → Future<File>`; `DocumentExportException`; `DriftDocumentRepository` ctor gains `required PdfBuilder pdfBuilder`; `FakeDocumentRepository` gains `throwOnExport`/`exportedIds`/`exportPdf`.

- [ ] **Step 1: Write the failing repo tests**

In `apps/mobile/test/features/library/drift_document_repository_test.dart`, add the import (with the others) and update the `repo()` helper to pass a builder, then add the tests.

Add import:
```dart
import 'package:mobile/features/library/pdf/pdf_builder.dart';
```

Change the existing `repo()` helper — add `pdfBuilder: const PdfBuilder(),`:
```dart
  DriftDocumentRepository repo({ImageMetadataScrubber? scrubber}) =>
      DriftDocumentRepository(
        db: db,
        scrubber: scrubber ?? const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: clock,
        pdfBuilder: const PdfBuilder(),
      );
```

**Also add `pdfBuilder: const PdfBuilder(),` (after the `clock:` line) to the FIVE other inline `DriftDocumentRepository(...)` constructions in this same file** — making `pdfBuilder` required would otherwise break their compilation:
- the `final r = DriftDocumentRepository(...)` in **`listDocumentSummaries returns newest first`**,
- `repo1` and `repo2` in **`Tier 1: documents persist across a DB close/reopen on disk`**,
- `repo1` and `repo2` in **`Tier 1: a delete is durable across a DB close/reopen`**.

(Find them all with `grep -n 'DriftDocumentRepository(' test/features/library/drift_document_repository_test.dart` — there are 6 constructions total; every one needs the new param.)

Add these tests inside `main()`:
```dart
  test('exportPdf writes export.pdf and returns a valid PDF file', () async {
    final doc = await repo().createFromCapture(capture);
    final file = await repo().exportPdf(doc.id);

    expect(file.path, endsWith('documents/${doc.id}/export.pdf'));
    expect(file.existsSync(), isTrue);
    final head = file.readAsBytesSync().sublist(0, 4);
    expect(head, [0x25, 0x50, 0x44, 0x46]); // %PDF
  });

  test('exportPdf throws DocumentExportException when the page file is missing',
      () async {
    // Seed a doc + page row, but never write the image file on disk.
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'noimg',
        createdAt: DateTime.utc(2026, 1, 1),
        modifiedAt: DateTime.utc(2026, 1, 1)));
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id, position: 1, relativeImagePath: 'documents/$id/page_1.jpg'));

    await expectLater(
      repo().exportPdf(id),
      throwsA(isA<DocumentExportException>()),
    );
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart`
Expected: compile FAIL — `pdfBuilder` is not a ctor param and `exportPdf` is undefined.

- [ ] **Step 3: Add `pdfRelativeFor` to the file store**

In `apps/mobile/lib/features/library/document_file_store.dart`, add after `relativeFor`:

```dart
  String pdfRelativeFor(int docId) => 'documents/$docId/export.pdf';
```

- [ ] **Step 4: Add the interface method + exception**

In `apps/mobile/lib/features/library/document_repository.dart`, add the `dart:io` import at the top:

```dart
import 'dart:io';
```

Add the method to the interface (after `deleteDocument`):
```dart
  /// Generates a PDF of [documentId] to on-device storage and returns the file.
  /// Throws [DocumentExportException] on any failure (e.g. a missing page file).
  Future<File> exportPdf(int documentId);
```

Add the exception (next to `DocumentSaveException`):
```dart
class DocumentExportException implements Exception {
  final String message;
  const DocumentExportException(this.message);
  @override
  String toString() => 'DocumentExportException: $message';
}
```

- [ ] **Step 5: Implement in the Drift repository**

In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`:

Add the import:
```dart
import '../pdf/pdf_builder.dart';
```

Add the field and ctor param. Change the field block + constructor to include `_pdfBuilder`:
```dart
  final AppDatabase _db;
  final ImageMetadataScrubber _scrubber;
  final DocumentFileStore _fileStore;
  final DateTime Function() _clock;
  final PdfBuilder _pdfBuilder;

  DriftDocumentRepository({
    required AppDatabase db,
    required ImageMetadataScrubber scrubber,
    required DocumentFileStore fileStore,
    required DateTime Function() clock,
    required PdfBuilder pdfBuilder,
  })  : _db = db, // ignore: prefer_initializing_formals
        _scrubber = scrubber, // ignore: prefer_initializing_formals
        _fileStore = fileStore, // ignore: prefer_initializing_formals
        _clock = clock, // ignore: prefer_initializing_formals
        _pdfBuilder = pdfBuilder; // ignore: prefer_initializing_formals
```

Add the method (after `deleteDocument`):
```dart
  @override
  Future<File> exportPdf(int documentId) async {
    final pages = await getDocumentPages(documentId);
    if (pages.isEmpty) {
      throw const DocumentExportException('export failed: no pages');
    }
    try {
      final bytes = await _pdfBuilder.build(pages);
      final rel = _fileStore.pdfRelativeFor(documentId);
      await _fileStore.writeRelative(rel, bytes);
      return _fileStore.absoluteFor(rel);
    } catch (e) {
      throw DocumentExportException('export failed: $e');
    }
  }
```

- [ ] **Step 6: Pass the builder in the production composition root**

In `apps/mobile/lib/features/library/library_dependencies.dart`, add the import:
```dart
import 'pdf/pdf_builder.dart';
```
and add `pdfBuilder: const PdfBuilder(),` to the `DriftDocumentRepository(...)` in `_defaultCreateRepository`:
```dart
  return DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: DocumentFileStore(docsDir),
    clock: DateTime.now,
    pdfBuilder: const PdfBuilder(),
  );
```

- [ ] **Step 7: Add the fake `exportPdf` + update the two real factories**

In `apps/mobile/test/support/fake_library.dart`:

Add the import:
```dart
import 'package:mobile/features/library/pdf/pdf_builder.dart';
```

Add fields to `FakeDocumentRepository` (next to `throwOnDelete`/`deletedIds`):
```dart
  final bool throwOnExport;
  final List<int> exportedIds = <int>[];
```
Add `this.throwOnExport = false,` to the constructor parameter list (next to `this.throwOnDelete = false,`).

Add the override (next to `deleteDocument`):
```dart
  @override
  Future<File> exportPdf(int documentId) async {
    if (throwOnExport) {
      throw const DocumentExportException('fake: export failed');
    }
    exportedIds.add(documentId);
    final f = File('${Directory.systemTemp.path}/fake-export-$documentId.pdf');
    await f.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]); // %PDF
    return f;
  }
```

Add `pdfBuilder: const PdfBuilder(),` to BOTH `tempLibraryDependencies()` and `persistentLibraryDependencies(...)`'s `DriftDocumentRepository(...)` (each currently ends with `clock: DateTime.now,`):
```dart
        clock: DateTime.now,
        pdfBuilder: const PdfBuilder(),
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart`
Expected: PASS (existing + the two new `exportPdf` tests).

- [ ] **Step 9: Full host suite + analyze (the ctor change touches every repo construction)**

Run: `cd apps/mobile && flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!` (the new required `pdfBuilder` param is supplied at **all nine** construction sites: `_defaultCreateRepository`, `tempLibraryDependencies`, `persistentLibraryDependencies`, and the **six** in `drift_document_repository_test.dart` — the `repo()` helper + five inline. A compile error here means an inline site was missed.)

- [ ] **Step 10: Commit**

```bash
git add apps/mobile/lib/features/library/document_file_store.dart \
        apps/mobile/lib/features/library/document_repository.dart \
        apps/mobile/lib/features/library/drift/drift_document_repository.dart \
        apps/mobile/lib/features/library/library_dependencies.dart \
        apps/mobile/test/support/fake_library.dart \
        apps/mobile/test/features/library/drift_document_repository_test.dart
git commit -m "feat(c1): repository.exportPdf — build + write export.pdf, graceful failure"
```

---

## Task 3: `PageViewerScreen` Export action

**Files:**
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart`
- Test: `apps/mobile/test/features/library/page_viewer_screen_test.dart`

**Interfaces:**
- Consumes: `repository.exportPdf(int) → Future<File>`; `FakeDocumentRepository(throwOnExport: ..., throwOnGetPages: ...)` with `exportedIds`.
- Produces: an Export `IconButton` keyed `page-viewer-export` in the AppBar; `_exportPdf()` showing a success/error SnackBar.

- [ ] **Step 1: Write the failing widget tests**

In `apps/mobile/test/features/library/page_viewer_screen_test.dart`, add these tests inside `main()` (reuse the existing `pushViewer` helper and `FakeDocumentRepository` import already in this file):

```dart
  testWidgets('export success shows a "PDF saved" SnackBar and stays',
      (tester) async {
    final repo = FakeDocumentRepository();
    await pushViewer(tester, repo, id: 4);

    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pumpAndSettle();

    expect(repo.exportedIds, contains(4));
    expect(find.text('PDF saved'), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });

  testWidgets('export failure shows an error SnackBar and stays',
      (tester) async {
    final repo = FakeDocumentRepository(throwOnExport: true);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't export PDF"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });

  testWidgets('export is disabled in the error state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(throwOnGetPages: true));
    expect(find.byKey(const Key('page-viewer-error')), findsOneWidget);
    final btn =
        tester.widget<IconButton>(find.byKey(const Key('page-viewer-export')));
    expect(btn.onPressed, isNull);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_screen_test.dart`
Expected: FAIL — there is no `page-viewer-export` key / `_exportPdf`.

- [ ] **Step 3: Add the Export action**

In `apps/mobile/lib/features/library/page_viewer_screen.dart`, add the Export `IconButton` to the AppBar `actions` list, BEFORE the existing delete button:

```dart
          IconButton(
            key: const Key('page-viewer-export'),
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: (_loading || _error) ? null : _exportPdf,
          ),
```

Add the method (next to `_confirmAndDelete`):

```dart
  Future<void> _exportPdf() async {
    try {
      await widget.repository.exportPdf(widget.documentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF saved')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't export PDF")),
      );
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_screen_test.dart`
Expected: PASS (existing viewer tests + the three new export tests).

- [ ] **Step 5: Analyze**

Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!` (no `use_build_context_synchronously` — `mounted` checked after the await).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/page_viewer_screen.dart \
        apps/mobile/test/features/library/page_viewer_screen_test.dart
git commit -m "feat(c1): PageViewerScreen Export-to-PDF action with success/error feedback"
```

---

## Task 4: Tier-2 integration (capture → save → open → export)

**Files:**
- Create: `apps/mobile/integration_test/c1_export_pdf.feature`
- Create: `apps/mobile/test/step/i_export_the_open_document_to_pdf.dart`
- Create: `apps/mobile/test/step/the_pdf_is_saved.dart`
- Generated: `apps/mobile/integration_test/c1_export_pdf_test.dart`

**Interfaces:**
- Consumes (reused steps, exact B1/B3 Gherkin): `Given the app is launched with camera permission granted and empty storage`, `When I tap the Scan button`, `And I tap the shutter`, `And I tap Accept` (B1 save flow → a real page image on disk), `And I open the first document` (B3).
- Produces: step functions named EXACTLY `iExportTheOpenDocumentToPdf`, `thePdfIsSaved`.

> **Why capture→save (not seed-on-disk):** `exportPdf` reads the page's real JPEG, so the document must have a real page image file. The B1 capture→save flow writes one via the actual app code (no fixture-on-device problem); the `'PDF saved'` SnackBar only appears if `exportPdf` completed, which proves the PDF was written on-device.

- [ ] **Step 1: Write the feature file**

Create `apps/mobile/integration_test/c1_export_pdf.feature`:

```gherkin
Feature: Export a document to PDF

  Scenario: Capture, save, then export the document to PDF
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    And I open the first document
    And I export the open document to PDF
    Then the PDF is saved
```

(Reuses B1's exact proven capture→save sequence — `When I tap the Scan button / And I tap the shutter / And I tap Accept` — verbatim from `b1_save_document.feature`, then B3's open step.)

- [ ] **Step 2: Write the two new step implementations**

Create `apps/mobile/test/step/i_export_the_open_document_to_pdf.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export the open document to PDF
Future<void> iExportTheOpenDocumentToPdf(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-export')));
  await tester.pumpAndSettle();
}
```

Create `apps/mobile/test/step/the_pdf_is_saved.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';

/// Usage: the PDF is saved
///
/// The success SnackBar only shows if repository.exportPdf completed — i.e. the
/// PDF was actually built from the real page image and written to device storage.
Future<void> thePdfIsSaved(WidgetTester tester) async {
  expect(find.text('PDF saved'), findsOneWidget);
}
```

- [ ] **Step 3: Generate the BDD test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `Built with build_runner` and a new `integration_test/c1_export_pdf_test.dart`.

- [ ] **Step 4: Verify the generated test wires the REAL steps (silent-stub guard)**

Run: `cat apps/mobile/integration_test/c1_export_pdf_test.dart`
Expected — `main()` calls all seven steps in order, including `iExportTheOpenDocumentToPdf(tester)` and `thePdfIsSaved(tester)`, importing the two new files from `./../test/step/`.

Run: `cd apps/mobile && git status --porcelain test/step/`
Expected: only the TWO files you authored appear as new — `i_export_the_open_document_to_pdf.dart`, `the_pdf_is_saved.dart`. If any OTHER new `test/step/*.dart` stub appears, a Gherkin step name mismatched its camelCase file — fix the name and re-generate.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/integration_test/c1_export_pdf.feature \
        apps/mobile/integration_test/c1_export_pdf_test.dart \
        apps/mobile/test/step/i_export_the_open_document_to_pdf.dart \
        apps/mobile/test/step/the_pdf_is_saved.dart
git commit -m "test(c1): Tier-2 integration — capture, save, open, export to PDF (no stub steps)"
```

---

## Task 5: `scripts/verify/c1.sh` (the C1 gate)

**Files:**
- Create: `scripts/verify/c1.sh`

**Interfaces:**
- Consumes: `scripts/verify/lib.sh` helpers (`require_tool`, `assert_file_has`, `assert_cmd`, `assert_coverage_floor`, `verify_integration_android`/`_ios`, `verify_summary`).

- [ ] **Step 1: Write the verify script**

Create `scripts/verify/c1.sh`:

```bash
#!/usr/bin/env bash
# Verify C1 (single-page PDF) acceptance criteria.
# Run: bash scripts/verify/c1.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 lane (open the PDF, confirm visually upright — manual).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== C1 verification =="

# ---- Tool preconditions ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence (static asserts) ----
assert_file_has "PdfBuilder exists" \
  "apps/mobile/lib/features/library/pdf/pdf_builder.dart" "class PdfBuilder"
assert_file_has "PdfBuilder embeds via MemoryImage (lossless + auto-orient)" \
  "apps/mobile/lib/features/library/pdf/pdf_builder.dart" "pw.MemoryImage"
assert_file_has "metadata-clean by construction (no info fields set)" \
  "apps/mobile/lib/features/library/pdf/pdf_builder.dart" "pw.Document(compress:"
assert_file_has "PdfTextLayer seam exists" \
  "apps/mobile/lib/features/library/pdf/pdf_text_layer.dart" "abstract interface class PdfTextLayer"
assert_file_has "ImageOnlyTextLayer default exists" \
  "apps/mobile/lib/features/library/pdf/pdf_text_layer.dart" "class ImageOnlyTextLayer"
assert_file_has "repository exposes exportPdf" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<File> exportPdf(int documentId)"
assert_file_has "file store has pdfRelativeFor" \
  "apps/mobile/lib/features/library/document_file_store.dart" "pdfRelativeFor"
assert_file_has "viewer wires the export action" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "page-viewer-export"
assert_file_has "pdf dependency pinned" \
  "apps/mobile/pubspec.yaml" "pdf: ^3.11.1"
assert_file_has "EXIF-6 orientation fixture is committed" \
  "apps/mobile/test/fixtures/landscape_exif6.jpg" ""
assert_file_has "no schema bump (schemaVersion stays 1)" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 1;"
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"

# ---- No-empty-stub guard: the new C1 steps are real + wired ----
assert_file_has "step: export is real (not a stub)" \
  "apps/mobile/test/step/i_export_the_open_document_to_pdf.dart" "page-viewer-export"
assert_file_has "step: pdf-is-saved is real (not a stub)" \
  "apps/mobile/test/step/the_pdf_is_saved.dart" "PDF saved"
assert_file_has "generated c1 test calls the export step" \
  "apps/mobile/integration_test/c1_export_pdf_test.dart" "iExportTheOpenDocumentToPdf(tester)"
assert_file_has "generated c1 test calls the pdf-is-saved step" \
  "apps/mobile/integration_test/c1_export_pdf_test.dart" "thePdfIsSaved(tester)"

# ---- Generated code is current ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (drift + c1 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/lib/features/library/drift/app_database.g.dart apps/mobile/integration_test/c1_export_pdf_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria: unit + widget tests, analyze, coverage ----
assert_cmd "c1 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (BDD integration test) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android c1_export_pdf_test.dart
verify_integration_ios c1_export_pdf_test.dart

# ---- Opt-in REAL_DEVICE Tier-3: open the PDF, confirm upright ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "REAL_DEVICE Tier-3 (MANUAL): export a document, then open documents/<id>/export.pdf in a PDF viewer — confirm the page renders UPRIGHT and legible, and that the file metadata has no author/producer/creator."
fi

verify_summary
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/verify/c1.sh`

- [ ] **Step 3: Static + negative-control smoke (no device)**

Run: `VERIFY_SKIP_DEVICE=1 bash scripts/verify/c1.sh; echo "exit=$?"`
Expected: the static asserts run and PASS; the run ends `GATE: FAIL` with `exit=1` (fail-closed because device checks were skipped — the correct negative control, NOT a real pass). If any STATIC assert fails, STOP and report it.

- [ ] **Step 4: Commit**

```bash
git add scripts/verify/c1.sh
git commit -m "test(c1): verification gate — static asserts, no-stub guard, integration, REAL_DEVICE lane"
```

- [ ] **Step 5: Full gate (with devices)** — run by the controller

Run: `bash scripts/verify/c1.sh`
Expected: `GATE: PASS` (exit 0) — static asserts, host tests, analyze, coverage ≥70%, Android + iOS integration all pass.

---

## Self-Review

**1. Spec coverage** (each spec section → task):
- `pdf` dependency (pinned) + `PdfBuilder` (lossless, auto-orient, metadata-clean) + `PdfTextLayer`/`ImageOnlyTextLayer` seam → Task 1 (all behaviors spike-verified).
- `DocumentFileStore.pdfRelativeFor` + `DocumentRepository.exportPdf` + `DocumentExportException` + Drift impl + composition wiring + fake → Task 2.
- `PageViewerScreen` Export action (success/error SnackBar, disabled while loading/error) → Task 3.
- Tier-2 integration + silent-stub guard → Task 4.
- Verify harness (static asserts, no-stub guard, coverage floor 70, fail-closed, REAL_DEVICE) → Task 5.
- Acceptance criteria: 1 (valid 1-page) T1/T4 · 2 (lossless) T1 · 3 (auto-orient/oriented MediaBox) T1 · 4 (metadata-clean) T1 · 5 (seam) T1 · 6 (graceful failure) T2+T3 · 7 (REAL_DEVICE upright) T5 deferred lane.
- Migration surface (interface+drift+fake+**all 9** `DriftDocumentRepository` construction sites: `_defaultCreateRepository`, `tempLibraryDependencies`, `persistentLibraryDependencies`, and the 6 in the repo test) → Task 2 Steps 1, 5–9.

**2. Placeholder scan:** none — every code step has complete code; every run step has an exact command + expected output.

**3. Type consistency:** `PdfBuilder({PdfTextLayer textLayer})` + `build(List<PageImage>, {bool compress})` identical across Tasks 1–2; `PdfTextLayer.overlayFor(PageImage) → List<pw.Widget>` matches the spy + ImageOnlyTextLayer; `exportPdf(int) → Future<File>` matches interface, Drift impl, fake, and the viewer call; `DriftDocumentRepository` ctor's new `required PdfBuilder pdfBuilder` is supplied at all **nine** construction sites (Task 2 Step 1 covers the 6 in the repo test; Steps 6–7 cover the 3 production/factory sites); keys `page-viewer-export` match between Task 3 widget + Task 4 step + Task 5 assert.

**Note (intentional refinement vs the spec sketch):** `PdfBuilder` holds `textLayer` as an injected **field** (const-constructible) and `build` takes `pages` + an optional `compress` flag, rather than the spec's indicative `build(pages, textLayer)` — field injection matches how `scrubber`/`fileStore` are injected, and `compress:false` is the verified seam-test hook (Gap G).
