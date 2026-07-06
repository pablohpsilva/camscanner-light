# Share Multiple Documents as a .zip — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user long-press to multi-select documents on the home screen and share them as a single `.zip` of per-document PDFs (a single selection shares one PDF directly).

**Architecture:** Strictly additive. A new pure-Dart `FileArchiver` zips existing per-document PDFs (produced by the already-working `exportPdf`); `ShareChannel` gains an optional `mimeType` so the zip attaches as `application/zip`; `DocumentsListView`/`HomeScreen` gain an opt-in selection mode. The DB / isolate / native path is never touched (the prior attempt's boot hang was collateral from that path, not from zipping).

**Tech Stack:** Flutter, Dart, `archive` 4.0.9 (pure-Dart zip), `share_plus`, Drift (unchanged), `bdd_widget_test`.

## Global Constraints

- Run every command from `apps/mobile/` (not the repo root).
- `flutter analyze` must stay at **zero warnings**.
- **TDD:** write the failing test first, watch it fail (red), then implement (green).
- **BDD:** the user-facing behavior gets a Gherkin `.feature` under `integration_test/`, with `bdd_widget_test`-generated `*_test.dart` and steps in `test/step/`; regenerate with `build_runner`.
- **Both platforms:** native-dependent behavior (real zip creation + real share sheet) must be proven on a **real Android device AND a real iOS device**; state the exact command + green result. Include an explicit **boot gate** (app cold-launches on both devices) — guards the latent `NativeDatabase.createInBackground` hang at `lib/features/library/drift/app_database.dart:119`.
- **`archive` pinned to `4.0.9`** — the version already resolved transitively; do NOT bump (2.2.x-style source builds / major bumps are out of scope).
- **Zip runs on the main isolate, stored (no compression)** — PDFs are already compressed; `CompressionType.none` avoids wasted CPU/jank and the app's native-assets/isolate trap.
- **Temp discipline:** all export artifacts go to `Directory.systemTemp.createTemp(...)` (matches every existing exporter); nothing is written to the persistent, backed-up store.
- Branch: `feat/share-documents-zip` (already created; the design spec is its first commit).
- Merge mode / combined-PDF and the export-choice dialog are **out of scope** (YAGNI).

---

### Task 1: `FileArchiver` + `SystemFileArchiver` (zip helper)

**Files:**
- Modify: `apps/mobile/pubspec.yaml` (promote `archive` to a direct dep)
- Create: `apps/mobile/lib/features/library/file_archiver.dart`
- Test: `apps/mobile/test/features/library/file_archiver_test.dart`

**Interfaces:**
- Consumes: nothing (leaf).
- Produces:
  - `abstract interface class FileArchiver { Future<File> zip(List<File> files, {required String archiveName, required List<String> entryNames}); }`
  - `class SystemFileArchiver implements FileArchiver { const SystemFileArchiver(); }`

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/library/file_archiver_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mobile/features/library/file_archiver.dart';

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('archiver_test');
  });
  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  Future<File> writeFile(String name, List<int> bytes) async {
    final f = File(p.join(base.path, name));
    await f.writeAsBytes(bytes);
    return f;
  }

  test('zips N files with the given entry names, round-tripping bytes', () async {
    final a = await writeFile('a.pdf', [1, 2, 3]);
    final b = await writeFile('b.pdf', [4, 5, 6, 7]);

    final zip = await const SystemFileArchiver().zip(
      [a, b],
      archiveName: 'documents.zip',
      entryNames: ['a.pdf', 'b.pdf'],
    );

    // Output is a temp .zip, not inside the source dir.
    expect(zip.path, endsWith('documents.zip'));
    expect(p.isWithin(base.path, zip.path), isFalse);

    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.map((f) => f.name).toList(), ['a.pdf', 'b.pdf']);
    expect(archive.files[0].content, equals(Uint8List.fromList([1, 2, 3])));
    expect(archive.files[1].content, equals(Uint8List.fromList([4, 5, 6, 7])));
  });

  test('stores entries uncompressed (no deflate)', () async {
    final a = await writeFile('a.pdf', List<int>.filled(1024, 42));
    final zip = await const SystemFileArchiver()
        .zip([a], archiveName: 'x.zip', entryNames: ['a.pdf']);
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.single.compression, CompressionType.none);
  });

  test('de-duplicates colliding entry names with a numeric suffix', () async {
    final a = await writeFile('one.pdf', [1]);
    final b = await writeFile('two.pdf', [2]);
    final zip = await const SystemFileArchiver().zip(
      [a, b],
      archiveName: 'dup.zip',
      entryNames: ['Doc.pdf', 'Doc.pdf'],
    );
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.map((f) => f.name).toList(), ['Doc.pdf', 'Doc (2).pdf']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/library/file_archiver_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:mobile/features/library/file_archiver.dart'` (and `archive` may be unresolved).

- [ ] **Step 3: Promote the `archive` dependency**

In `apps/mobile/pubspec.yaml`, under `dependencies:` (alphabetical, near the top), add:

```yaml
  archive: 4.0.9
```

Then run: `flutter pub get`
Expected: resolves with `archive 4.0.9` (already the transitive version — no other version changes).

- [ ] **Step 4: Write the implementation**

Create `apps/mobile/lib/features/library/file_archiver.dart`:

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
  /// [files]); colliding names are de-duplicated with a numeric suffix. Entries
  /// are STORED (no compression) — the producer's files (PDFs) are already
  /// compressed, so deflate wastes CPU for ~0 gain.
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames});
}

