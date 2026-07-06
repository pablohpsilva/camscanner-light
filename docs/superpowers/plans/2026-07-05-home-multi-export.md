# Home Multi-Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user long-press to select one or more documents on the home screen and export them as PDF — merged into one PDF, or as separate PDFs bundled in a `.zip`.

**Architecture:** A selection mode on `HomeScreen` drives a contextual app bar with an Export action. Two new repository methods build the artifacts (`exportCombinedPdf`, `exportSeparatePdfs`) reusing the existing `PdfBuilder` and temp-file discipline. A new injectable `FileArchiver` zips the separate PDFs. Everything is handed to the existing multi-file `ShareChannel`.

**Tech Stack:** Flutter, Drift, the `pdf` package (via `PdfBuilder`), `archive` (zip), `share_plus` (via `ShareChannel`).

## Global Constraints

- Nothing leaves the device except through the user-driven OS share sheet; export artifacts go to `Directory.systemTemp` (temp discipline), never the backed-up store.
- TDD: every task writes a failing test first, then the minimal implementation. Commit after each task.
- DRY / YAGNI / KISS / SOLID. No export-quality picker for this flow (uses `ExportQuality.original`, matching the current home-screen single-doc Share).
- The choice dialog appears only for **2+** selected documents; a single selection exports one PDF directly.
- "Separate files" = one PDF per document bundled into a single `.zip` (zip is the only separate option — no loose multi-file share).
- Work happens in the worktree at `.claude/worktrees/home-multi-export`; all paths below are relative to `apps/mobile/` within it. Run tests with `flutter test <path>` from `apps/mobile/`.
- `archive` is promoted to a **direct** dependency at `^4.0.9` (already resolved transitively).

---

## File Structure

- `lib/features/library/file_archiver.dart` — **new.** `FileArchiver` interface + `SystemFileArchiver` (only file importing `archive`).
- `lib/features/library/document_repository.dart` — **modify.** Add `exportCombinedPdf` / `exportSeparatePdfs` to the interface.
- `lib/features/library/drift/drift_document_repository.dart` — **modify.** Implement the two methods.
- `lib/features/library/widgets/documents_list_view.dart` — **modify.** Add selection-mode rendering.
- `lib/features/library/widgets/export_choice_dialog.dart` — **new.** `MultiExportChoice` enum + `showExportChoiceDialog`.
- `lib/features/library/library_dependencies.dart` — **modify.** Add `archiver` field.
- `lib/features/library/home_screen.dart` — **modify.** Selection state, contextual app bar, `_exportSelected` orchestration.
- `pubspec.yaml` — **modify.** Add `archive: ^4.0.9`.
- Tests: `test/features/library/file_archiver_test.dart`, `export_combined_pdf_test.dart`, `export_separate_pdfs_test.dart`, `documents_list_view_test.dart` (extend), `export_choice_dialog_test.dart`, `home_multi_export_test.dart` (new). `test/support/fake_library.dart` (extend with the two repo methods + `FakeFileArchiver`).

---

## Task 1: FileArchiver (zip helper)

**Files:**
- Modify: `pubspec.yaml` (add `archive: ^4.0.9` under `dependencies`, alphabetically near `animations`/`archive`)
- Create: `lib/features/library/file_archiver.dart`
- Test: `test/features/library/file_archiver_test.dart`

**Interfaces:**
- Produces: `abstract interface class FileArchiver { Future<File> zip(List<File> files, {required String archiveName, required List<String> entryNames}); }` and `class SystemFileArchiver implements FileArchiver { const SystemFileArchiver(); }`.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:`, add:

```yaml
  archive: ^4.0.9
