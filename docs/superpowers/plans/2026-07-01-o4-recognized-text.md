# O4 — Recognized Text (view / copy / export `.txt`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface each page's cached OCR text in-app — a selectable text view with copy-all and export-as-`.txt` (temp-file share).

**Architecture:** A new `DocumentRepository.exportRecognizedText` materializes a page's cached `ocrText` into a temporary `.txt` file (mirrors `exportPdf`'s temp-file share). A new `RecognizedTextScreen` loads the page's text authoritatively from the repository, renders it in a `SelectableText`, and offers Copy (clipboard) + Share (`share_plus`). An empty page offers on-demand "Recognize text" via the existing `runOcr`. The page viewer's per-page popup menu gains a "View text" entry.

**Tech Stack:** Flutter/Dart, drift (SQLite), `share_plus` 13.2.0, `google_mlkit_text_recognition` (already wired), `bdd_widget_test` + `build_runner`.

## Global Constraints

- **iOS + Android**: every decision must work on both. Use only cross-platform APIs (`SelectableText`, `Clipboard`, `share_plus`, `Directory.systemTemp`). No platform channels.
- **On-device only, no cloud**: text never leaves the device except via the user-initiated share sheet.
- **No file accumulation**: the `.txt` export goes to `Directory.systemTemp` (temporary), never persistent app storage — same rule as the temp-PDF share.
- **TDD/BDD first**; SOLID/KISS/DRY. Reuse `_pdfFileNameFor`'s sanitizer (DRY-extract a shared base-name helper).
- **Commits**: stage explicit file paths (never `git add -A`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Do NOT touch**: `apps/mobile/android/build.gradle.kts` (project-level), `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, `.superpowers/`.
- **On-device gate**: BDD + integration tests must pass on the Samsung `RZCY51D0T1K`. Host `flutter test` skips `integration_test/` (compile gate is `flutter analyze`).
- Paths below are relative to `apps/mobile/` unless noted (`scripts/` and `docs/` are repo-root).

---

### Task 1: `exportRecognizedText` repository method

**Files:**
- Modify: `lib/features/library/document_repository.dart` (add interface method)
- Modify: `lib/features/library/drift/drift_document_repository.dart` (impl + extract sanitizer)
- Modify: `test/support/fake_library.dart` (implement in `FakeDocumentRepository`)
- Test: `test/features/library/export_recognized_text_test.dart` (create)

**Interfaces:**
- Consumes: existing `AppDatabase` (`pages` table with `ocrText` column; `documents` table with `name`), `DocumentExportException`, `_pdfFileNameFor` sanitizer.
- Produces: `Future<File> exportRecognizedText(int documentId, int position)` on `DocumentRepository`.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/export_recognized_text_test.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
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
    base = await Directory.systemTemp.createTemp('o4txt');
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

  Future<int> seedPage({String? ocrText}) async {
    final now = DateTime.now();
    final docId = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: 'My Report', createdAt: now, modifiedAt: now));
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId,
        position: 1,
        relativeImagePath: 'documents/$docId/page_1.jpg',
        ocrText: Value(ocrText)));
    return docId;
  }

  test('writes a temp .txt with the cached text and a sanitized name', () async {
    final docId = await seedPage(ocrText: 'HELLO WORLD');
    final file = await repo.exportRecognizedText(docId, 1);

    expect(await file.readAsString(), 'HELLO WORLD');
    expect(file.path, endsWith('My Report_page_1.txt'));
    // Temp, not under the documents dir.
    expect(file.path.contains(base.path), isFalse);
  });

  test('throws when the page has no recognized text', () async {
    final docId = await seedPage(ocrText: null);
    expect(() => repo.exportRecognizedText(docId, 1),
        throwsA(isA<DocumentExportException>()));
  });

  test('throws when the page row does not exist', () async {
    expect(() => repo.exportRecognizedText(999, 1),
        throwsA(isA<DocumentExportException>()));
  });
}
```

> **Note (implementer):** confirm the `Value(...)` import — `PagesCompanion.insert`'s `ocrText` is a nullable column, so import `package:drift/drift.dart` (for `Value`) if not already transitively available via `app_database.dart`. If `ocrText` is not an `insert` named param, set it with a follow-up `db.update`. Verify against the actual `Pages` table definition.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/export_recognized_text_test.dart`
Expected: FAIL — `exportRecognizedText` is not defined on the repository.

- [ ] **Step 3: Add the interface method**

In `lib/features/library/document_repository.dart`, immediately after the `runOcr` declaration (before the closing `}` of the interface):

```dart
  /// Materializes the page at [position] of [documentId]'s cached recognized
  /// text (`ocrText`) into a TEMPORARY `.txt` file and returns it. The file is
  /// named `<sanitized-document-name>_page_<position>.txt` under the system temp
  /// dir — temporary, so the app does not accumulate exports (mirrors
  /// [exportPdf]). A `.txt` carries no metadata, so no scrub pass is needed.
  /// Nothing leaves the device. Throws [DocumentExportException] when the page
  /// row is missing or has no recognized text (null/empty/whitespace).
  Future<File> exportRecognizedText(int documentId, int position);
```

- [ ] **Step 4: Implement in the Drift repository**

In `lib/features/library/drift/drift_document_repository.dart`:

First DRY-extract the sanitizer. Replace `_pdfFileNameFor` with:

```dart
  /// Sanitized base name (no extension) from the document's name; 'document'
  /// when the name is empty/unknown. Shared by all export filename builders.
  Future<String> _exportBaseName(int documentId) async {
    final doc = await (_db.select(_db.documents)
          ..where((d) => d.id.equals(documentId)))
        .getSingleOrNull();
    final base = (doc?.name ?? 'document')
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_')
        .trim();
    return base.isEmpty ? 'document' : base;
  }

  Future<String> _pdfFileNameFor(int documentId) async =>
      '${await _exportBaseName(documentId)}.pdf';
```

Then add the method (place near `exportPageAsImage`):

```dart
  @override
  Future<File> exportRecognizedText(int documentId, int position) async {
    final row = await (_db.select(_db.pages)
          ..where((t) =>
              t.documentId.equals(documentId) & t.position.equals(position)))
        .getSingleOrNull();
    if (row == null) {
      throw DocumentExportException(
          'exportText failed: no page ($documentId, $position)');
    }
    final text = row.ocrText;
    if (text == null || text.trim().isEmpty) {
      throw const DocumentExportException('exportText failed: no recognized text');
    }
    try {
      final dir = await Directory.systemTemp.createTemp('txt_export');
      final base = await _exportBaseName(documentId);
      final file = File('${dir.path}/${base}_page_$position.txt');
      await file.writeAsString(text);
      return file;
    } catch (e) {
      throw DocumentExportException('exportText failed: $e');
    }
  }
```

> Ensure `dart:io` `File`/`Directory` are already imported in this file (they are — `exportPdf` uses them).

- [ ] **Step 5: Implement in the fake repository**

In `test/support/fake_library.dart`, add to `FakeDocumentRepository` (near the existing `runOcr` no-op). Add a field to control failure and record calls, then the method:

```dart
  final bool throwOnExportText;
  int? lastExportedTextPosition;
```
(add `this.throwOnExportText = false` to the constructor parameter list alongside the other `throwOn*` flags)

```dart
  @override
  Future<File> exportRecognizedText(int documentId, int position) async {
    lastExportedTextPosition = position;
    if (throwOnExportText) {
      throw const DocumentExportException('fake exportText failure');
    }
    final dir = await Directory.systemTemp.createTemp('faketxt');
    final f = File('${dir.path}/page_$position.txt');
    await f.writeAsString('fake recognized text');
    return f;
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/export_recognized_text_test.dart`
Expected: PASS (3/3).

- [ ] **Step 7: Analyze**

Run: `cd apps/mobile && flutter analyze --no-fatal-infos`
Expected: `No issues found`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/document_repository.dart apps/mobile/lib/features/library/drift/drift_document_repository.dart apps/mobile/test/support/fake_library.dart apps/mobile/test/features/library/export_recognized_text_test.dart
git commit -m "feat(o4): exportRecognizedText — cached OCR text to a temp .txt"
```

---

### Task 2: `RecognizedTextScreen` widget

**Files:**
- Create: `lib/features/library/recognized_text_screen.dart`
- Test: `test/features/library/recognized_text_screen_test.dart` (create)

**Interfaces:**
- Consumes: `DocumentRepository` (`getDocumentPages`, `runOcr`, `exportRecognizedText`), `PageImage.ocrText`, `FakeDocumentRepository`, `SharePlus`.
- Produces: `RecognizedTextScreen({required int documentId, required int position, required String name, String? initialText, required DocumentRepository repository})`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/library/recognized_text_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/recognized_text_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Widget host(FakeDocumentRepository repo, {String? initialText}) => MaterialApp(
        home: RecognizedTextScreen(
          documentId: 1,
          position: 1,
          name: 'My Report',
          initialText: initialText,
          repository: repo,
        ),
      );

  testWidgets('renders the page text as selectable text', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/x.jpg', ocrText: 'HELLO WORLD')],
    );
    await tester.pumpWidget(host(repo, initialText: 'HELLO WORLD'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recognized-text-body')), findsOneWidget);
    expect(find.text('HELLO WORLD'), findsWidgets);
  });

  testWidgets('Copy places the text on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/x.jpg', ocrText: 'HELLO WORLD')],
    );
    await tester.pumpWidget(host(repo, initialText: 'HELLO WORLD'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recognized-text-copy')));
    await tester.pumpAndSettle();

    expect(copied, 'HELLO WORLD');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('empty page offers Recognize text; tapping runs OCR and shows result',
      (tester) async {
    final repo = FakeDocumentRepository(
      // Page starts with NO text → empty state; runOcr "recognizes" the text.
      pages: const [PageImage(position: 1, imagePath: '/x.jpg')],
      recognizesText: 'RECOGNIZED NOW',
    );
    await tester.pumpWidget(host(repo, initialText: null));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recognized-text-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('recognized-text-run')));
    await tester.pumpAndSettle();

    expect(repo.ranOcr, isTrue);
    expect(find.byKey(const Key('recognized-text-body')), findsOneWidget);
    expect(find.text('RECOGNIZED NOW'), findsWidgets);
  });
}
```

> **Note (implementer):** the screen's `_load()` runs on init, so the fake must return a page with **no** `ocrText` initially (empty state), and `runOcr` must **mutate** the fake's working page to carry `recognizesText` so the post-`runOcr` reload surfaces it. Test #1/#2 inject a page that already has `ocrText: 'HELLO WORLD'`, so `_load` renders it immediately (initialText only avoids a spinner flash). See Step 3 for the exact fake changes.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/recognized_text_screen_test.dart`
Expected: FAIL — `recognized_text_screen.dart` does not exist.

- [ ] **Step 3: Model on-demand OCR in the fake**

In `test/support/fake_library.dart`:

Add a constructor parameter `String? recognizesText` (default null) alongside `this.pages`, store it as a field, then replace the no-op `runOcr` with a version that records the call and writes `recognizesText` onto the matching working page:

```dart
  final String? recognizesText;
  bool ranOcr = false;

  @override
  Future<void> runOcr(int documentId, int position) async {
    ranOcr = true;
    final w = _working;
    final t = recognizesText;
    if (w != null && t != null) {
      for (var i = 0; i < w.length; i++) {
        if (w[i].position == position) {
          w[i] = PageImage(
            position: w[i].position,
            imagePath: w[i].imagePath,
            corners: w[i].corners,
            flatImagePath: w[i].flatImagePath,
            ocrText: t,
            ocrWords: w[i].ocrWords,
          );
        }
      }
    }
  }
```

> `_working` is the fake's mutable copy of the injected `pages` (already present). `getDocumentPages` returns `_working`, so this mutation is what the screen's post-`runOcr` reload sees.

- [ ] **Step 4: Implement the screen**

Create `lib/features/library/recognized_text_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart'; // re-exports XFile

import 'document_repository.dart';
import 'page_image.dart';

/// Shows a single page's cached OCR text: selectable, copyable, exportable as a
/// temporary `.txt` via the share sheet. Loads the text authoritatively from
/// the repository on init (with [initialText] as an instant-render seed), so it
/// stays correct even if the caller's cached text is stale. When the page has
/// no text yet, offers an on-demand "Recognize text" action (`runOcr`).
class RecognizedTextScreen extends StatefulWidget {
  final int documentId;
  final int position;
  final String name;
  final String? initialText;
  final DocumentRepository repository;

  const RecognizedTextScreen({
    super.key,
    required this.documentId,
    required this.position,
    required this.name,
    required this.repository,
    this.initialText,
  });

  @override
  State<RecognizedTextScreen> createState() => _RecognizedTextScreenState();
}

class _RecognizedTextScreenState extends State<RecognizedTextScreen> {
  String? _text;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final pages = await widget.repository.getDocumentPages(widget.documentId);
      if (!mounted) return;
      PageImage? page;
      for (final p in pages) {
        if (p.position == widget.position) {
          page = p;
          break;
        }
      }
      setState(() => _text = page?.ocrText);
    } catch (_) {
      // Keep whatever seed we had; surface nothing catastrophic.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recognize() async {
    setState(() => _busy = true);
    try {
      await widget.repository.runOcr(widget.documentId, widget.position);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't recognize text")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final t = _text;
    if (t == null || t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied')),
    );
  }

  Future<void> _share() async {
    try {
      final file = await widget.repository
          .exportRecognizedText(widget.documentId, widget.position);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: widget.name),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't export text")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final hasText = text != null && text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Text'),
        actions: [
          IconButton(
            key: const Key('recognized-text-copy'),
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: (_busy || !hasText) ? null : _copy,
          ),
          IconButton(
            key: const Key('recognized-text-share'),
            tooltip: 'Export as .txt',
            icon: const Icon(Icons.share),
            onPressed: (_busy || !hasText) ? null : _share,
          ),
        ],
      ),
      body: _busy && text == null
          ? const Center(
              key: Key('recognized-text-loading'),
              child: CircularProgressIndicator())
          : hasText
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    text,
                    key: const Key('recognized-text-body'),
                  ),
                )
              : Center(
                  key: const Key('recognized-text-empty'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No text recognized on this page yet.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('recognized-text-run'),
                        onPressed: _busy ? null : _recognize,
                        child: const Text('Recognize text'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
```

> **Note (implementer):** the `_load` lookup uses a plain null-safe loop over the concrete `PageImage` list (no `package:collection` dependency). `ocrText` is already `String?` on `PageImage`, so `_text = page?.ocrText` type-checks directly. `XFile` is re-exported by `package:share_plus/share_plus.dart` (same as `pdf_preview_screen.dart`) — do NOT add a `cross_file` dependency.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/recognized_text_screen_test.dart`
Expected: PASS (3/3). No `Image.file` is used, so no host decode hang.

- [ ] **Step 6: Analyze**

Run: `cd apps/mobile && flutter analyze --no-fatal-infos`
Expected: `No issues found`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/recognized_text_screen.dart apps/mobile/test/features/library/recognized_text_screen_test.dart apps/mobile/test/support/fake_library.dart
git commit -m "feat(o4): RecognizedTextScreen — selectable text, copy, share .txt"
```

---

### Task 3: Wire "View text" into the page viewer

**Files:**
- Modify: `lib/features/library/page_viewer_screen.dart`
- Test: `test/features/library/page_viewer_view_text_test.dart` (create)

**Interfaces:**
- Consumes: `RecognizedTextScreen` (Task 2), existing `page-viewer-page-menu` popup, `_pages[_current]`.
- Produces: a `page-viewer-view-text` popup menu item that pushes `RecognizedTextScreen` for the current page.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/library/page_viewer_view_text_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('View text opens the recognized-text screen for the current page',
      (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/x.jpg', ocrText: 'HELLO WORLD')],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-view-text')));
    await tester.pumpAndSettle();

    // On the recognized-text screen now.
    expect(find.byKey(const Key('recognized-text-body')), findsOneWidget);
    expect(find.text('HELLO WORLD'), findsWidgets);
  });
}
```

> **Note (implementer):** confirm `FakeDocumentRepository(pages: [...])` yields a page whose image is a NON-loadable path (`/x.jpg`) so the viewer's `Image.file` degrades to the broken-image placeholder rather than hanging the host test (established pattern — see `flutter-image-file-host-test-hang` memory). The existing fake already synthesizes non-loadable pages; passing an explicit `ocrText` page keeps that property.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_view_text_test.dart`
Expected: FAIL — no `page-viewer-view-text` item.