/// Production archiver backed by the `archive` package. The only file in the
/// app that imports `archive`. Runs on the calling (main) isolate: the input is
/// a handful of already-compressed PDFs, and staying off spawned isolates avoids
/// the app's native-assets/isolate pitfalls.
class SystemFileArchiver implements FileArchiver {
  const SystemFileArchiver();

  @override
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames}) async {
    final archive = Archive();
    final used = <String>{};
    for (var i = 0; i < files.length; i++) {
      final bytes = await files[i].readAsBytes();
      final entry = ArchiveFile.bytes(_dedup(entryNames[i], used), bytes)
        ..compression = CompressionType.none; // store; PDFs are already compressed
      archive.addFile(entry);
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

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/library/file_archiver_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/features/library/file_archiver.dart test/features/library/file_archiver_test.dart`
Expected: `No issues found!`

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock \
  apps/mobile/lib/features/library/file_archiver.dart \
  apps/mobile/test/features/library/file_archiver_test.dart
git commit -m "feat(share): FileArchiver zip helper (stored, deduped entries)"
```

---

### Task 2: `exportSeparatePdfs` repository method

**Files:**
- Modify: `apps/mobile/lib/features/library/document_repository.dart` (interface)
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart` (impl)
- Modify: `apps/mobile/test/support/fake_library.dart` (fake impl + recorder — required or the fake stops compiling)
- Test: `apps/mobile/test/features/library/export_separate_pdfs_test.dart`

**Interfaces:**
- Consumes: existing `Future<File> exportPdf(int documentId, {ExportQuality quality})`.
- Produces: `Future<List<File>> exportSeparatePdfs(List<int> documentIds)` on `DocumentRepository`; `FakeDocumentRepository.separateExportedIds` (recorded ids).

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/library/export_separate_pdfs_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
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
    base = await Directory.systemTemp.createTemp('sep_pdf');
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

  Future<int> seedDoc(String name) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: name, createdAt: now, modifiedAt: now));
    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, jpeg);
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id, position: 1, relativeImagePath: rel));
    return id;
  }

  test('exports one PDF per id, in list order, to temp', () async {
    final a = await seedDoc('Alpha');
    final b = await seedDoc('Beta');

    final files = await repo.exportSeparatePdfs([b, a]); // order preserved

    expect(files.length, 2);
    expect(p.basename(files[0].path), 'Beta.pdf');
    expect(p.basename(files[1].path), 'Alpha.pdf');
    for (final f in files) {
      expect(p.isWithin(base.path, f.path), isFalse,
          reason: 'exports must not land in the persistent, backed-up store');
      expect(await f.readAsBytes(), isNotEmpty);
    }
  });

  test('throws when documentIds is empty', () async {
    expect(() => repo.exportSeparatePdfs(const []),
        throwsA(isA<DocumentExportException>()));
  });

  test('propagates a per-document export failure', () async {
    // A document row with no page file → exportPdf throws → propagates.
    final now = DateTime.now();
    final empty = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Empty', createdAt: now, modifiedAt: now));
    expect(() => repo.exportSeparatePdfs([empty]),
        throwsA(isA<DocumentExportException>()));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/library/export_separate_pdfs_test.dart`
Expected: FAIL — `The method 'exportSeparatePdfs' isn't defined for the type 'DriftDocumentRepository'`.

- [ ] **Step 3: Add the interface method**

In `apps/mobile/lib/features/library/document_repository.dart`, immediately after the `exportPdf` declaration (around line 45), add:

```dart
  /// Exports each document in [documentIds] as its own PDF (delegating to
  /// [exportPdf] per id), returning the temp files in list order. Throws
  /// [DocumentExportException] when [documentIds] is empty or any export fails.
  Future<List<File>> exportSeparatePdfs(List<int> documentIds);
```

- [ ] **Step 4: Implement it in the Drift repository**

In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`, immediately after the `exportPdf` method (after its closing brace, ~line 371), add:

```dart
  @override
  Future<List<File>> exportSeparatePdfs(List<int> documentIds) async {
    if (documentIds.isEmpty) {
      throw const DocumentExportException('export failed: no documents');
    }
    final files = <File>[];
    for (final id in documentIds) {
      files.add(await exportPdf(id));
    }
    return files;
  }
```

- [ ] **Step 5: Implement it in the fake (keeps the fake compiling)**

In `apps/mobile/test/support/fake_library.dart`, add a recorder field next to `exportedIds` (~line 62):

```dart
  final List<List<int>> separateExportCalls = <List<int>>[];
```

Then add the method right after `exportPdf` in `FakeDocumentRepository` (after ~line 147):

```dart
  @override
  Future<List<File>> exportSeparatePdfs(List<int> documentIds) async {
    if (throwOnExport) {
      throw const DocumentExportException('fake: separate export failed');
    }
    if (documentIds.isEmpty) {
      throw const DocumentExportException('fake: no documents');
    }
    separateExportCalls.add(List<int>.unmodifiable(documentIds));
    return [
      for (final id in documentIds)
        File('${Directory.systemTemp.path}/fake-export-$id.pdf')
    ];
  }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/features/library/export_separate_pdfs_test.dart`
Expected: PASS (3 tests).

Run the full suite to confirm the interface change broke nothing:
Run: `flutter test`
Expected: PASS (all existing tests still green).

- [ ] **Step 7: Analyze + commit**

Run: `flutter analyze lib/features/library/document_repository.dart lib/features/library/drift/drift_document_repository.dart test/support/fake_library.dart test/features/library/export_separate_pdfs_test.dart`
Expected: `No issues found!`

```bash
git add apps/mobile/lib/features/library/document_repository.dart \
  apps/mobile/lib/features/library/drift/drift_document_repository.dart \
  apps/mobile/test/support/fake_library.dart \
  apps/mobile/test/features/library/export_separate_pdfs_test.dart
git commit -m "feat(library): exportSeparatePdfs — one PDF per document id"
```

---

### Task 3: `ShareChannel.mimeType`

**Files:**
- Modify: `apps/mobile/lib/features/library/share_channel.dart` (interface + `SystemShareChannel`)
- Modify: `apps/mobile/test/support/fake_library.dart` (`FakeShareChannel` records `mimeType`)
- Test: `apps/mobile/test/features/library/share_channel_mimetype_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Future<void> share(List<String> filePaths, {String? subject, String? mimeType})`; `FakeShareChannel.lastMimeType`.

> **Note:** `SystemShareChannel` forwards to `SharePlus`/`XFile`, a **native** platform channel that cannot run under `flutter test`. This task's host test verifies the recorder contract (`FakeShareChannel.lastMimeType`) that Tasks 5–7 depend on; the real `application/zip` forwarding is proven on-device in Task 7.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/library/share_channel_mimetype_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import '../../support/fake_library.dart';

void main() {
  test('records the mimeType passed to share', () async {
    final fake = FakeShareChannel();
    await fake.share(['/tmp/documents.zip'], mimeType: 'application/zip');
    expect(fake.lastMimeType, 'application/zip');
    expect(fake.lastFilePaths, ['/tmp/documents.zip']);
  });

  test('mimeType defaults to null (existing callers unchanged)', () async {
    final fake = FakeShareChannel();
    await fake.share(['/tmp/a.pdf'], subject: 'A');
    expect(fake.lastMimeType, isNull);
    expect(fake.lastSubject, 'A');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/library/share_channel_mimetype_test.dart`
Expected: FAIL — `The named parameter 'mimeType' isn't defined` / `lastMimeType` undefined.

- [ ] **Step 3: Extend the interface + production channel**

Replace the body of `apps/mobile/lib/features/library/share_channel.dart` from the abstract method through `SystemShareChannel` with:

```dart
abstract interface class ShareChannel {
  /// Shares [filePaths] via the OS share sheet, with an optional [subject]
  /// (used by targets like Mail) and an optional [mimeType] applied to every
  /// shared file (e.g. `application/zip`, so a `.zip` is not treated as opaque
  /// `application/octet-stream` and rejected). Files must already be
  /// metadata-scrubbed by their producer — this channel does not scrub (DRY).
  Future<void> share(List<String> filePaths, {String? subject, String? mimeType});
}

/// Production channel backed by the `share_plus` package. The only file in the
/// app that imports `share_plus`.
class SystemShareChannel implements ShareChannel {
  const SystemShareChannel();

  @override
  Future<void> share(List<String> filePaths,
      {String? subject, String? mimeType}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: filePaths.map((p) => XFile(p, mimeType: mimeType)).toList(),
        subject: subject,
      ),
    );
  }
}
```

- [ ] **Step 4: Extend `FakeShareChannel`**

In `apps/mobile/test/support/fake_library.dart`, update `FakeShareChannel` (~line 422):

```dart
class FakeShareChannel implements ShareChannel {
  List<String>? lastFilePaths;
  String? lastSubject;
  String? lastMimeType;
  int calls = 0;
  final bool throwOnShare;
  FakeShareChannel({this.throwOnShare = false});

  @override
  Future<void> share(List<String> filePaths,
      {String? subject, String? mimeType}) async {
    if (throwOnShare) throw Exception('fake: share failed');
    calls++;
    lastFilePaths = filePaths;
    lastSubject = subject;
    lastMimeType = mimeType;
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/library/share_channel_mimetype_test.dart`
Expected: PASS (2 tests).

Run: `flutter test`
Expected: PASS (all existing callers still compile — `mimeType` is optional).

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/features/library/share_channel.dart test/support/fake_library.dart test/features/library/share_channel_mimetype_test.dart`
Expected: `No issues found!`

```bash
git add apps/mobile/lib/features/library/share_channel.dart \
  apps/mobile/test/support/fake_library.dart \
  apps/mobile/test/features/library/share_channel_mimetype_test.dart
git commit -m "feat(share): optional mimeType on ShareChannel.share"
```

---

### Task 4: `DocumentsListView` selection mode

**Files:**
- Modify: `apps/mobile/lib/features/library/widgets/documents_list_view.dart`
- Test: `apps/mobile/test/features/library/documents_list_view_selection_test.dart`

**Interfaces:**
- Consumes: existing `DocumentSummary`.
- Produces: `DocumentsListView({... Set<int> selectedIds = const {}, bool selectionMode = false, ValueChanged<DocumentSummary>? onToggleSelect, ValueChanged<DocumentSummary>? onLongPress})`; per-row checkbox key `Key('document-check-<id>')`.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/library/documents_list_view_selection_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';

DocumentSummary _summary(int id, String name) => DocumentSummary(
      document: Document(
        id: id,
        name: name,
        createdAt: DateTime.utc(2026, 7, 6),
        modifiedAt: DateTime.utc(2026, 7, 6),
      ),
      pageCount: 1,
      thumbnailPath: '/nonexistent/thumb-$id.jpg',
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final docs = [_summary(1, 'Alpha'), _summary(2, 'Beta')];

  testWidgets('long-press reports the row without opening it', (tester) async {
    DocumentSummary? longPressed;
    DocumentSummary? opened;
    await tester.pumpWidget(_host(DocumentsListView(
      summaries: docs,
      onOpen: (s) => opened = s,
      onLongPress: (s) => longPressed = s,
    )));
    await tester.longPress(find.byKey(const Key('document-tile-1')));
    expect(longPressed?.document.id, 1);
    expect(opened, isNull);
  });

  testWidgets('in selection mode a tap toggles instead of opening', (tester) async {
    DocumentSummary? toggled;
    DocumentSummary? opened;
    await tester.pumpWidget(_host(DocumentsListView(
      summaries: docs,
      selectionMode: true,
      selectedIds: const {1},
      onOpen: (s) => opened = s,
      onToggleSelect: (s) => toggled = s,
    )));
    // Selected row shows its checkbox; overflow menu is hidden.
    expect(find.byKey(const Key('document-check-1')), findsOneWidget);
    expect(find.byKey(const Key('document-menu-1')), findsNothing);

    await tester.tap(find.byKey(const Key('document-tile-2')));
    expect(toggled?.document.id, 2);
    expect(opened, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/library/documents_list_view_selection_test.dart`
Expected: FAIL — `No named parameter with the name 'onLongPress'`.

- [ ] **Step 3: Implement the selection params**

Replace `apps/mobile/lib/features/library/widgets/documents_list_view.dart` in full:

```dart
import 'package:flutter/material.dart';

import '../document_summary.dart';
import 'document_thumbnail.dart';
import 'share_menu_button.dart';

/// Rich list of saved documents: thumbnail, name, date, page count. Rendered in
/// the order it is given — the caller (HomeScreen) applies the user's chosen
/// sort (D3). Each row has an optional overflow menu (Rename / Share) when
/// [onRename] or [onShare] is provided.
///
/// Opt-in multi-select: when [selectionMode] is true, rows show a checkbox and
/// a tap routes to [onToggleSelect] (not [onOpen]); [onLongPress] enters the
/// mode from the caller. All selection params default to a no-op so existing
/// callers and tests are unaffected.
class DocumentsListView extends StatelessWidget {
  /// Bottom scroll inset (~ one row's height) so the floating Scan button,
  /// which docks over the bottom-right of this list, never permanently covers
  /// the last row's overflow (⋮) menu — the user can scroll it into the clear.
  static const double fabBottomInset = 88;

  final List<DocumentSummary> summaries;
  final ValueChanged<DocumentSummary>? onOpen;
  final ValueChanged<DocumentSummary>? onRename;
  final ValueChanged<DocumentSummary>? onShare;
  final Set<int> selectedIds;
  final bool selectionMode;
  final ValueChanged<DocumentSummary>? onToggleSelect;
  final ValueChanged<DocumentSummary>? onLongPress;
  const DocumentsListView({
    super.key,
    required this.summaries,
    this.onOpen,
    this.onRename,
    this.onShare,
    this.selectedIds = const {},
    this.selectionMode = false,
    this.onToggleSelect,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('documents-list'),
      padding: const EdgeInsets.only(bottom: fabBottomInset),
      itemCount: summaries.length,
      itemBuilder: (context, i) {
        final s = summaries[i];
        final d = s.document;
        final selected = selectedIds.contains(d.id);
        return ListTile(
          key: Key('document-tile-${d.id}'),
          selected: selectionMode && selected,
          leading: selectionMode
              ? Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  key: Key('document-check-${d.id}'),
                  color: selected ? Theme.of(context).colorScheme.primary : null,
                )
              : DocumentThumbnail(
                  key: Key('document-thumb-${d.id}'), path: s.thumbnailPath),
          title: Text(d.name),
          subtitle: Text(
              '${_formatLocal(d.createdAt.toLocal())} · ${_pages(s.pageCount)}'),
          trailing: (selectionMode || (onRename == null && onShare == null))
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
          onLongPress: onLongPress == null ? null : () => onLongPress!(s),
          onTap: selectionMode
              ? (onToggleSelect == null ? null : () => onToggleSelect!(s))
              : (onOpen == null ? null : () => onOpen!(s)),
        );
      },
    );
  }

  String _pages(int n) => n == 1 ? '1 page' : '$n pages';

  String _formatLocal(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/library/documents_list_view_selection_test.dart`
Expected: PASS (2 tests).

Run: `flutter test test/features/library/`
Expected: PASS (existing `documents_list_view` / home tests unaffected — defaults preserve behavior).

- [ ] **Step 5: Analyze + commit**

Run: `flutter analyze lib/features/library/widgets/documents_list_view.dart test/features/library/documents_list_view_selection_test.dart`
Expected: `No issues found!`

```bash
git add apps/mobile/lib/features/library/widgets/documents_list_view.dart \
  apps/mobile/test/features/library/documents_list_view_selection_test.dart
git commit -m "feat(library): DocumentsListView opt-in selection mode"
```

---

### Task 5: HomeScreen selection mode + `_exportSelected` orchestration

**Files:**
- Modify: `apps/mobile/lib/features/library/library_dependencies.dart` (add `archiver`)
- Modify: `apps/mobile/lib/features/library/home_screen.dart` (selection state, contextual app bar, wiring, `_exportSelected`)
- Test: `apps/mobile/test/features/library/home_multi_export_test.dart`

**Interfaces:**
- Consumes: `FileArchiver`/`SystemFileArchiver` (Task 1), `exportSeparatePdfs` (Task 2), `ShareChannel.share(..., mimeType:)` (Task 3), `DocumentsListView` selection params (Task 4), existing `sortDocuments`.
- Produces: `LibraryDependencies.archiver`; home-screen keys `Key('selection-close')`, `Key('selection-export')`.

- [ ] **Step 1: Add `archiver` to `LibraryDependencies`**

In `apps/mobile/lib/features/library/library_dependencies.dart`, add the import (with the other `library` imports):

```dart
import 'file_archiver.dart';
```

Add the field + constructor default inside `LibraryDependencies` (alongside `share`):

```dart
  final FileArchiver archiver;
```

and in the `const LibraryDependencies({...})` initializer list:

```dart
    this.archiver = const SystemFileArchiver(),
```

- [ ] **Step 2: Write the failing widget tests**

Create `apps/mobile/test/features/library/home_multi_export_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/file_archiver.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/library_dependencies.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';

/// Recording archiver: captures the zip call, returns a stub file (no I/O).
class FakeFileArchiver implements FileArchiver {
  int calls = 0;
  List<String>? lastEntryNames;
  String? lastArchiveName;
  @override
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames}) async {
    calls++;
    lastArchiveName = archiveName;
    lastEntryNames = entryNames;
    return File('${Directory.systemTemp.path}/$archiveName');
  }
}

Document _doc(int id, String name) => Document(
      id: id,
      name: name,
      createdAt: DateTime.utc(2026, 7, 6, id), // distinct so sort is stable
      modifiedAt: DateTime.utc(2026, 7, 6, id),
    );

void main() {
  late FakeDocumentRepository repo;
  late FakeShareChannel share;
  late FakeFileArchiver archiver;

  LibraryDependencies deps() => LibraryDependencies(
        createRepository: () async => repo,
        share: share,
        archiver: archiver,
      );

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        dependencies: const ScanDependencies(),
        libraryDependencies: deps(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    repo = FakeDocumentRepository(
      documents: [_doc(1, 'Alpha'), _doc(2, 'Beta')],
    );
    share = FakeShareChannel();
    archiver = FakeFileArchiver();
  });

  testWidgets('long-press enters selection; title shows count; close clears',
      (tester) async {
    await pumpHome(tester);
    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('selection-close')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    expect(find.text('Documents'), findsOneWidget); // back to normal app bar
  });

  testWidgets('one selected → Export shares a single PDF, no zip',
      (tester) async {
    await pumpHome(tester);
    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle();

    expect(repo.exportedIds, [1]);
    expect(archiver.calls, 0);
    expect(share.lastFilePaths!.single, endsWith('.pdf'));
    expect(share.lastMimeType, isNull);
    // selection cleared after success
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('two selected → Export zips separate PDFs and shares the zip',
      (tester) async {
    await pumpHome(tester);
    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-tile-2')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle();

    expect(repo.separateExportCalls.single, [1, 2]); // displayed (sorted) order
    expect(archiver.calls, 1);
    expect(archiver.lastEntryNames, ['Alpha.pdf', 'Beta.pdf']);
    expect(share.lastFilePaths!.single, endsWith('.zip'));
    expect(share.lastMimeType, 'application/zip');
    expect(find.text('2 selected'), findsNothing);
  });

  testWidgets('a failing export shows the "Couldn\'t share" snackbar',
      (tester) async {
    repo = FakeDocumentRepository(
      documents: [_doc(1, 'Alpha'), _doc(2, 'Beta')],
      throwOnExport: true,
    );
    await pumpHome(tester);
    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-tile-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't share"), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/features/library/home_multi_export_test.dart`
Expected: FAIL — `document-tile` long-press has no effect / `selection-export` key not found.

- [ ] **Step 4: Implement selection mode in `home_screen.dart`**

Add the import near the top (with the `package:path` imports is fine — add after the material import):

```dart
import 'package:path/path.dart' as p;
```

Add selection state next to `_sharing` (~line 43):

```dart
  final Set<int> _selectedIds = {};
  bool get _selectionMode => _selectedIds.isNotEmpty;
```

Add these methods (place them right after `_shareDocument`, ~line 194):

```dart
  void _toggleSelect(DocumentSummary s) {
    setState(() {
      final id = s.document.id;
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _enterSelection(DocumentSummary s) {
    setState(() => _selectedIds.add(s.document.id));
  }

  void _clearSelection() => setState(_selectedIds.clear);

  /// Ids of the currently-selected documents in displayed (sorted) order.
  List<int> get _selectedInDisplayOrder => [
        for (final s in sortDocuments(_summaries, _sort))
          if (_selectedIds.contains(s.document.id)) s.document.id,
      ];

  Future<void> _exportSelected() async {
    final repo = _repository;
    if (repo == null || _sharing) return;
    final ids = _selectedInDisplayOrder;
    if (ids.isEmpty) return;
    final byId = {for (final s in _summaries) s.document.id: s.document};
    _sharing = true;
    try {
      if (ids.length == 1) {
        final file = await repo.exportPdf(ids.single);
        await widget.libraryDependencies.share
            .share([file.path], subject: byId[ids.single]?.name);
      } else {
        final files = await repo.exportSeparatePdfs(ids);
        final zip = await widget.libraryDependencies.archiver.zip(
          files,
          archiveName: 'documents.zip',
          entryNames: [for (final f in files) p.basename(f.path)],
        );
        await widget.libraryDependencies.share
            .share([zip.path], mimeType: 'application/zip');
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

Make search and selection mutually exclusive — in `_openSearch` (~line 131) clear any selection:

```dart
  void _openSearch() => setState(() {
        _selectedIds.clear();
        _searching = true;
      });
```

Replace the `appBar:` line in `build` (~line 199) with a three-way choice:

```dart
      appBar: _searching
          ? _buildSearchAppBar()
          : _selectionMode
              ? _buildSelectionAppBar()
              : _buildNormalAppBar(),
```

Hide the FAB while selecting — replace the `floatingActionButton:` condition (~line 207):

```dart
      floatingActionButton: (_searching || _selectionMode)
          ? null
          : FloatingActionButton.extended(
              onPressed: _repository == null ? null : _openScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan'),
            ),
```

Add the selection app bar next to `_buildNormalAppBar` (~line 228):

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

Finally, wire selection into the non-search `DocumentsListView` in `_buildBody` (~line 282). Replace that `DocumentsListView(...)` (the one inside the `Column`/`Expanded`, NOT the search branch) with:

```dart
          child: DocumentsListView(
            summaries: sortDocuments(_summaries, _sort),
            onOpen: _openDocument,
            onRename: _renameDocument,
            onShare: _shareDocument,
            selectionMode: _selectionMode,
            selectedIds: _selectedIds,
            onLongPress: _enterSelection,
            onToggleSelect: _toggleSelect,
          ),
```

(The search-branch `DocumentsListView` is left unchanged — no selection while searching.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/library/home_multi_export_test.dart`
Expected: PASS (4 tests).

Run: `flutter test`
Expected: PASS (full suite green).

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze lib/features/library/library_dependencies.dart lib/features/library/home_screen.dart test/features/library/home_multi_export_test.dart`
Expected: `No issues found!`

```bash
git add apps/mobile/lib/features/library/library_dependencies.dart \
  apps/mobile/lib/features/library/home_screen.dart \
  apps/mobile/test/features/library/home_multi_export_test.dart
git commit -m "feat(library): multi-select export → share documents as a .zip"
```

---

### Task 6: BDD feature + steps

**Files:**
- Create: `apps/mobile/integration_test/r4_share_documents_zip.feature`
- Create: `apps/mobile/test/step/i_long_press_the_first_document.dart`
- Create: `apps/mobile/test/step/i_select_the_second_document.dart`
- Create: `apps/mobile/test/step/i_export_the_selection.dart`
- Create: `apps/mobile/test/step/a_zip_is_handed_to_the_share_sheet.dart`
- Generated (by build_runner): `apps/mobile/integration_test/r4_share_documents_zip_test.dart`

**Interfaces:**
- Consumes: `tempLibraryDependencies()` (real Drift-on-memory + `lastBddShareChannel`), the Task 5 UI keys, `b1`-style scan/save steps that already exist (`i_tap_the_scan_button`, `i_capture_and_accept_the_first_page`, `i_tap_done`).

> The scenario builds two real documents through the scan flow (reusing existing steps), then multi-selects and exports. `tempLibraryDependencies()` wires a real `DriftDocumentRepository` + a `FakeShareChannel` (captured as `lastBddShareChannel`) and the **default** `SystemFileArchiver`, so a real `.zip` is actually produced and its path is asserted.

- [ ] **Step 1: Write the feature file**

Create `apps/mobile/integration_test/r4_share_documents_zip.feature`:

```gherkin
Feature: Share multiple documents as a zip

  Scenario: Select two documents and share them as a single zip
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I long press the first document
    And I select the second document
    And I export the selection
    Then a zip is handed to the share sheet
```

> Before writing steps, confirm the exact wording of the existing scan/save steps in `test/step/` (e.g. `i_capture_and_accept_the_first_page.dart`) and reuse them verbatim so no duplicate steps are generated. Adjust the three reused lines above to match the existing generated method names if they differ.

- [ ] **Step 2: Run build_runner to generate the test + step stubs**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: generates `integration_test/r4_share_documents_zip_test.dart` and empty step stubs under `test/step/` for any new step (the four new `.dart` files below). If a stub is generated for an already-existing step, delete the duplicate and keep the original.

- [ ] **Step 3: Implement the new steps**

`apps/mobile/test/step/i_long_press_the_first_document.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I long press the first document
Future<void> iLongPressTheFirstDocument(WidgetTester tester) async {
  await tester.longPress(find.byKey(const Key('document-tile-1')));
  await tester.pumpAndSettle();
}
```

`apps/mobile/test/step/i_select_the_second_document.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I select the second document
Future<void> iSelectTheSecondDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-tile-2')));
  await tester.pumpAndSettle();
}
```

`apps/mobile/test/step/i_export_the_selection.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export the selection
Future<void> iExportTheSelection(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('selection-export')));
  await tester.pumpAndSettle();
}
```

`apps/mobile/test/step/a_zip_is_handed_to_the_share_sheet.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_library.dart';