```

Then run:

```bash
flutter pub get
```
Expected: `Got dependencies!`

- [ ] **Step 2: Write the failing test**

Create `test/features/library/file_archiver_test.dart`:

```dart
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/file_archiver.dart';

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('archiver');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  Future<File> tmp(String name, String content) async {
    final f = File('${base.path}/$name');
    await f.writeAsString(content);
    return f;
  }

  test('zips files into a temp .zip whose entries round-trip', () async {
    final a = await tmp('a.pdf', 'AAA');
    final b = await tmp('b.pdf', 'BBB');

    final zip = await const SystemFileArchiver().zip(
      [a, b],
      archiveName: 'documents.zip',
      entryNames: const ['Report.pdf', 'Invoice.pdf'],
    );

    expect(zip.path, endsWith('documents.zip'));
    expect(zip.path.startsWith(Directory.systemTemp.path), isTrue);
    expect(await zip.exists(), isTrue);

    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.map((f) => f.name), ['Report.pdf', 'Invoice.pdf']);
    expect(String.fromCharCodes(archive.files[0].content as List<int>), 'AAA');
    expect(String.fromCharCodes(archive.files[1].content as List<int>), 'BBB');
  });

  test('de-duplicates colliding entry names with a numeric suffix', () async {
    final a = await tmp('a.pdf', 'AAA');
    final b = await tmp('b.pdf', 'BBB');

    final zip = await const SystemFileArchiver().zip(
      [a, b],
      archiveName: 'documents.zip',
      entryNames: const ['Report.pdf', 'Report.pdf'],
    );

    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.map((f) => f.name), ['Report.pdf', 'Report (2).pdf']);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/features/library/file_archiver_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'mobile/features/library/file_archiver.dart'` (file not created yet).

- [ ] **Step 4: Write the minimal implementation**

Create `lib/features/library/file_archiver.dart`:

```dart
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Bundles files into a single zip archive. Injectable (DIP) so tests use a
/// recording fake instead of touching the filesystem. Mirrors [ShareChannel]:
/// a small, single-purpose channel that keeps its third-party dependency
/// ([archive]) from leaking into the rest of the app.
abstract interface class FileArchiver {
  /// Zips [files] into a single temp `.zip` named [archiveName] and returns it.
  /// [entryNames] gives the in-zip filename for each file (same length/order as
  /// [files]); colliding names are de-duplicated with a numeric suffix. The
  /// producer of [files] is responsible for their contents being share-safe.
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames});
}

/// Production archiver backed by the `archive` package. The only file in the
/// app that imports `archive`.
class SystemFileArchiver implements FileArchiver {
  const SystemFileArchiver();