- [ ] **Step 3: Add the import and the handler**

In `lib/features/library/page_viewer_screen.dart`, add the import near the other feature imports:

```dart
import 'recognized_text_screen.dart';
```

Add a method alongside `_exportPageAsImage`:

```dart
  void _viewText() {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecognizedTextScreen(
          documentId: widget.documentId,
          position: page.position,
          name: _name,
          initialText: page.ocrText,
          repository: widget.repository,
        ),
      ),
    );
  }
```

- [ ] **Step 4: Add the menu item**

In the `PopupMenuButton`'s `onSelected`, add:

```dart
              if (v == 'view-text') _viewText();
```

In `itemBuilder`'s list, add as the first item (view is a read action, list it before mutating actions):

```dart
              PopupMenuItem<String>(
                value: 'view-text',
                key: Key('page-viewer-view-text'),
                child: Text('View text'),
              ),
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_view_text_test.dart`
Expected: PASS.

- [ ] **Step 6: Run the full page-viewer + library test group + analyze**

Run: `cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/test/features/library/page_viewer_view_text_test.dart
git commit -m "feat(o4): page viewer 'View text' opens recognized-text screen"
```

---

### Task 4: BDD `.feature`, on-device integration test, verify script, plans index

**Files:**
- Create: `integration_test/o4_recognized_text.feature`
- Create step defs (as needed): `test/step/a_saved_document_with_recognized_text.dart`, `test/step/i_open_the_text_view.dart`, `test/step/i_copy_the_recognized_text.dart`
- Generate: `integration_test/o4_recognized_text_test.dart` (via build_runner; committed)
- Create: `integration_test/o4_recognized_text_device_test.dart` (deterministic on-device test with real ML Kit)
- Create: `scripts/verify/o4.sh` (repo root)
- Modify: `docs/superpowers/plans/00-plans-index.md`