/// Usage: a zip is handed to the share sheet
Future<void> aZipIsHandedToTheShareSheet(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  final share = lastBddShareChannel;
  expect(share, isNotNull);
  expect(share!.calls, greaterThan(0));
  expect(share.lastFilePaths!.single, endsWith('.zip'));
  expect(share.lastMimeType, 'application/zip');
}
```

- [ ] **Step 4: Point the generated test at `tempLibraryDependencies`**

Confirm the generated `integration_test/r4_share_documents_zip_test.dart` launches the app via the shared `bddSetUp`/launch that other `r*`/`b1` features use (i.e. through `tempLibraryDependencies()`), matching `r1_share_document.feature`. If the generator emits its own `main`, ensure the `Given ... empty storage` step wires `tempLibraryDependencies()` exactly as the existing `the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart` step does (reused verbatim — do not fork it).

- [ ] **Step 5: Run the generated BDD test on host**

Run: `flutter test integration_test/r4_share_documents_zip_test.dart`
Expected: PASS. (Uses fakes/in-memory Drift; no native libs required for the host run — the OS share sheet is faked via `lastBddShareChannel`.)

If it fails to load native libs (opencv/MLKit) during the scan steps on host, that is the documented host limitation — defer this scenario's execution to the device run in Task 7 and note it explicitly.

- [ ] **Step 6: Analyze + commit**

Run: `flutter analyze integration_test/r4_share_documents_zip_test.dart test/step/i_long_press_the_first_document.dart test/step/i_select_the_second_document.dart test/step/i_export_the_selection.dart test/step/a_zip_is_handed_to_the_share_sheet.dart`
Expected: `No issues found!`

```bash
git add apps/mobile/integration_test/r4_share_documents_zip.feature \
  apps/mobile/integration_test/r4_share_documents_zip_test.dart \
  apps/mobile/test/step/i_long_press_the_first_document.dart \
  apps/mobile/test/step/i_select_the_second_document.dart \
  apps/mobile/test/step/i_export_the_selection.dart \
  apps/mobile/test/step/a_zip_is_handed_to_the_share_sheet.dart