  @override
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames}) async {
    final archive = Archive();
    final used = <String>{};
    for (var i = 0; i < files.length; i++) {
      final bytes = await files[i].readAsBytes();
      archive.addFile(ArchiveFile.bytes(_dedup(entryNames[i], used), bytes));
    }
    final encoded = ZipEncoder().encodeBytes(archive);
    final dir = await Directory.systemTemp.createTemp('zip_export');
    final file = File('${dir.path}/$archiveName');
    await file.writeAsBytes(encoded);
    return file;
  }

  /// Returns [name] if unused, else appends " (2)", " (3)", … before the
  /// extension until unique. Records the winner in [used].
  String _dedup(String name, Set<String> used) {
    if (used.add(name)) return name;
    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    for (var n = 2;; n++) {
      final candidate = '$stem ($n)$ext';
      if (used.add(candidate)) return candidate;
    }
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/features/library/file_archiver_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/library/file_archiver.dart test/features/library/file_archiver_test.dart
git commit -m "feat(library): add FileArchiver zip helper"
```

---

## Task 2: Repository methods — exportCombinedPdf & exportSeparatePdfs

**Files:**
- Modify: `lib/features/library/document_repository.dart` (add two methods to the `DocumentRepository` interface, after `exportAllPagesAsImages`)
- Modify: `lib/features/library/drift/drift_document_repository.dart` (implement, after `exportPdf`)
- Modify: `test/support/fake_library.dart` (add the two methods to `FakeDocumentRepository` so the interface stays satisfied)
- Test: `test/features/library/export_combined_pdf_test.dart`, `test/features/library/export_separate_pdfs_test.dart`

**Interfaces:**
- Consumes: existing `getDocumentPages(int)`, `exportPdf(int)`, injected `PdfBuilder.build(List<PageImage>)`.
- Produces:
  - `Future<File> exportCombinedPdf(List<int> documentIds)` — one PDF of every page of every doc, list order then position order; throws `DocumentExportException` on empty list or zero total pages.
  - `Future<List<File>> exportSeparatePdfs(List<int> documentIds)` — one PDF per id in order; throws `DocumentExportException` on empty list.

- [ ] **Step 1: Write the failing tests**

Create `test/features/library/export_combined_pdf_test.dart`:

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
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

/// Records the page list handed to the PDF builder so tests can assert the
/// combined export's page count and order without parsing a PDF.
class RecordingPdfBuilder extends PdfBuilder {
  final List<List<PageImage>> calls = <List<PageImage>>[];
  RecordingPdfBuilder();

  @override
  Future<Uint8List> build(List<PageImage> pages,
      {bool compress = true,
      ExportQuality quality = ExportQuality.original}) async {
    calls.add(List<PageImage>.of(pages));
    return Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46, 0x0A]); // "%PDF\n"
  }
}

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;
  late RecordingPdfBuilder pdf;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('combined');
    db = AppDatabase(NativeDatabase.memory());
    store = DocumentFileStore(base);
    pdf = RecordingPdfBuilder();
    repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: pdf,
      warper: const HybridWarper(),
    );
  });

  tearDown(() async {
    await db.close();
    if (await base.exists()) await base.delete(recursive: true);
  });

  Uint8List jpeg() =>
      Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));

  Future<int> seedDoc(String name, int pageCount) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: name, createdAt: now, modifiedAt: now));
    for (var pos = 1; pos <= pageCount; pos++) {
      final rel = 'documents/$id/page_$pos.jpg';
      await store.writeRelative(rel, jpeg());
      await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id,
          position: pos,
          relativeImagePath: rel,
          flatRelativePath: const Value(null)));
    }
    return id;
  }

  test('concatenates all pages across documents in list then position order',
      () async {
    final a = await seedDoc('A', 2);
    final b = await seedDoc('B', 3);

    final file = await repo.exportCombinedPdf([a, b]);

    expect(file.path, endsWith('.pdf'));
    expect(file.path.startsWith(Directory.systemTemp.path), isTrue);
    expect(await file.exists(), isTrue);

    final built = pdf.calls.single;
    expect(built.length, 5);
    expect(built.map((p) => p.imagePath), [
      '${base.path}/documents/$a/page_1.jpg',
      '${base.path}/documents/$a/page_2.jpg',
      '${base.path}/documents/$b/page_1.jpg',
      '${base.path}/documents/$b/page_2.jpg',
      '${base.path}/documents/$b/page_3.jpg',
    ]);
  });

  test('throws on an empty document list', () async {
    expect(() => repo.exportCombinedPdf(const []),
        throwsA(isA<DocumentExportException>()));
  });

  test('throws when no selected document has any page', () async {
    final empty = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Empty', createdAt: DateTime.now(), modifiedAt: DateTime.now()));
    expect(() => repo.exportCombinedPdf([empty]),
        throwsA(isA<DocumentExportException>()));
  });
}
```

Create `test/features/library/export_separate_pdfs_test.dart`:

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
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('separate');
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

  Future<int> seedDoc(String name) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: name, createdAt: now, modifiedAt: now));
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, jpeg());
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id,
        position: 1,
        relativeImagePath: rel,
        flatRelativePath: const Value(null)));
    return id;
  }

  test('returns one PDF file per document in list order', () async {
    final a = await seedDoc('Report');
    final b = await seedDoc('Invoice');

    final files = await repo.exportSeparatePdfs([a, b]);

    expect(files.length, 2);
    expect(files[0].path, endsWith('Report.pdf'));
    expect(files[1].path, endsWith('Invoice.pdf'));
    for (final f in files) {
      expect(await f.exists(), isTrue);
      expect(f.path.startsWith(Directory.systemTemp.path), isTrue);
    }
  });

  test('throws on an empty document list', () async {
    expect(() => repo.exportSeparatePdfs(const []),
        throwsA(isA<DocumentExportException>()));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/library/export_combined_pdf_test.dart test/features/library/export_separate_pdfs_test.dart`
Expected: FAIL — compile error: `The method 'exportCombinedPdf' isn't defined` / `exportSeparatePdfs` (interface + impl missing).

- [ ] **Step 3: Add the methods to the interface**

In `lib/features/library/document_repository.dart`, immediately after the `exportAllPagesAsImages` declaration (the method ending `...ExportQuality quality = ExportQuality.original});`), add:

```dart
  /// Builds ONE PDF containing every page of every document in [documentIds]
  /// (documents in list order; pages in position order) and returns it as a
  /// temporary file (same temp-file discipline as [exportPdf]). Nothing leaves
  /// the device. Throws [DocumentExportException] when [documentIds] is empty
  /// or none of the documents has any page.
  Future<File> exportCombinedPdf(List<int> documentIds);

  /// Exports each document in [documentIds] as its own PDF (delegating to
  /// [exportPdf] per id), returning the temporary files in list order. Nothing
  /// leaves the device. Throws [DocumentExportException] when [documentIds] is
  /// empty or any per-document export fails.
  Future<List<File>> exportSeparatePdfs(List<int> documentIds);
```

- [ ] **Step 4: Implement in the Drift repository**

In `lib/features/library/drift/drift_document_repository.dart`, immediately after the `exportPdf` method (the one ending with its `catch (e) { throw DocumentExportException('export failed: $e'); } }`), add:

```dart
  @override
  Future<File> exportCombinedPdf(List<int> documentIds) async {
    if (documentIds.isEmpty) {
      throw const DocumentExportException('combined export failed: no documents');
    }
    final pages = <PageImage>[];
    for (final id in documentIds) {
      pages.addAll(await getDocumentPages(id));
    }
    if (pages.isEmpty) {
      throw const DocumentExportException('combined export failed: no pages');
    }
    try {
      final bytes = await _pdfBuilder.build(pages);
      final dir = await Directory.systemTemp.createTemp('pdf_combined');
      final file = File('${dir.path}/documents.pdf');
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      if (e is DocumentExportException) rethrow;
      throw DocumentExportException('combined export failed: $e');
    }
  }

  @override
  Future<List<File>> exportSeparatePdfs(List<int> documentIds) async {
    if (documentIds.isEmpty) {
      throw const DocumentExportException('separate export failed: no documents');
    }
    final files = <File>[];
    for (final id in documentIds) {
      files.add(await exportPdf(id));
    }
    return files;
  }
```

- [ ] **Step 5: Add the methods to the fake repository (keep the build green)**

In `test/support/fake_library.dart`, inside `class FakeDocumentRepository`, add these fields near the other recorders (e.g. after `final List<int> exportedIds = <int>[];`):

```dart
  final List<List<int>> combinedExports = <List<int>>[];
  final List<List<int>> separateExports = <List<int>>[];
```

Then add these methods inside the class (e.g. right after the existing `exportPdf` override):

```dart
  @override
  Future<File> exportCombinedPdf(List<int> documentIds) async {
    if (throwOnExport) {
      throw const DocumentExportException('fake: combined export failed');
    }
    if (exportGate != null) await exportGate!.future;
    combinedExports.add(List<int>.of(documentIds));
    return File('${Directory.systemTemp.path}/fake-combined.pdf');
  }

  @override
  Future<List<File>> exportSeparatePdfs(List<int> documentIds) async {
    if (throwOnExport) {
      throw const DocumentExportException('fake: separate export failed');
    }
    if (exportGate != null) await exportGate!.future;
    separateExports.add(List<int>.of(documentIds));
    return [
      for (final id in documentIds)
        File('${Directory.systemTemp.path}/fake-sep-$id.pdf')
    ];
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/library/export_combined_pdf_test.dart test/features/library/export_separate_pdfs_test.dart`
Expected: PASS (5 tests total).

- [ ] **Step 7: Commit**

```bash
git add lib/features/library/document_repository.dart lib/features/library/drift/drift_document_repository.dart test/support/fake_library.dart test/features/library/export_combined_pdf_test.dart test/features/library/export_separate_pdfs_test.dart
git commit -m "feat(library): add exportCombinedPdf and exportSeparatePdfs"
```

---

## Task 3: DocumentsListView selection mode

**Files:**
- Modify: `lib/features/library/widgets/documents_list_view.dart`
- Test: `test/features/library/documents_list_view_test.dart` (append tests)

**Interfaces:**
- Produces: `DocumentsListView` gains optional params `Set<int> selectedIds = const {}`, `bool selectionMode = false`, `ValueChanged<DocumentSummary>? onToggleSelect`, `ValueChanged<DocumentSummary>? onLongPress`. In selection mode: row `onTap` routes to `onToggleSelect`; a check icon keyed `document-check-<id>` renders as trailing; the overflow menu is hidden. `onLongPress` fires on any row.

- [ ] **Step 1: Write the failing tests**

Append to `test/features/library/documents_list_view_test.dart` (inside `main()`, after the last test):

```dart
  testWidgets('long-pressing a tile invokes onLongPress with that summary',
      (tester) async {
    DocumentSummary? pressed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentsListView(
          summaries: [summary(1), summary(2)],
          onLongPress: (s) => pressed = s,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('document-tile-2')));
    expect(pressed, isNotNull);
    expect(pressed!.document.id, 2);
  });

  testWidgets('in selection mode a tap toggles selection instead of opening',
      (tester) async {
    DocumentSummary? toggled;
    DocumentSummary? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentsListView(
          summaries: [summary(1), summary(2)],
          selectionMode: true,
          selectedIds: const {1},
          onOpen: (s) => opened = s,
          onToggleSelect: (s) => toggled = s,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Check marks reflect selectedIds; the overflow menu is hidden.
    expect(find.byKey(const Key('document-check-1')), findsOneWidget);
    expect(find.byKey(const Key('document-check-2')), findsOneWidget);
    expect(find.byKey(const Key('document-menu-1')), findsNothing);

    await tester.tap(find.byKey(const Key('document-tile-2')));
    expect(toggled, isNotNull);
    expect(toggled!.document.id, 2);
    expect(opened, isNull);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/features/library/documents_list_view_test.dart`
Expected: FAIL — `No named parameter with the name 'selectionMode'` (and `onLongPress`, `onToggleSelect`, `selectedIds`).

- [ ] **Step 3: Implement selection support**

In `lib/features/library/widgets/documents_list_view.dart`, replace the class fields and constructor (the block from `final List<DocumentSummary> summaries;` through the closing `});` of the constructor) with:

```dart
  final List<DocumentSummary> summaries;
  final ValueChanged<DocumentSummary>? onOpen;
  final ValueChanged<DocumentSummary>? onRename;
  final ValueChanged<DocumentSummary>? onShare;
  final ValueChanged<DocumentSummary>? onToggleSelect;
  final ValueChanged<DocumentSummary>? onLongPress;
  final Set<int> selectedIds;
  final bool selectionMode;
  const DocumentsListView({
    super.key,
    required this.summaries,
    this.onOpen,
    this.onRename,
    this.onShare,
    this.onToggleSelect,
    this.onLongPress,
    this.selectedIds = const {},
    this.selectionMode = false,
  });
```

Then, in `build`, replace the `trailing:` argument of the `ListTile` (the whole `trailing: (onRename == null && onShare == null) ? null : PopupMenuButton<String>(...)` expression) with:

```dart
          trailing: selectionMode
              ? Icon(
                  key: Key('document-check-${d.id}'),
                  selectedIds.contains(d.id)
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selectedIds.contains(d.id)
                      ? Theme.of(context).colorScheme.primary
                      : null,
                )
              : (onRename == null && onShare == null)
                  ? null
                  : PopupMenuButton<String>(
                      key: Key('document-menu-${d.id}'),
                      tooltip: 'Document options',
                      onSelected: (v) {
                        if (v == 'rename') onRename?.call(s);
                        if (v == 'share') onShare?.call(s);
                        if (v == kShareLinkValue || v == kFaxValue) {
                          handleShareExtra(context, v);
                        }
                      },
                      itemBuilder: (context) => [
                        if (onShare != null)
                          PopupMenuItem<String>(
                            key: Key('document-share-${d.id}'),
                            value: 'share',
                            child: const Text('Share'),
                          ),
                        if (onShare != null)
                          ...shareExtraMenuItems(
                              showFax: true, keyPrefix: 'document-${d.id}'),
                        if (onRename != null)
                          PopupMenuItem<String>(
                            key: Key('document-rename-${d.id}'),
                            value: 'rename',
                            child: const Text('Rename'),
                          ),
                      ],
                    ),
```

And replace the `onTap:` argument (currently `onTap: onOpen == null ? null : () => onOpen!(s),`) with:

```dart
          onTap: selectionMode
              ? (onToggleSelect == null ? null : () => onToggleSelect!(s))
              : (onOpen == null ? null : () => onOpen!(s)),
          onLongPress:
              onLongPress == null ? null : () => onLongPress!(s),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/library/documents_list_view_test.dart`
Expected: PASS (all existing tests + 2 new).

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/widgets/documents_list_view.dart test/features/library/documents_list_view_test.dart
git commit -m "feat(library): DocumentsListView selection mode"
```

---

## Task 4: Export-choice dialog

**Files:**
- Create: `lib/features/library/widgets/export_choice_dialog.dart`
- Test: `test/features/library/export_choice_dialog_test.dart`

**Interfaces:**
- Produces: `enum MultiExportChoice { merged, separateZip }` and `Future<MultiExportChoice?> showExportChoiceDialog(BuildContext context)`. Returns `merged` (key `export-choice-merged`), `separateZip` (key `export-choice-zip`), or `null` when dismissed.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/export_choice_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/export_choice_dialog.dart';

void main() {
  Future<MultiExportChoice?> open(WidgetTester tester) async {
    late Future<MultiExportChoice?> result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => result = showExportChoiceDialog(context),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('choosing Merge returns MultiExportChoice.merged', (tester) async {
    final result = await open(tester);
    await tester.tap(find.byKey(const Key('export-choice-merged')));
    await tester.pumpAndSettle();
    expect(await result, MultiExportChoice.merged);
  });

  testWidgets('choosing Separate returns MultiExportChoice.separateZip',
      (tester) async {
    final result = await open(tester);
    await tester.tap(find.byKey(const Key('export-choice-zip')));
    await tester.pumpAndSettle();
    expect(await result, MultiExportChoice.separateZip);
  });

  testWidgets('dismissing returns null', (tester) async {
    final result = await open(tester);
    await tester.tapAt(const Offset(10, 10)); // tap the barrier
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/library/export_choice_dialog_test.dart`
Expected: FAIL — can't resolve `export_choice_dialog.dart`.

- [ ] **Step 3: Write the minimal implementation**

Create `lib/features/library/widgets/export_choice_dialog.dart`:

```dart
import 'package:flutter/material.dart';

/// How the user wants multiple selected documents exported.
enum MultiExportChoice {
  /// One combined PDF containing every page of every selected document.
  merged,

  /// One PDF per document, bundled into a single `.zip`.
  separateZip,
}

/// Asks the user how to export 2+ selected documents. Returns the chosen mode,
/// or null when dismissed. Shown only for multi-selection (a single document
/// exports directly, no dialog).
Future<MultiExportChoice?> showExportChoiceDialog(BuildContext context) {
  return showDialog<MultiExportChoice>(
    context: context,
    builder: (_) => SimpleDialog(
      key: const Key('export-choice-dialog'),
      title: const Text('Export documents'),
      children: [
        SimpleDialogOption(
          key: const Key('export-choice-merged'),
          onPressed: () =>
              Navigator.of(context).pop(MultiExportChoice.merged),
          child: const ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('Merge into one PDF'),
          ),
        ),
        SimpleDialogOption(
          key: const Key('export-choice-zip'),
          onPressed: () =>
              Navigator.of(context).pop(MultiExportChoice.separateZip),
          child: const ListTile(
            leading: Icon(Icons.folder_zip_outlined),
            title: Text('Separate PDFs (.zip)'),
          ),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/features/library/export_choice_dialog_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/library/widgets/export_choice_dialog.dart test/features/library/export_choice_dialog_test.dart
git commit -m "feat(library): export choice dialog (merge vs zip)"
```

---

## Task 5: Wire selection & export into HomeScreen

**Files:**
- Modify: `lib/features/library/library_dependencies.dart` (add `archiver` field)
- Modify: `lib/features/library/home_screen.dart` (selection state, contextual app bar, `_exportSelected`, pass selection params to `DocumentsListView`)
- Modify: `test/support/fake_library.dart` (add `FakeFileArchiver`)
- Test: `test/features/library/home_multi_export_test.dart`

**Interfaces:**
- Consumes: `exportCombinedPdf` / `exportSeparatePdfs` (Task 2), `DocumentsListView` selection params (Task 3), `showExportChoiceDialog` / `MultiExportChoice` (Task 4), `FileArchiver` (Task 1), existing `ShareChannel`.
- Produces: `LibraryDependencies` gains `final FileArchiver archiver;` (default `const SystemFileArchiver()`). `HomeScreen` gains long-press selection, a contextual app bar (`selection-close`, title `"$N selected"`, `selection-export`), and `_exportSelected()`.

- [ ] **Step 1: Add FakeFileArchiver to the test support**

In `test/support/fake_library.dart`, add this import near the other `mobile/...` imports:

```dart
import 'package:mobile/features/library/file_archiver.dart';
```

And add this class at the end of the file:

```dart
/// Recording archiver for tests: captures the last zip call, never touches the
/// filesystem. [throwOnZip] simulates a zip failure.
class FakeFileArchiver implements FileArchiver {
  int calls = 0;
  List<File>? lastFiles;
  String? lastArchiveName;
  List<String>? lastEntryNames;
  final bool throwOnZip;
  FakeFileArchiver({this.throwOnZip = false});

  @override
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames}) async {
    if (throwOnZip) throw Exception('fake: zip failed');
    calls++;
    lastFiles = files;
    lastArchiveName = archiveName;
    lastEntryNames = entryNames;
    return File('${Directory.systemTemp.path}/$archiveName');
  }
}
```

- [ ] **Step 2: Add the archiver to LibraryDependencies**

In `lib/features/library/library_dependencies.dart`:

Add the import near the other library imports:

```dart
import 'file_archiver.dart';
```

Add the field + constructor default. Change the fields block and constructor of `LibraryDependencies` so it reads:

```dart
  final DocumentRepositoryFactory createRepository;
  final DocumentPrinter printer;
  final ShareChannel share;
  final LinkShareChannel linkShare;
  final FaxProvider fax;
  final FileArchiver archiver;
  const LibraryDependencies({
    this.createRepository = _defaultCreateRepository,
    this.printer = const SystemDocumentPrinter(),
    this.share = const SystemShareChannel(),
    this.linkShare = const UnavailableLinkShareChannel(),
    this.fax = const UnavailableFaxProvider(),
    this.archiver = const SystemFileArchiver(),
  });
```

- [ ] **Step 3: Write the failing widget tests**

Create `test/features/library/home_multi_export_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/file_archiver.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/library_dependencies.dart';

import '../../support/fake_library.dart';

void main() {
  HomeScreen homeWith(
    FakeDocumentRepository repo,
    FakeShareChannel share, {
    FileArchiver? archiver,
  }) =>
      HomeScreen(
        libraryDependencies: LibraryDependencies(
          createRepository: () async => repo,
          share: share,
          archiver: archiver ?? FakeFileArchiver(),
        ),
      );

  Document doc(int id, String name) => Document(
        id: id,
        name: name,
        createdAt: DateTime.utc(2026, 7, 2),
        modifiedAt: DateTime.utc(2026, 7, 2),
      );

  Future<void> enterSelection(WidgetTester tester, int id) async {
    await tester.longPress(find.byKey(Key('document-tile-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('long-press enters selection mode with an N-selected title',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [doc(1, 'A'), doc(2, 'B')]);
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, FakeShareChannel())));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byKey(const Key('selection-export')), findsOneWidget);

    // Close clears selection and restores the normal app bar.
    await tester.tap(find.byKey(const Key('selection-close')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    expect(find.text('Documents'), findsOneWidget);
  });

  testWidgets('one selected document exports a single PDF and shares it',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [doc(1, 'A'), doc(2, 'B')]);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.exportedIds, [1]);
    expect(repo.combinedExports, isEmpty);
    expect(share.calls, 1);
    expect(share.lastFilePaths!.single, endsWith('.pdf'));
    expect(share.lastSubject, 'A');
    // Selection cleared after success.
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('2+ selected + Merge calls exportCombinedPdf then shares',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [doc(1, 'A'), doc(2, 'B')]);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    await tester.tap(find.byKey(const Key('document-tile-2')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle(); // choice dialog
    await tester.tap(find.byKey(const Key('export-choice-merged')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.combinedExports, [
      [1, 2] // display order: created desc, tie-break id asc → doc 1 then doc 2
    ]);
    expect(share.calls, 1);
    expect(share.lastFilePaths!.single, endsWith('.pdf'));
    expect(share.lastSubject, '2 documents');
  });

  testWidgets('2+ selected + Separate zips the PDFs then shares the zip',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [doc(1, 'A'), doc(2, 'B')]);
    final share = FakeShareChannel();
    final archiver = FakeFileArchiver();
    await tester
        .pumpWidget(MaterialApp(home: homeWith(repo, share, archiver: archiver)));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    await tester.tap(find.byKey(const Key('document-tile-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-choice-zip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.separateExports, [
      [1, 2]
    ]);
    expect(archiver.calls, 1);
    expect(archiver.lastArchiveName, 'documents.zip');
    expect(archiver.lastEntryNames, ['fake-sep-1.pdf', 'fake-sep-2.pdf']);
    expect(share.calls, 1);
    expect(share.lastFilePaths!.single, endsWith('documents.zip'));
  });

  testWidgets('double-tapping Export on one selection runs one export',
      (tester) async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(
        documents: [doc(1, 'A')], exportGate: gate);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pump();

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.exportedIds.length, 1);
    expect(share.calls, 1);
  });

  testWidgets('a failing export shows a share error', (tester) async {
    final repo = FakeDocumentRepository(
        documents: [doc(1, 'A'), doc(2, 'B')], throwOnExport: true);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    await tester.tap(find.byKey(const Key('document-tile-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-choice-merged')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 0);
    expect(find.text("Couldn't share"), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `flutter test test/features/library/home_multi_export_test.dart`
Expected: FAIL — no `selection-export` key / long-press does nothing (selection not implemented).

- [ ] **Step 5: Implement selection + export in HomeScreen**

In `lib/features/library/home_screen.dart`:

(a) Add imports near the others:

```dart
import 'package:path/path.dart' as p;

import 'file_archiver.dart';
import 'widgets/export_choice_dialog.dart';
```
(The `file_archiver.dart` import is only needed if referenced directly; `FileArchiver` is reached via `widget.libraryDependencies.archiver`, so `file_archiver.dart` may be unused — omit it if the analyzer flags it. `path` and `export_choice_dialog.dart` are required.)

(b) Add selection state near the other `_HomeScreenState` fields (after `bool _sharing = false;`):

```dart
  final Set<int> _selectedIds = <int>{};
  bool get _selectionMode => _selectedIds.isNotEmpty;
```

(c) Add the selection handlers and `_exportSelected` (place after `_shareDocument`):

```dart
  void _toggleSelect(DocumentSummary s) {
    setState(() {
      final id = s.document.id;
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _startSelection(DocumentSummary s) {
    setState(() => _selectedIds.add(s.document.id));
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  // The documents currently on screen, in display order (search order when
  // searching, else the active sort). Selection export follows this order.
  List<DocumentSummary> get _displayed =>
      _searching ? _summaries : sortDocuments(_summaries, _sort);

  Future<void> _exportSelected() async {
    final repo = _repository;
    if (repo == null || _sharing) return;
    final selected =
        _displayed.where((s) => _selectedIds.contains(s.document.id)).toList();
    if (selected.isEmpty) return;
    final ids = selected.map((s) => s.document.id).toList();

    MultiExportChoice? choice;
    if (ids.length >= 2) {
      choice = await showExportChoiceDialog(context);
      if (choice == null || !mounted) return;
    }

    _sharing = true;
    try {
      final share = widget.libraryDependencies.share;
      if (ids.length == 1) {
        final file = await repo.exportPdf(ids.first);
        await share.share([file.path], subject: selected.first.document.name);
      } else if (choice == MultiExportChoice.merged) {
        final file = await repo.exportCombinedPdf(ids);
        await share.share([file.path], subject: '${ids.length} documents');
      } else {
        final files = await repo.exportSeparatePdfs(ids);
        // Reuse the repo's sanitized per-doc PDF names as zip entry names (DRY).
        final entryNames = [for (final f in files) p.basename(f.path)];
        final zip = await widget.libraryDependencies.archiver
            .zip(files, archiveName: 'documents.zip', entryNames: entryNames);
        await share.share([zip.path]);
      }
      if (mounted) _clearSelection();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't share")),
      );
    } finally {
      _sharing = false;
    }
  }
```

(d) Make search exit selection: in `_openSearch`, change it to:

```dart
  void _openSearch() => setState(() {
        _selectedIds.clear();
        _searching = true;
      });
```

(e) Swap in the contextual app bar. In `build`, change the `appBar:` line to:

```dart
      appBar: _selectionMode
          ? _buildSelectionAppBar()
          : _searching
              ? _buildSearchAppBar()
              : _buildNormalAppBar(),
```

And hide the FAB during selection — change the `floatingActionButton:` condition from `_searching ? null : ...` to:

```dart
      floatingActionButton: (_searching || _selectionMode)
          ? null
          : FloatingActionButton.extended(
              onPressed: _repository == null ? null : _openScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan'),
            ),
```

(f) Add the contextual app bar builder (place next to `_buildNormalAppBar`):

```dart
  AppBar _buildSelectionAppBar() => AppBar(
        leading: IconButton(
          key: const Key('selection-close'),
          tooltip: 'Cancel selection',
          icon: const Icon(Icons.close),
          onPressed: _clearSelection,
        ),
        title: Text('${_selectedIds.length} selected'),
        actions: [
          IconButton(
            key: const Key('selection-export'),
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share),
            onPressed: _exportSelected,
          ),
        ],
      );
```

(g) Pass selection params to BOTH `DocumentsListView` call sites in `_buildBody` (the search branch and the normal branch). For each `DocumentsListView(...)`, add these arguments:

```dart
        selectionMode: _selectionMode,
        selectedIds: _selectedIds,
        onToggleSelect: _toggleSelect,
        onLongPress: _startSelection,
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/features/library/home_multi_export_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 7: Run the full library test suite to catch regressions**

Run: `flutter test test/features/library/`
Expected: PASS (all tests, including the pre-existing `home_share_test.dart`, `home_screen_test.dart`, `documents_list_view_test.dart`).

- [ ] **Step 8: Analyze**

Run: `flutter analyze lib/features/library`
Expected: `No issues found!` (remove any unused import the analyzer flags, e.g. `file_archiver.dart` in `home_screen.dart`).

- [ ] **Step 9: Commit**

```bash
git add lib/features/library/library_dependencies.dart lib/features/library/home_screen.dart test/support/fake_library.dart test/features/library/home_multi_export_test.dart
git commit -m "feat(library): multi-select PDF export from home screen"
```

---

## Manual verification (on device — host tests skip native share/zip)

After all tasks pass, verify on device (per project memory, host tests don't exercise the real share sheet or native zip):

1. Long-press a document → selection mode; select a second → title reads "2 selected".
2. Export → dialog → **Merge into one PDF** → share sheet shows one PDF containing both documents' pages in order.
3. Export → **Separate PDFs (.zip)** → share sheet shows one `documents.zip`; saved & unzipped, it contains one correctly-named PDF per document (collisions suffixed " (2)").
4. Select exactly one → Export → shares that single PDF directly (no dialog).
5. Cancel (✕) clears selection.

---

## Self-Review Notes

- **Spec coverage:** long-press select (Task 3/5), contextual app bar + N selected (Task 5), merge choice only for 2+ (Task 5 `_exportSelected`), combined PDF (Task 2), separate→zip (Tasks 1/2/5), `FileArchiver` injectable + `archive` direct dep (Task 1), share via existing `ShareChannel` (Task 5), temp discipline (Tasks 1/2), tests per component, YAGNI (no quality picker). All spec sections map to a task.
- **Type consistency:** `MultiExportChoice { merged, separateZip }`, `exportCombinedPdf(List<int>)→File`, `exportSeparatePdfs(List<int>)→List<File>`, `FileArchiver.zip(List<File>, {archiveName, entryNames})→File`, `DocumentsListView` params `selectionMode/selectedIds/onToggleSelect/onLongPress` — used identically across tasks.
- **Ordering:** `DocumentSort.initial` is `created` **desc**; the Task 5 test docs share a `createdAt`, so the tie-break (createdAt desc, then id asc) yields display order `[1, 2]`. The Task 5 tests assert `[1, 2]` accordingly. If real usage needs selection to follow tap order instead of display order, that's a future enhancement — this plan uses display order.