**Interfaces:**
- Consumes: `bdd_widget_test` generation pipeline, existing `support/persistent_storage.dart` seeding pattern, `MlKitOcrEngine`, `RecognizedTextScreen` keys.

- [ ] **Step 1: Write the `.feature`**

Create `integration_test/o4_recognized_text.feature`:

```gherkin
Feature: View and copy recognized text

  Scenario: Open a page's recognized text and copy it
    Given a saved document with recognized text {'HELLO WORLD'}
    When the app launches reading that same storage
    And I open the first document
    And I open the text view
    Then I see {'HELLO WORLD'} text
    And I copy the recognized text
    Then I see {'Copied'} text
```

- [ ] **Step 2: Write the new step definitions**

Create `test/step/a_saved_document_with_recognized_text.dart` — mirror `a_document_was_saved_to_persistent_storage_earlier.dart`, but insert a page WITH `ocrText`:

```dart
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

import '../support/persistent_storage.dart';

/// Usage: a saved document with recognized text {'HELLO WORLD'}
Future<void> aSavedDocumentWithRecognizedText(
    WidgetTester tester, String text) async {
  final dir = await Directory.systemTemp.createTemp('o4persist');
  persistentDir = dir;
  persistentDbFile = File('${dir.path}/camscanner.sqlite');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  final db = AppDatabase(NativeDatabase(persistentDbFile!));
  final now = DateTime.utc(2026, 7, 1, 12);
  final docId = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'OCR Doc', createdAt: now, modifiedAt: now));
  await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId,
        position: 1,
        relativeImagePath: 'documents/$docId/page_1.jpg',
        ocrText: Value(text)));
  await db.close();
}
```

