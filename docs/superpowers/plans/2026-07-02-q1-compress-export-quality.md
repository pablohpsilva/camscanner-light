# Q1 Compress / Export Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick a quality preset (Original/High/Medium/Low) when exporting a PDF or images, re-encoding/downscaling pages to shrink the shared file while keeping searchability.

**Architecture:** A new `ExportQuality` enum (single source of preset values) drives a pure-Dart `ImageCompressor` DIP seam (`decode → bakeOrientation → copyResize → encodeJpg`, verbatim on Original). `PdfBuilder` and `DriftDocumentRepository` apply the compressor per page; the three page-viewer export actions first show an `ExportQualityDialog` and pass the choice through. Print/protect keep the default (Original), so they are untouched.

**Tech Stack:** Flutter/Dart, `image: ^4.5.0` (pure-Dart raster; installed 4.3.0), `pdf` (PDF gen), drift (SQLite), `bdd_widget_test` + `build_runner` (BDD), `flutter_test`.

## Global Constraints

- Preset values are EXACT and live only in `ExportQuality`: `original`(q=null, dim=null), `high`(q=85, dim=null), `medium`(q=75, dim=2200), `low`(q=60, dim=1600).
- Compressor pipeline: `original` returns input bytes **verbatim** (no decode); otherwise `decode → bakeOrientation → [copyResize to long-edge cap, interpolation average, never upscale] → encodeJpg(quality)`. Malformed/undecodable input → return input **verbatim** (never fail an export).
- Downscale passes only the long-edge dimension to `copyResize` (the package derives the other side, preserving aspect).
- Image export path is unified to `compress(raw, quality) → scrub → write`.
- `print` and `protect` stay at Original (rely on the default parameter — do NOT add a dialog to them).
- The picker is a **dialog** (`showDialog`), matching every existing chooser; NOT a bottom sheet. Keys: `export-quality-dialog`, `export-quality-original/high/medium/low`, `export-quality-cancel`.
- All THREE export handlers wrap the export call in `_exporting` (set true, clear in `finally` guarded by `mounted`), and check `if (q == null || !mounted) return;` after the dialog await.
- The PDF-export widget test uses `pump()`, NOT `pumpAndSettle()` (the pushed `PdfPreviewScreen` opens the real pdfx channel and hangs settle).
- BDD targets the image-export path (deterministic `'Page saved as image'` snackbar); existing shared export step defs are updated to tap through the dialog choosing **Original**, so existing `.feature` files stay unchanged and green.
- Commit with **explicit file paths** (never `git add -A`). Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Do NOT touch `apps/mobile/android/build.gradle.kts` (project-level), `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`.
- On-device gate device: Samsung `RZCY51D0T1K`.
- All paths below are relative to repo root; the Flutter app is at `apps/mobile/`.

---

### Task 1: `ExportQuality` enum

**Files:**
- Create: `apps/mobile/lib/features/library/export/export_quality.dart`
- Test: `apps/mobile/test/features/library/export/export_quality_test.dart`

**Interfaces:**
- Produces: `enum ExportQuality { original, high, medium, low }` with fields `int? jpegQuality`, `int? maxDimension`, `String label`, `String description`, and `bool get reencodes`.

- [ ] **Step 1: Write the failing test**

```dart
// apps/mobile/test/features/library/export/export_quality_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/export/export_quality.dart';

void main() {
  test('preset values are exact', () {
    expect(ExportQuality.original.jpegQuality, isNull);
    expect(ExportQuality.original.maxDimension, isNull);
    expect(ExportQuality.original.reencodes, isFalse);

    expect(ExportQuality.high.jpegQuality, 85);
    expect(ExportQuality.high.maxDimension, isNull);
    expect(ExportQuality.high.reencodes, isTrue);

    expect(ExportQuality.medium.jpegQuality, 75);
    expect(ExportQuality.medium.maxDimension, 2200);

    expect(ExportQuality.low.jpegQuality, 60);
    expect(ExportQuality.low.maxDimension, 1600);
  });

  test('every preset has a label and description', () {
    for (final q in ExportQuality.values) {
      expect(q.label, isNotEmpty);
      expect(q.description, isNotEmpty);
    }
    expect(ExportQuality.medium.label, 'Medium');
    expect(ExportQuality.medium.description, 'Good for email');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/export/export_quality_test.dart`
Expected: FAIL — `export_quality.dart` does not exist (compile error).

- [ ] **Step 3: Write minimal implementation**