git commit -m "test(share): BDD scenario — select two documents and share as a zip"
```

---

### Task 7: Device verification (Android AND iOS) + boot gate

**Files:** none (verification only). Produces the evidence CLAUDE.md requires before "done".

- [ ] **Step 1: Confirm devices are attached**

Run: `flutter devices`
Expected: the Android device (`RZCY51D0T1K`) and the iOS device (`00008120-0016355C21E8201E`) both listed.

- [ ] **Step 2: Full host suite green**

Run (from `apps/mobile/`): `flutter test`
Expected: PASS. Paste the summary line.

- [ ] **Step 3: BDD scenario on a real Android device**

Run: `flutter test integration_test/r4_share_documents_zip_test.dart -d RZCY51D0T1K`
Expected: PASS — a real `.zip` is produced and handed to the (faked) share channel. Paste the result.

- [ ] **Step 4: BDD scenario on a real iOS device**

Run: `flutter test integration_test/r4_share_documents_zip_test.dart -d 00008120-0016355C21E8201E`
Expected: PASS. Paste the result.

- [ ] **Step 5: Manual real-share smoke test on both devices**

Run: `flutter run --release -d RZCY51D0T1K` (then repeat with the iOS id). Scan/create ≥2 documents, long-press to select, tap Export, and confirm the OS share sheet appears with a single `.zip` that a target app (e.g. Files/Mail) accepts. Record the outcome per platform.

- [ ] **Step 6: Boot gate (guards the latent `createInBackground` hang)**

Confirm each device cold-launches to the document list without hanging (the app opened in Step 5 counts if it reached the list). If either device hangs on boot, STOP: that is the separate known `NativeDatabase.createInBackground` issue (fix = open the DB on the root isolate in `app_database.dart`) — report it as a distinct finding; do not fold a DB-layer change into this feature without a new red test.

- [ ] **Step 7: Record evidence**

State, per platform, the exact command run and the green result. Only after Android AND iOS pass (or an explicit, named gap is recorded) is the feature "done".

---

## Self-Review

**1. Spec coverage:**
- Selection mode (long-press, count, close, clear-on-success) → Tasks 4, 5. ✓
- `DocumentsListView` opt-in params → Task 4. ✓
- No choice dialog; 1→PDF, 2+→zip → Task 5 `_exportSelected`. ✓
- `exportSeparatePdfs` repo method → Task 2. ✓
- `FileArchiver`/`SystemFileArchiver`, stored, deduped, temp `.zip`, `archive` promoted → Task 1. ✓
- `ShareChannel` optional `mimeType`; zip shares `application/zip` → Tasks 3, 5. ✓
- Error handling: `_sharing` guard, empty-throw, "Couldn't share" snackbar → Tasks 2, 5. ✓
- TDD host tests for archiver/repo/share/list/home → Tasks 1–5. ✓
- BDD `.feature` + steps → Task 6. ✓
- Android + iOS device verification + boot gate → Task 7. ✓
- Out of scope (merge/combined PDF, quality picker, DB boot-hang fix) → excluded. ✓

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; every run step shows the command + expected result. The only conditional instructions (Task 6 Steps 2/4) are explicit reconciliation steps against generated output, not placeholders. ✓

**3. Type consistency:** `FileArchiver.zip(List<File>, {required String archiveName, required List<String> entryNames})` is identical in Task 1 (definition), Task 5 (call), and Task 6's `FakeFileArchiver`. `exportSeparatePdfs(List<int>)` identical in Tasks 2 and 5 and the fake. `share(..., {String? subject, String? mimeType})` identical in Tasks 3 and 5 and the fake. `FakeDocumentRepository.separateExportCalls`, `FakeShareChannel.lastMimeType`, `FakeFileArchiver.lastEntryNames` names match across defining and asserting tasks. Home keys `selection-close` / `selection-export` and row key `document-check-<id>` match between Tasks 4/5 and the tests/steps. ✓