Create `test/step/i_open_the_text_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the text view
Future<void> iOpenTheTextView(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-view-text')));
  await tester.pumpAndSettle();
}
```

Create `test/step/i_copy_the_recognized_text.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I copy the recognized text
Future<void> iCopyTheRecognizedText(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('recognized-text-copy')));
  await tester.pumpAndSettle();
}
```

> `I open the first document` and `I see {'...'} text` step defs already exist and are reused verbatim.

- [ ] **Step 3: Generate the BDD test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `integration_test/o4_recognized_text_test.dart` is (re)generated importing the step files above. Verify the generated file references `aSavedDocumentWithRecognizedText`, `iOpenTheTextView`, `iCopyTheRecognizedText`.

- [ ] **Step 4: Write the deterministic on-device test**

Create `integration_test/o4_recognized_text_device_test.dart` — proves the real ML Kit path plus `exportRecognizedText` and screen rendering, deterministically (rendered-text JPEG):

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/ocr/mlkit_ocr_engine.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/recognized_text_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recognized text renders in-app and exports as .txt on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('o4dev');
    final db = AppDatabase(NativeDatabase.memory());
    final store = DocumentFileStore(base);
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
      ocrEngine: const MlKitOcrEngine(),
    );

    // Seed a page with a real "scanned" JPEG (black text on white).
    final now = DateTime.now();
    final docId = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
    final rel = 'documents/$docId/page_1.jpg';
    final image = img.Image(width: 720, height: 220);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.drawString(image, 'HELLO WORLD',
        font: img.arial48, x: 40, y: 80, color: img.ColorRgb8(0, 0, 0));
    await store.writeRelative(rel, Uint8List.fromList(img.encodeJpg(image, quality: 95)));
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId, position: 1, relativeImagePath: rel));

    await repo.runOcr(docId, 1);

    await tester.pumpWidget(MaterialApp(
      home: RecognizedTextScreen(
        documentId: docId, position: 1, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recognized-text-body')), findsOneWidget);
    expect(find.textContaining('HELLO'), findsWidgets);

    final file = await repo.exportRecognizedText(docId, 1);
    expect((await file.readAsString()).toUpperCase(), contains('HELLO'));

    await db.close();
    await base.delete(recursive: true);
  });
}
```

- [ ] **Step 5: Write the verify script**

Create `scripts/verify/o4.sh` (repo root), mirroring `scripts/verify/o1.sh`:

```bash
#!/usr/bin/env bash
# Verify O4 (recognized text: view / copy / export .txt) acceptance criteria.
# Run from repository root: bash scripts/verify/o4.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== O4 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "exportRecognizedText on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "exportRecognizedText"