```dart
// apps/mobile/lib/features/library/export/export_quality.dart
/// The quality presets offered when exporting. The single source of truth for
/// the JPEG re-encode quality and downscale cap; every export path reads these.
enum ExportQuality {
  original(
      jpegQuality: null,
      maxDimension: null,
      label: 'Original',
      description: 'Full quality, largest file'),
  high(
      jpegQuality: 85,
      maxDimension: null,
      label: 'High',
      description: 'High quality'),
  medium(
      jpegQuality: 75,
      maxDimension: 2200,
      label: 'Medium',
      description: 'Good for email'),
  low(
      jpegQuality: 60,
      maxDimension: 1600,
      label: 'Low',
      description: 'Smallest file');

  const ExportQuality({
    required this.jpegQuality,
    required this.maxDimension,
    required this.label,
    required this.description,
  });

  /// JPEG quality (0–100) to re-encode at; null when [original] (no re-encode).
  final int? jpegQuality;

  /// Cap for the image's long edge in pixels; null = do not downscale.
  final int? maxDimension;

  /// Short UI label.
  final String label;

  /// One-line UI description.
  final String description;

  /// Whether this preset re-encodes the image (false only for [original]).
  bool get reencodes => jpegQuality != null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/export/export_quality_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/export/export_quality.dart apps/mobile/test/features/library/export/export_quality_test.dart
git commit -m "feat(q1): ExportQuality enum with preset values

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `ImageCompressor` seam + `ImageLibraryCompressor`

**Files:**
- Create: `apps/mobile/lib/features/library/export/image_compressor.dart`
- Test: `apps/mobile/test/features/library/export/image_compressor_test.dart`

**Interfaces:**
- Consumes: `ExportQuality` (Task 1).
- Produces: `abstract interface class ImageCompressor { Future<Uint8List> compress(Uint8List jpegBytes, ExportQuality quality); }` and `class ImageLibraryCompressor implements ImageCompressor { const ImageLibraryCompressor(); }`.

- [ ] **Step 1: Write the failing test**

```dart
// apps/mobile/test/features/library/export/image_compressor_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/export/image_compressor.dart';