assert_file_has "exportRecognizedText in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "exportRecognizedText"

assert_file_has "RecognizedTextScreen exists" \
  "apps/mobile/lib/features/library/recognized_text_screen.dart" \
  "class RecognizedTextScreen"

assert_file_has "page viewer wires View text" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-view-text"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/o4_recognized_text.feature" \
  "View and copy recognized text"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/o4_recognized_text_test.dart" \
  "recognized text"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device O4 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device recognized-text test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/o4_recognized_text_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/o4_recognized_text_test.dart"
fi

echo "== O4 verification complete =="
```

Make it executable: `chmod +x scripts/verify/o4.sh`.

- [ ] **Step 6: Run host tests, analyze, and (on device) the verify script**

Run: `cd apps/mobile && flutter test && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

On the connected Samsung `RZCY51D0T1K`:
Run: `bash scripts/verify/o4.sh`
Expected: `== O4 verification complete ==` with every assertion ✓.

- [ ] **Step 7: Update the plans index**

In `docs/superpowers/plans/00-plans-index.md`, add rows after the O1 row (also correct the stale O2/O3 gap — they are built & merged):

```markdown
| O2 | OCR engine (ML Kit) + auto-run after save | 08 | `2026-07-01-o2-mlkit-engine.md`¹ | ✅ **built & merged** |
| O3 | Searchable PDF text layer | 08 | `2026-07-01-o3-searchable-pdf.md`¹ | ✅ **built & merged** |
| O4 | Recognized text: view / copy / export .txt | 08 | `2026-07-01-o4-recognized-text.md` | ✅ **built & gated** |
```