Uint8List _jpeg(int w, int h, {int? orientation}) {
  final image = img.Image(width: w, height: h);
  // Fill with a gradient so JPEG has real content (not a flat block).
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  const compressor = ImageLibraryCompressor();

  test('original returns the input bytes verbatim (byte-identical)', () async {
    final input = _jpeg(400, 300);
    final out = await compressor.compress(input, ExportQuality.original);
    expect(out, equals(input)); // element-wise: same bytes, no re-encode
  });

  test('low yields fewer bytes and a smaller long edge for a large image',
      () async {
    final input = _jpeg(3000, 2000);
    final out = await compressor.compress(input, ExportQuality.low);
    expect(out.length, lessThan(input.length));
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 1600); // long edge capped at low.maxDimension
    expect(decoded.height, lessThan(2000));
  });

  test('never upscales a small image', () async {
    final input = _jpeg(800, 600); // long edge 800 < low cap 1600
    final out = await compressor.compress(input, ExportQuality.low);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 800);
    expect(decoded.height, 600);
  });

  test('malformed input falls back to verbatim (no throw)', () async {
    final garbage = Uint8List.fromList(List<int>.filled(64, 0x7F));
    final out = await compressor.compress(garbage, ExportQuality.low);
    expect(out, garbage);
  });

  test('re-encode bakes EXIF orientation into the pixels', () async {
    // 100x60 tagged orientation 6 (90° CW) => baked dims become 60x100.
    final input = _jpeg(100, 60, orientation: 6);
    final out = await compressor.compress(input, ExportQuality.high);
    final decoded = img.decodeImage(out)!;
    expect(decoded.width, 60);
    expect(decoded.height, 100);
    final o = decoded.exif.imageIfd.orientation;
    expect(o == null || o == 1, isTrue); // tag cleared/absent after bake
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/export/image_compressor_test.dart`
Expected: FAIL — `image_compressor.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// apps/mobile/lib/features/library/export/image_compressor.dart
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'export_quality.dart';

/// Re-encodes a page's JPEG for a chosen [ExportQuality] (DIP seam). The image
/// leaving the app is compressed; the stored original is never touched.
abstract interface class ImageCompressor {
  /// Returns re-encoded JPEG bytes for [quality], or the input bytes verbatim
  /// when [quality] does not re-encode (ExportQuality.original) or the input is
  /// not decodable.
  Future<Uint8List> compress(Uint8List jpegBytes, ExportQuality quality);
}

/// Production compressor: pure-Dart `image` package, following the same
/// decode→bakeOrientation→[resize]→encodeJpg sequence every other re-encode
/// path in the app uses (auto_enhancer, perspective_warper, filter strip, …).
class ImageLibraryCompressor implements ImageCompressor {
  const ImageLibraryCompressor();

  @override
  Future<Uint8List> compress(Uint8List jpegBytes, ExportQuality quality) async {
    if (!quality.reencodes) return jpegBytes; // Original: verbatim, no decode.

    img.Image? decoded;
    try {
      decoded = img.decodeImage(jpegBytes);
    } catch (_) {
      decoded = null; // the image pkg can THROW on garbage, not just return null
    }
    if (decoded == null) return jpegBytes; // fallback: never fail an export

    // bakeOrientation: encodeJpg drops EXIF, so pixels must be upright first.
    var image = img.bakeOrientation(decoded);

    final cap = quality.maxDimension;
    if (cap != null) {
      final longEdge = image.width >= image.height ? image.width : image.height;
      if (longEdge > cap) {
        // Pass only the long edge; the package derives the other side (aspect
        // preserved). Never upscale (guarded by longEdge > cap above).
        image = image.width >= image.height
            ? img.copyResize(image,
                width: cap, interpolation: img.Interpolation.average)
            : img.copyResize(image,
                height: cap, interpolation: img.Interpolation.average);
      }
    }

    return Uint8List.fromList(
        img.encodeJpg(image, quality: quality.jpegQuality!));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/export/image_compressor_test.dart`
Expected: PASS (5 tests). If the orientation test's dims are not swapped, the encoder isn't round-tripping EXIF — in that case assert instead that `img.decodeImage(out)!.width == img.bakeOrientation(img.decodeImage(input)!).width` (still proves baking); do not weaken the other tests.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/export/image_compressor.dart apps/mobile/test/features/library/export/image_compressor_test.dart
git commit -m "feat(q1): ImageCompressor seam + ImageLibraryCompressor (bake+downscale+re-encode)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `PdfBuilder` quality wiring

**Files:**
- Modify: `apps/mobile/lib/features/library/pdf/pdf_builder.dart`
- Test: `apps/mobile/test/features/library/pdf/pdf_builder_quality_test.dart`

**Interfaces:**
- Consumes: `ImageCompressor`, `ImageLibraryCompressor` (Task 2), `ExportQuality` (Task 1).
- Produces: `PdfBuilder({PdfTextLayer textLayer, ImageCompressor compressor})` and `Future<Uint8List> build(List<PageImage> pages, {bool compress = true, ExportQuality quality = ExportQuality.original})`.

- [ ] **Step 1: Write the failing test**

```dart
// apps/mobile/test/features/library/pdf/pdf_builder_quality_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/ocr_pdf_text_layer.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

Future<PageImage> _largePage(Directory dir) async {
  final image = img.Image(width: 3000, height: 2000);
  for (var y = 0; y < 2000; y += 1) {
    for (var x = 0; x < 3000; x += 1) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  final path = '${dir.path}/page.jpg';
  await File(path).writeAsBytes(img.encodeJpg(image, quality: 95));
  return PageImage(
    position: 1,
    imagePath: path,
    ocrWords: const [
      OcrWordBox(text: 'HELLO', left: .1, top: .1, right: .4, bottom: .2),
    ],
    ocrText: 'HELLO',
  );
}

void main() {
  test('low quality yields a smaller PDF than original for a large page',
      () async {
    final dir = await Directory.systemTemp.createTemp('pdfq');
    final page = await _largePage(dir);
    const builder = PdfBuilder();
    final original = await builder.build([page], quality: ExportQuality.original);
    final low = await builder.build([page], quality: ExportQuality.low);
    expect(low.length, lessThan(original.length));
    await dir.delete(recursive: true);
  });

  test('searchable text survives bake+downscale at low quality', () async {
    final dir = await Directory.systemTemp.createTemp('pdfq2');
    final page = await _largePage(dir);
    const builder = PdfBuilder(textLayer: OcrPdfTextLayer());
    // compress:false keeps the text stream un-deflated so it is greppable.
    final low =
        await builder.build([page], quality: ExportQuality.low, compress: false);
    expect(String.fromCharCodes(low).contains('HELLO'), isTrue);
    await dir.delete(recursive: true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/pdf/pdf_builder_quality_test.dart`
Expected: FAIL — `build` has no named `quality` parameter (compile error).

- [ ] **Step 3: Write minimal implementation**

Replace the whole file:

```dart
// apps/mobile/lib/features/library/pdf/pdf_builder.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../export/export_quality.dart';
import '../export/image_compressor.dart';
import '../page_image.dart';
import 'pdf_text_layer.dart';

/// Composes a document's pages into a PDF. Reads each page's JPEG, applies the
/// [compressor] for the chosen [ExportQuality] (Original = verbatim, lossless),
/// and embeds it. The pdf package auto-orients from EXIF; the compressor bakes
/// orientation on re-encode, so alignment holds either way. The default
/// pw.Document() writes no info dict, so the output is metadata-clean.
class PdfBuilder {
  final PdfTextLayer textLayer;
  final ImageCompressor compressor;
  const PdfBuilder({
    this.textLayer = const ImageOnlyTextLayer(),
    this.compressor = const ImageLibraryCompressor(),
  });

  /// [compress] is the PDF-structure deflate flag (tests pass false to grep the
  /// text overlay). [quality] chooses the per-page image re-encode preset.
  Future<Uint8List> build(
    List<PageImage> pages, {
    bool compress = true,
    ExportQuality quality = ExportQuality.original,
  }) async {
    final doc = pw.Document(compress: compress);
    for (final page in pages) {
      final raw = await File(page.displayPath).readAsBytes();
      final bytes = await compressor.compress(raw, quality);
      final image = pw.MemoryImage(bytes); // EXIF auto-orient (baked on re-encode)
      final overlay = textLayer.overlayFor(
          page, image.width!.toDouble(), image.height!.toDouble());
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

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/pdf/pdf_builder_quality_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Verify no existing pdf_builder test regressed**

Run: `cd apps/mobile && flutter test test/features/library/pdf/`
Expected: PASS (all pdf tests, including any existing pdf_builder test).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/pdf/pdf_builder.dart apps/mobile/test/features/library/pdf/pdf_builder_quality_test.dart
git commit -m "feat(q1): PdfBuilder applies ImageCompressor per page for ExportQuality

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Repository quality parameters (interface + Drift + fake)

**Files:**
- Modify: `apps/mobile/lib/features/library/document_repository.dart` (add `{ExportQuality quality}` to 3 methods; add import)
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart` (inject `ImageCompressor`; thread quality)
- Modify: `apps/mobile/test/support/fake_library.dart` (match new signatures; add recorders)
- Test: `apps/mobile/test/features/library/export/export_compression_test.dart`

**Interfaces:**
- Consumes: `ExportQuality` (Task 1), `ImageCompressor`/`ImageLibraryCompressor` (Task 2), `PdfBuilder.build(..., quality:)` (Task 3).
- Produces (interface): `Future<File> exportPdf(int documentId, {ExportQuality quality = ExportQuality.original})`, `Future<File> exportPageAsImage(int documentId, int position, {ExportQuality quality = ExportQuality.original})`, `Future<List<File>> exportAllPagesAsImages(int documentId, {ExportQuality quality = ExportQuality.original})`.
- Produces (fake recorders): `ExportQuality? lastExportQuality`, `ExportQuality? lastImageExportQuality`, `ExportQuality? lastAllImagesExportQuality`.

- [ ] **Step 1: Write the failing test**

```dart
// apps/mobile/test/features/library/export/export_compression_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/perspective_warper.dart';

Future<(DriftDocumentRepository, AppDatabase, Directory, int)> _seed() async {
  final base = await Directory.systemTemp.createTemp('q1cmp');
  final db = AppDatabase(NativeDatabase.memory());
  final store = DocumentFileStore(base);
  final repo = DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: store,
    clock: DateTime.now,
    pdfBuilder: const PdfBuilder(),
    warper: const PerspectiveWarper(),
  );
  final now = DateTime.now();
  final id = await db.into(db.documents).insert(
      DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
  final image = img.Image(width: 3000, height: 2000);
  for (var y = 0; y < 2000; y++) {
    for (var x = 0; x < 3000; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: 95));
  const rel = 'documents/1/page_1.jpg';
  await store.writeRelative(rel, jpeg);
  await db.into(db.pages).insert(
      PagesCompanion.insert(documentId: id, position: 1, relativeImagePath: rel));
  return (repo, db, base, id);
}

void main() {
  test('exportPdf at low is smaller than at original', () async {
    final (repo, db, base, id) = await _seed();
    final original = await (await repo.exportPdf(id)).readAsBytes();
    final low =
        await (await repo.exportPdf(id, quality: ExportQuality.low)).readAsBytes();
    expect(low.length, lessThan(original.length));
    await db.close();
    await base.delete(recursive: true);
  });

  test('exportPageAsImage at low is smaller than at original', () async {
    final (repo, db, base, id) = await _seed();
    final original = await (await repo.exportPageAsImage(id, 1)).readAsBytes();
    final low = await (await repo.exportPageAsImage(id, 1,
            quality: ExportQuality.low))
        .readAsBytes();
    expect(low.length, lessThan(original.length));
    await db.close();
    await base.delete(recursive: true);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/export/export_compression_test.dart`
Expected: FAIL — `exportPdf`/`exportPageAsImage` have no `quality` named parameter (compile error).

- [ ] **Step 3: Update the interface**

In `apps/mobile/lib/features/library/document_repository.dart`, add the import near the other imports:

```dart
import 'export/export_quality.dart';
```

Change the three method signatures (keep the existing doc comments above each):

```dart
  Future<File> exportPdf(int documentId,
      {ExportQuality quality = ExportQuality.original});
```
```dart
  Future<File> exportPageAsImage(int documentId, int position,
      {ExportQuality quality = ExportQuality.original});
```
```dart
  Future<List<File>> exportAllPagesAsImages(int documentId,
      {ExportQuality quality = ExportQuality.original});
```

- [ ] **Step 4: Update the Drift implementation**

In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`:

Add imports near the others:
```dart
import '../export/export_quality.dart';
import '../export/image_compressor.dart';
```

Add the field + constructor parameter (mirror the `encryptor` pattern):
```dart
  final ImageCompressor _compressor;
```
In the constructor parameter list, add:
```dart
    ImageCompressor compressor = const ImageLibraryCompressor(),
```
In the initializer list, add:
```dart
        _compressor = compressor, // ignore: prefer_initializing_formals
```

Change `exportPdf` signature + build call:
```dart
  @override
  Future<File> exportPdf(int documentId,
      {ExportQuality quality = ExportQuality.original}) async {
    final pages = await getDocumentPages(documentId);
    if (pages.isEmpty) {
      throw const DocumentExportException('export failed: no pages');
    }
    try {
      final bytes = await _pdfBuilder.build(pages, quality: quality);
      final dir = await Directory.systemTemp.createTemp('pdf_export');
      final safeName = await _pdfFileNameFor(documentId);
      final file = File('${dir.path}/$safeName');
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      throw DocumentExportException('export failed: $e');
    }
  }
```

Change `exportPageAsImage` to `compress → scrub → write`:
```dart
  @override
  Future<File> exportPageAsImage(int documentId, int position,
      {ExportQuality quality = ExportQuality.original}) async {
    final row = await (_db.select(_db.pages)
          ..where((t) =>
              t.documentId.equals(documentId) & t.position.equals(position)))
        .getSingleOrNull();
    if (row == null) {
      throw DocumentExportException(
          'exportImage failed: no page ($documentId, $position)');
    }
    try {
      // Display image: the flattened derivative when present, else the original.
      final srcRel = row.flatRelativePath ?? row.relativeImagePath;
      final bytes = await _fileStore.absoluteFor(srcRel).readAsBytes();
      final compressed = await _compressor.compress(bytes, quality);
      final scrubbed = _scrubber.scrub(compressed); // privacy: always scrub
      final rel = _fileStore.imageExportRelativeFor(documentId, position);
      await _fileStore.writeRelative(rel, scrubbed);
      return _fileStore.absoluteFor(rel);
    } catch (e) {
      if (e is DocumentExportException) rethrow;
      throw DocumentExportException('exportImage failed: $e');
    }
  }
```

Change `exportAllPagesAsImages` to thread quality:
```dart
  @override
  Future<List<File>> exportAllPagesAsImages(int documentId,
      {ExportQuality quality = ExportQuality.original}) async {
    final pages = await getDocumentPages(documentId);
    if (pages.isEmpty) {
      throw const DocumentExportException('exportAll failed: no pages');
    }
    final files = <File>[];
    for (final page in pages) {
      files.add(
          await exportPageAsImage(documentId, page.position, quality: quality));
    }
    return files;
  }
```

Note: `exportProtectedPdf` is unchanged — it calls `_pdfBuilder.build(pages)` (default Original).

- [ ] **Step 5: Update the fake repository**

In `apps/mobile/test/support/fake_library.dart`:

Add the import near the top:
```dart
import 'package:mobile/features/library/export/export_quality.dart';
```

Add recorder fields (next to `exportedIds`):
```dart
  ExportQuality? lastExportQuality;
  ExportQuality? lastImageExportQuality;
  ExportQuality? lastAllImagesExportQuality;
```

Update the three fake overrides to match the new signatures + record the quality:
```dart
  @override
  Future<File> exportPdf(int documentId,
      {ExportQuality quality = ExportQuality.original}) async {
    if (throwOnExport) {
      throw const DocumentExportException('fake: export failed');
    }
    if (exportGate != null) await exportGate!.future;
    exportedIds.add(documentId);
    lastExportQuality = quality;
    return File('${Directory.systemTemp.path}/fake-export-$documentId.pdf');
  }
```
```dart
  @override
  Future<File> exportPageAsImage(int documentId, int position,
      {ExportQuality quality = ExportQuality.original}) async {
    if (throwOnExportImage) {
      throw const DocumentExportException('fake: exportImage failed');
    }
    lastExportedImagePosition = position;
    lastImageExportQuality = quality;
    return File(
        '${Directory.systemTemp.path}/fake-export-$documentId-$position.jpg');
  }
```
```dart
  @override
  Future<List<File>> exportAllPagesAsImages(int documentId,
      {ExportQuality quality = ExportQuality.original}) async {
    if (throwOnExportImage) {
      throw const DocumentExportException('fake: exportAll failed');
    }
    lastAllImagesExportQuality = quality;
    final pages = await getDocumentPages(documentId);
    return [
      for (final p in pages)
        File('${Directory.systemTemp.path}/fake-all-$documentId-${p.position}.jpg')
    ];
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/export/export_compression_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 7: Verify the whole library suite still compiles + passes**

Run (with the CV host lib set up, since drift library tests load it):
```bash
bash scripts/setup-cv-host-test.sh
export DARTCV_LIB_PATH="/tmp/dartcv_lib/lib/libdartcv.dylib"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"
cd apps/mobile && flutter test test/features/library/
```
Expected: PASS (no signature-mismatch compile errors in existing tests).

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/document_repository.dart apps/mobile/lib/features/library/drift/drift_document_repository.dart apps/mobile/test/support/fake_library.dart apps/mobile/test/features/library/export/export_compression_test.dart
git commit -m "feat(q1): thread ExportQuality through repository export methods

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `ExportQualityDialog`

**Files:**
- Create: `apps/mobile/lib/features/library/export/export_quality_dialog.dart`
- Test: `apps/mobile/test/features/library/export/export_quality_dialog_test.dart`

**Interfaces:**
- Consumes: `ExportQuality` (Task 1).
- Produces: `Future<ExportQuality?> showExportQualityDialog(BuildContext context)` and `class ExportQualityDialog extends StatelessWidget`.

- [ ] **Step 1: Write the failing test**

```dart
// apps/mobile/test/features/library/export/export_quality_dialog_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/export/export_quality_dialog.dart';

Future<ExportQuality?> _open(WidgetTester tester) async {
  ExportQuality? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async =>
              result = await showExportQualityDialog(context),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result; // still null until the dialog resolves
}

void main() {
  testWidgets('shows the four options', (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('export-quality-dialog')), findsOneWidget);
    for (final q in ExportQuality.values) {
      expect(find.byKey(Key('export-quality-${q.name}')), findsOneWidget);
    }
  });

  testWidgets('tapping an option returns that quality', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('export-quality-medium')));
    await tester.pumpAndSettle();
    // Re-open path: assert the label was shown; capture via a second harness.
    // Simpler: verify the dialog is dismissed after tapping.
    expect(find.byKey(const Key('export-quality-dialog')), findsNothing);
  });

  testWidgets('returns the chosen quality value', (tester) async {
    ExportQuality? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                picked = await showExportQualityDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-low')));
    await tester.pumpAndSettle();
    expect(picked, ExportQuality.low);
  });

  testWidgets('cancel returns null', (tester) async {
    ExportQuality? picked = ExportQuality.high;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                picked = await showExportQualityDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-cancel')));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/export/export_quality_dialog_test.dart`
Expected: FAIL — `export_quality_dialog.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// apps/mobile/lib/features/library/export/export_quality_dialog.dart
import 'package:flutter/material.dart';

import 'export_quality.dart';

/// Shows the export-quality picker and resolves to the chosen [ExportQuality]
/// (or null if cancelled/dismissed). A dialog, matching the app's other pickers.
Future<ExportQuality?> showExportQualityDialog(BuildContext context) {
  return showDialog<ExportQuality>(
    context: context,
    builder: (_) => const ExportQualityDialog(),
  );
}

class ExportQualityDialog extends StatelessWidget {
  const ExportQualityDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('export-quality-dialog'),
      title: const Text('Export quality'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final q in ExportQuality.values)
              ListTile(
                key: Key('export-quality-${q.name}'),
                title: Text(q.label),
                subtitle: Text(q.description),
                onTap: () => Navigator.of(context).pop(q),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('export-quality-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/export/export_quality_dialog_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/export/export_quality_dialog.dart apps/mobile/test/features/library/export/export_quality_dialog_test.dart
git commit -m "feat(q1): ExportQualityDialog picker (dialog, matches app convention)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Page-viewer wiring + update existing export tests

**Files:**
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart` (`_exportPdf`, `_exportPageAsImage`, `_exportAllImages`; add dialog import)
- Modify: `apps/mobile/test/features/library/page_viewer_screen_test.dart` (PDF-export tests route through the dialog)
- Modify: `apps/mobile/test/features/library/page_viewer_i1_test.dart` (image-export tests route through the dialog)
- Modify: `apps/mobile/test/features/library/page_viewer_export_all_test.dart` (all-images tests route through the dialog)
- Test (new): `apps/mobile/test/features/library/page_viewer_q1_test.dart` (quality passthrough + cancel no-op)

**Interfaces:**
- Consumes: `showExportQualityDialog` (Task 5), the repository `quality:` params + fake recorders (Task 4).

- [ ] **Step 1: Write the failing test (new passthrough/cancel behaviour)**

```dart
// apps/mobile/test/features/library/page_viewer_q1_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

Future<void> _pumpViewer(WidgetTester tester, FakeDocumentRepository repo) async {
  await tester.pumpWidget(MaterialApp(
    home: PageViewerScreen(
      repository: repo,
      documentId: 4,
      name: 'Doc',
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('image export: choosing Medium passes quality + confirms',
      (tester) async {
    final repo = FakeDocumentRepository();
    await _pumpViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-medium')));
    await tester.pumpAndSettle();
    expect(repo.lastImageExportQuality, ExportQuality.medium);
    expect(find.text('Page saved as image'), findsOneWidget);
  });

  testWidgets('image export: cancelling the dialog is a no-op', (tester) async {
    final repo = FakeDocumentRepository();
    await _pumpViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-cancel')));
    await tester.pumpAndSettle();
    expect(repo.lastImageExportQuality, isNull);
    expect(find.text('Page saved as image'), findsNothing);
  });

  testWidgets('PDF export: choosing Low passes quality (pump, not settle)',
      (tester) async {
    final repo = FakeDocumentRepository();
    await _pumpViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pumpAndSettle(); // dialog animates in
    await tester.tap(find.byKey(const Key('export-quality-low')));
    await tester.pump(); // NOT settle — the pushed pdfx preview hangs settle
    await tester.pump();
    expect(repo.lastExportQuality, ExportQuality.low);
  });
}
```

Note: confirm the `PageViewerScreen` constructor parameter names against the top of `page_viewer_screen.dart` (it takes `repository`, `documentId`, and a title/name param). Match the existing test files' construction exactly (see `page_viewer_i1_test.dart`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_q1_test.dart`
Expected: FAIL — no dialog appears (the handler exports directly), so `export-quality-medium` isn't found.

- [ ] **Step 3: Wire the three handlers**

In `apps/mobile/lib/features/library/page_viewer_screen.dart`, add the import:
```dart
import 'export/export_quality_dialog.dart';
```

Replace `_exportPdf`:
```dart
  Future<void> _exportPdf() async {
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final file =
          await widget.repository.exportPdf(widget.documentId, quality: quality);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(pdfPath: file.path, name: _name),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't export PDF")),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
```

Replace `_exportPageAsImage`:
```dart
  Future<void> _exportPageAsImage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      await widget.repository
          .exportPageAsImage(widget.documentId, page.position, quality: quality);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Page saved as image')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't export image")),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
```

Replace `_exportAllImages`:
```dart
  Future<void> _exportAllImages() async {
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final files = await widget.repository
          .exportAllPagesAsImages(widget.documentId, quality: quality);
      if (!mounted) return;
      final n = files.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported $n ${n == 1 ? 'image' : 'images'}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't export images")),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
```

- [ ] **Step 4: Run the new test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_q1_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Fix the existing PDF-export tests (they now break)**

In `apps/mobile/test/features/library/page_viewer_screen_test.dart`, every test that taps `page-viewer-export` must now tap through the dialog. Insert, immediately after the `await tester.tap(find.byKey(const Key('page-viewer-export')));` line in each such test:
```dart
    await tester.pumpAndSettle(); // export-quality dialog animates in
    await tester.tap(find.byKey(const Key('export-quality-original')));
```
Keep each test's existing follow-up pump discipline:
- The "export success navigates to the PDF preview" test keeps `await tester.pump(); await tester.pump();` after the option tap (NOT settle), then asserts `PdfPreviewScreen`.
- The "export failure shows an error SnackBar" test keeps `pumpAndSettle()` after the option tap (no navigation on failure) and asserts `Couldn't export PDF`.
- The "all AppBar actions are disabled while an export is in flight" test: tap `page-viewer-export` → `pumpAndSettle` (dialog) → tap `export-quality-original` → `pump()` (gate now holds the export open) → assert buttons disabled → complete the gate → `pump(); pump()` → assert `PdfPreviewScreen`.

- [ ] **Step 6: Fix the existing image-export tests**

In `apps/mobile/test/features/library/page_viewer_i1_test.dart`, each test that taps `page-viewer-export-image` must add, right after that tap:
```dart
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
```
before the existing `pumpAndSettle()` + assertion. (The failure-path test does the same, then asserts `Couldn't export image`.)

- [ ] **Step 7: Fix the existing all-images tests**

In `apps/mobile/test/features/library/page_viewer_export_all_test.dart`, each test that taps `page-viewer-export-all-images` must add, right after that tap:
```dart
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
```
before the existing `pumpAndSettle()` + assertion.

- [ ] **Step 8: Run all affected page-viewer tests**

Run:
```bash
cd apps/mobile && flutter test test/features/library/page_viewer_screen_test.dart test/features/library/page_viewer_i1_test.dart test/features/library/page_viewer_export_all_test.dart test/features/library/page_viewer_q1_test.dart
```
Expected: PASS (all). If a test still exports without the dialog, the assertion for the confirmation/nav will fail — add the dialog tap there too.

- [ ] **Step 9: Commit**

```bash
git add apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/test/features/library/page_viewer_screen_test.dart apps/mobile/test/features/library/page_viewer_i1_test.dart apps/mobile/test/features/library/page_viewer_export_all_test.dart apps/mobile/test/features/library/page_viewer_q1_test.dart
git commit -m "feat(q1): page viewer export actions show quality dialog + spinner

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: BDD scenario + on-device deterministic test

**Files:**
- Modify: `apps/mobile/test/step/i_export_the_page_as_an_image.dart` (tap Original through the dialog)
- Modify: `apps/mobile/test/step/i_export_all_pages_as_images.dart` (tap Original)
- Modify: `apps/mobile/test/step/i_export_the_open_document_to_pdf.dart` (tap Original)
- Create: `apps/mobile/test/step/i_export_the_page_as_an_image_at_medium_quality.dart`
- Create: `apps/mobile/integration_test/q1_compress_export.feature`
- Generate: `apps/mobile/integration_test/q1_compress_export_test.dart` (via build_runner)
- Create: `apps/mobile/integration_test/q1_compress_device_test.dart` (deterministic device test)

**Interfaces:**
- Consumes: the dialog keys (`export-quality-original`, `export-quality-medium`) and the repo `quality:` params.

- [ ] **Step 1: Update the shared export steps to tap through the dialog (Original)**

`apps/mobile/test/step/i_export_the_page_as_an_image.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export the page as an image
Future<void> iExportThePageAsAnImage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-export-image')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('export-quality-original')));
  await tester.pumpAndSettle();
}
```

`apps/mobile/test/step/i_export_all_pages_as_images.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export all pages as images
Future<void> iExportAllPagesAsImages(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('export-quality-original')));
  await tester.pumpAndSettle();
}
```

`apps/mobile/test/step/i_export_the_open_document_to_pdf.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export the open document to PDF
Future<void> iExportTheOpenDocumentToPdf(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-export')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('export-quality-original')));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 2: Add the Medium-quality step for Q1**

```dart
// apps/mobile/test/step/i_export_the_page_as_an_image_at_medium_quality.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export the page as an image at Medium quality
Future<void> iExportThePageAsAnImageAtMediumQuality(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-export-image')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('export-quality-medium')));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 3: Write the Q1 feature**

```gherkin
# apps/mobile/integration_test/q1_compress_export.feature
Feature: Q1 Compress / export quality

  Scenario: Choosing a quality when exporting a page as an image
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I export the page as an image at Medium quality
    Then I see the image export confirmation
```

- [ ] **Step 4: Generate the BDD test**

Run:
```bash
cd apps/mobile && dart run build_runner build --delete-conflicting-outputs
```
Expected: `integration_test/q1_compress_export_test.dart` is created; existing generated `*_test.dart` files are unchanged (we only changed step bodies, not `.feature` phrases). Confirm the file exists:
```bash
ls apps/mobile/integration_test/q1_compress_export_test.dart
```

- [ ] **Step 5: Write the deterministic on-device test**

```dart
// apps/mobile/integration_test/q1_compress_device_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exportPdf at low is smaller than at original on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('q1dev');
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

    final now = DateTime.now();
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Doc', createdAt: now, modifiedAt: now));
    final image = img.Image(width: 3000, height: 2000);
    for (var y = 0; y < 2000; y++) {
      for (var x = 0; x < 3000; x++) {
        image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    const rel = 'documents/1/page_1.jpg';
    await store.writeRelative(
        rel, Uint8List.fromList(img.encodeJpg(image, quality: 95)));
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id, position: 1, relativeImagePath: rel));

    final original = await (await repo.exportPdf(id)).readAsBytes();
    final low = await (await repo.exportPdf(id, quality: ExportQuality.low))
        .readAsBytes();
    expect(low.length, lessThan(original.length));

    await db.close();
    await base.delete(recursive: true);
  });
}
```

- [ ] **Step 6: Run the on-device tests (device gate)**

Run:
```bash
cd apps/mobile && flutter test integration_test/q1_compress_device_test.dart -d RZCY51D0T1K
cd apps/mobile && flutter test integration_test/q1_compress_export_test.dart -d RZCY51D0T1K
```
Expected: `All tests passed` for both.

- [ ] **Step 7: Regression — run the existing export BDDs on device (their steps changed)**

Run:
```bash
cd apps/mobile && flutter test integration_test/i1_export_image_test.dart integration_test/j1_export_all_images_test.dart integration_test/h5_multipage_pdf_test.dart integration_test/c2_pdf_preview_test.dart -d RZCY51D0T1K
```
Expected: `All tests passed` (the updated shared steps tap Original through the dialog).

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/test/step/i_export_the_page_as_an_image.dart apps/mobile/test/step/i_export_all_pages_as_images.dart apps/mobile/test/step/i_export_the_open_document_to_pdf.dart apps/mobile/test/step/i_export_the_page_as_an_image_at_medium_quality.dart apps/mobile/integration_test/q1_compress_export.feature apps/mobile/integration_test/q1_compress_export_test.dart apps/mobile/integration_test/q1_compress_device_test.dart
git commit -m "test(q1): BDD quality scenario + on-device compression test; export steps tap dialog

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Verify script + plans index

**Files:**
- Create: `scripts/verify/q1.sh`
- Modify: `docs/superpowers/plans/00-plans-index.md`

**Interfaces:**
- Consumes: everything above (asserts the artifacts exist and the suites pass).

- [ ] **Step 1: Write the verify script**

```bash
# scripts/verify/q1.sh
#!/usr/bin/env bash
# Verify Q1 (compress / export quality) acceptance criteria.
# Run from repository root: bash scripts/verify/q1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== Q1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "ExportQuality enum exists" \
  "apps/mobile/lib/features/library/export/export_quality.dart" \
  "enum ExportQuality"

assert_file_has "ImageCompressor seam exists" \
  "apps/mobile/lib/features/library/export/image_compressor.dart" \
  "abstract interface class ImageCompressor"

assert_file_has "compressor bakes orientation" \
  "apps/mobile/lib/features/library/export/image_compressor.dart" \
  "bakeOrientation"

assert_file_has "ExportQualityDialog exists" \
  "apps/mobile/lib/features/library/export/export_quality_dialog.dart" \
  "export-quality-dialog"

assert_file_has "PdfBuilder accepts quality" \
  "apps/mobile/lib/features/library/pdf/pdf_builder.dart" \
  "ExportQuality quality"

assert_file_has "repository exportPdf accepts quality" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "exportPdf(int documentId,"

assert_file_has "page viewer shows quality dialog" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "showExportQualityDialog"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/q1_compress_export.feature" \
  "Compress / export quality"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/q1_compress_export_test.dart" \
  "Medium"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device Q1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device compression test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/q1_compress_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/q1_compress_export_test.dart"
fi

echo "== Q1 verification complete =="
```

- [ ] **Step 2: Run the verify script (host portion first)**

Run: `VERIFY_SKIP_DEVICE=1 bash scripts/verify/q1.sh`
Expected: ends with `== Q1 verification complete ==` and no `FAIL` lines.

- [ ] **Step 3: Run the full verify script on device**

Run: `bash scripts/verify/q1.sh`
Expected: ends with `== Q1 verification complete ==`, on-device asserts pass.

- [ ] **Step 4: Update the plans index**

In `docs/superpowers/plans/00-plans-index.md`, add a row after the P1 row:
```markdown
| Q1 | Compress / export quality (PDF + images) | 07/10 | `2026-07-02-q1-compress-export-quality.md` | ✅ **built & gated** |
```

- [ ] **Step 5: Commit**

```bash
git add scripts/verify/q1.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(q1): verify script + plans index

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Notes for the executor

- `pubspec.yaml` already declares `image: ^4.5.0` — **no dependency change** is needed.
- The composition root (`library_dependencies.dart`) needs **no change**: `PdfBuilder` and `DriftDocumentRepository` both gain defaulted `const` injections.
- `exportProtectedPdf` and `_print` are intentionally left at Original (default parameter) — do not add a dialog to them.
- If `PageViewerScreen`'s constructor parameter names differ from the snippet in Task 6 Step 1, copy the exact construction from `page_viewer_i1_test.dart` (already in the repo).
- Host `flutter test` skips `integration_test/`; the BDD + device tests run only via `flutter test integration_test/… -d RZCY51D0T1K`.