> ¹ O2/O3 were built and merged directly (commits `d896f1d`, `2657c31`) ahead of a formal plan file; rows added here for an accurate index. If no plan file exists, cite the commit in the note column instead of a filename.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/integration_test/o4_recognized_text.feature apps/mobile/integration_test/o4_recognized_text_test.dart apps/mobile/integration_test/o4_recognized_text_device_test.dart apps/mobile/test/step/a_saved_document_with_recognized_text.dart apps/mobile/test/step/i_open_the_text_view.dart apps/mobile/test/step/i_copy_the_recognized_text.dart scripts/verify/o4.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(o4): BDD + on-device recognized-text tests, verify script, index"
```

---

## Self-Review

- **Spec coverage:** selectable text view (Task 2 `SelectableText`), copy (Task 2 `_copy`), export `.txt` (Task 1 + Task 2 `_share`), entry point (Task 3), empty→on-demand OCR (Task 2 `_recognize`), temp-file no-accumulation (Task 1). ✅
- **Placeholder scan:** every code step carries complete code; implementer notes flag the two spots needing a clean idiom (`PageImage` lookup; `Value` import). ✅
- **Type consistency:** `exportRecognizedText(int, int) → Future<File>` identical across interface, Drift, fake, and screen call sites; `RecognizedTextScreen` constructor identical in Task 2 test, Task 3 wiring, and Task 4 device test. ✅
- **Out of scope kept out:** no content-search, no multi-language, no doc-level concat. ✅
