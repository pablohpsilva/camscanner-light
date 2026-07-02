# R1 — Share a document Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate the three ad-hoc `share_plus` call sites behind a testable `ShareChannel` seam, and add a "Share" action to the documents list that shares a document's PDF.

**Architecture:** `ShareChannel.share(List<String> filePaths, {String? subject})` — production `SystemShareChannel` wraps `SharePlus.instance.share`; a `FakeShareChannel` records calls for tests. Injected through `LibraryDependencies.share` → `HomeScreen` → `PageViewerScreen` → `{PdfPreviewScreen, RecognizedTextScreen}`. The library-list Share reuses `exportPdf` (searchable, metadata-scrubbed) then hands the file to the channel.

**Tech Stack:** Flutter/Dart, `share_plus` (already a dependency), `pdf`, drift, `bdd_widget_test` + `build_runner`.

## Global Constraints

- **iOS + Android**: `share_plus` handles both share sheets; the seam + menu are pure Dart. No per-OS branching.
- **Testable seam**: the OS share sheet can't be automated — everything routes through `ShareChannel`; tests/BDD inject a recording fake so nothing blocks on a native sheet.
- **No new dependency**: `share_plus: ^13.2.0` is already in `pubspec.yaml`. After this refactor, `share_channel.dart` is the **only** file that imports `package:share_plus/share_plus.dart`.
- **Reuse** the existing `exportPdf` (searchable, metadata-scrubbed) PDF for library-list Share — sharing is just a new destination; no re-scrub (DRY).
- **Scope**: PDF sharing only. JPG sharing (routing `_exportPageAsImage`/`_exportAllImages` through the channel) is deferred to R2; Feature 12 stays open.
- **TDD/BDD first**; SOLID/KISS/DRY.
- **Commits**: explicit file paths (never `git add -A`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Do NOT commit report files.
- **Do NOT touch**: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, `.superpowers/`.
- **On-device gate**: BDD + integration tests pass on Samsung `RZCY51D0T1K`.
- Paths relative to `apps/mobile/` unless noted (`scripts/`, `docs/` are repo-root).

---

### Task 1: `ShareChannel` seam + `FakeShareChannel` + composition root

**Files:**
- Create: `lib/features/library/share_channel.dart`
- Modify: `lib/features/library/library_dependencies.dart` (add `share`)
- Modify: `test/support/fake_library.dart` (add `FakeShareChannel` + top-level BDD recorder)
- Test: `test/features/library/share_channel_test.dart` (create)

**Interfaces:**
- Produces: `abstract interface class ShareChannel { Future<void> share(List<String> filePaths, {String? subject}); }`; `class SystemShareChannel implements ShareChannel` (const); `class FakeShareChannel implements ShareChannel` with fields `List<String>? lastFilePaths`, `String? lastSubject`, `int calls`, ctor `FakeShareChannel({bool throwOnShare = false})`; top-level `FakeShareChannel? lastBddShareChannel`; `LibraryDependencies.share` (default `const SystemShareChannel()`).

- [ ] **Step 1: Create the seam**

Create `lib/features/library/share_channel.dart`:

```dart
import 'package:share_plus/share_plus.dart';

/// Shares files to the OS share sheet (Mail, Messages, WhatsApp, etc.).
/// Injectable (DIP) so tests and the on-device BDD use a recording fake instead
/// of the native share sheet (which cannot be driven by an automated test).
///
/// This is the OCP extension point for Feature 12: a future on-device link-share
/// channel is just another implementation — existing callers are undisturbed.
/// Path-based on purpose, so `share_plus`'s `XFile`/`ShareParams` types stay
/// entirely inside [SystemShareChannel] and never leak into the abstraction.
abstract interface class ShareChannel {
  /// Shares [filePaths] via the OS share sheet, with an optional [subject]
  /// (used by targets like Mail). Files must already be metadata-scrubbed by
  /// their producer — this channel does not scrub (DRY).
  Future<void> share(List<String> filePaths, {String? subject});
}

/// Production channel backed by the `share_plus` package. The only file in the
/// app that imports `share_plus`.
class SystemShareChannel implements ShareChannel {
  const SystemShareChannel();

  @override
  Future<void> share(List<String> filePaths, {String? subject}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: filePaths.map((p) => XFile(p)).toList(),
        subject: subject,
      ),
    );
  }
}
```

- [ ] **Step 2: Add `share` to `LibraryDependencies`**

In `lib/features/library/library_dependencies.dart`, add the import (near the other library imports, keep alphabetical with `document_printer.dart`):

```dart
import 'share_channel.dart';
```

In the `LibraryDependencies` class, add a field after `printer`:

```dart
  final ShareChannel share;
```

and in its `const` constructor parameter list, after `this.printer = const SystemDocumentPrinter(),`, add:

```dart
    this.share = const SystemShareChannel(),
```

- [ ] **Step 3: Add `FakeShareChannel` + BDD recorder to test support**

In `test/support/fake_library.dart`, add the import at the top (near the existing `document_printer.dart` import):

```dart
import 'package:mobile/features/library/share_channel.dart';
```

Add, top-level near `FakeDocumentPrinter`:

```dart
/// Recording share channel for tests: captures the last call, never touches the
/// native share sheet. [throwOnShare] simulates a share failure.
class FakeShareChannel implements ShareChannel {
  List<String>? lastFilePaths;
  String? lastSubject;
  int calls = 0;
  final bool throwOnShare;
  FakeShareChannel({this.throwOnShare = false});

  @override
  Future<void> share(List<String> filePaths, {String? subject}) async {
    if (throwOnShare) throw Exception('fake: share failed');
    calls++;
    lastFilePaths = filePaths;
    lastSubject = subject;
  }
}

/// The [FakeShareChannel] most recently installed by [tempLibraryDependencies],
/// so a BDD step can assert what was handed to the share sheet.
FakeShareChannel? lastBddShareChannel;
```

- [ ] **Step 4: Write the failing unit test**

Create `test/features/library/share_channel_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/library_dependencies.dart';
import 'package:mobile/features/library/share_channel.dart';

import '../../support/fake_library.dart';

void main() {
  test('SystemShareChannel is a ShareChannel (interface extension point)', () {
    const channel = SystemShareChannel();
    expect(channel, isA<ShareChannel>());
  });

  test('LibraryDependencies defaults share to SystemShareChannel', () {
    const deps = LibraryDependencies();
    expect(deps.share, isA<SystemShareChannel>());
  });

  test('FakeShareChannel records the last share call', () async {
    final fake = FakeShareChannel();
    await fake.share(['/tmp/a.pdf'], subject: 'Doc');
    expect(fake.calls, 1);
    expect(fake.lastFilePaths, ['/tmp/a.pdf']);
    expect(fake.lastSubject, 'Doc');
  });

  test('FakeShareChannel throws when configured to', () {
    final fake = FakeShareChannel(throwOnShare: true);
    expect(() => fake.share(['/tmp/a.pdf']), throwsException);
  });
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/share_channel_test.dart`
Expected: PASS (4/4). (This task adds the types the test needs; if it fails to compile, the seam/field is missing — fix before proceeding.)

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/share_channel.dart apps/mobile/lib/features/library/library_dependencies.dart apps/mobile/test/support/fake_library.dart apps/mobile/test/features/library/share_channel_test.dart
git commit -m "feat(r1): ShareChannel seam + SystemShareChannel/FakeShareChannel + deps"
```

---

### Task 2: Route the three existing share sites through the channel

**Files:**
- Modify: `lib/features/library/home_screen.dart` (thread `share` into `PageViewerScreen`)
- Modify: `lib/features/library/page_viewer_screen.dart` (`share` param; `_shareQuietly` uses channel; thread to `PdfPreviewScreen`/`RecognizedTextScreen`; drop `share_plus` import)
- Modify: `lib/features/library/pdf_preview_screen.dart` (`share` param; use channel; drop `share_plus` import)
- Modify: `lib/features/library/recognized_text_screen.dart` (`share` param; use channel; drop `share_plus` import)
- Test: `test/features/library/share_routing_test.dart` (create)

**Interfaces:**
- Consumes: `ShareChannel`, `SystemShareChannel`, `FakeShareChannel` (Task 1); `LibraryDependencies.share` (Task 1).
- Produces: `PdfPreviewScreen`, `PageViewerScreen`, `RecognizedTextScreen` each gain `final ShareChannel share` (default `const SystemShareChannel()`).

- [ ] **Step 1: Write the failing routing tests**

Create `test/features/library/share_routing_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';
import 'package:mobile/features/library/recognized_text_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('PdfPreviewScreen Share routes the PDF through the channel',
      (tester) async {
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(
      home: PdfPreviewScreen(
        pdfPath: '/docs/report.pdf',
        name: 'Report',
        share: share,
        // opener throws → screen shows the error state, but the Share action in
        // the app bar is always present and independent of load state.
        opener: (_) => Future.error(StateError('no native pdfx in host test')),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pdf-preview-share')));
    await tester.pump();

    expect(share.calls, 1);
    expect(share.lastFilePaths, ['/docs/report.pdf']);
    expect(share.lastSubject, 'Report');
  });

  testWidgets('RecognizedTextScreen Share routes the .txt through the channel',
      (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [
        PageImage(position: 1, imagePath: '/a.jpg', ocrText: 'HELLO'),
      ],
    );
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(
      home: RecognizedTextScreen(
        documentId: 7,
        position: 1,
        name: 'Notes',
        initialText: 'HELLO',
        repository: repo,
        share: share,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recognized-text-share')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 1);
    expect(share.lastFilePaths, isNotNull);
    expect(share.lastFilePaths!.single, endsWith('.txt'));
    expect(share.lastSubject, 'Notes');
  });

  testWidgets('PageViewer protect flow routes the protected PDF through channel',
      (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(
          documentId: 5, name: 'Doc', repository: repo, share: share),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-protect')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.pump();
    await tester.tap(find.byKey(const Key('password-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 1);
    expect(share.lastFilePaths, isNotNull);
    expect(share.lastFilePaths!.single, endsWith('.pdf'));
    expect(share.lastSubject, 'Doc');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/share_routing_test.dart`
Expected: FAIL to compile — the screens have no `share` parameter yet.

- [ ] **Step 3: Route `PdfPreviewScreen`**

In `lib/features/library/pdf_preview_screen.dart`:

Replace the import line `import 'package:share_plus/share_plus.dart';` with:
```dart
import 'share_channel.dart';
```

Add fields + constructor default. Change the widget to:
```dart
class PdfPreviewScreen extends StatefulWidget {
  final String pdfPath;
  final String name;
  final PdfOpener opener;
  final ShareChannel share;
  const PdfPreviewScreen({
    super.key,
    required this.pdfPath,
    required this.name,
    this.opener = PdfDocument.openFile,
    this.share = const SystemShareChannel(),
  });
```

Replace the Share `onPressed` (currently `SharePlus.instance.share(ShareParams(...))`) with:
```dart
            onPressed: () => unawaited(
              widget.share.share([widget.pdfPath], subject: widget.name),
            ),
```

- [ ] **Step 4: Route `RecognizedTextScreen`**

In `lib/features/library/recognized_text_screen.dart`:

Replace the import line `import 'package:share_plus/share_plus.dart'; // re-exports XFile` with:
```dart
import 'share_channel.dart';
```

Add a field + constructor default:
```dart
  final DocumentRepository repository;
  final ShareChannel share;

  const RecognizedTextScreen({
    super.key,
    required this.documentId,
    required this.position,
    required this.name,
    required this.repository,
    this.initialText,
    this.share = const SystemShareChannel(),
  });
```

In `_share()`, replace the `SharePlus.instance.share(ShareParams(...))` call with:
```dart
      await widget.share.share([file.path], subject: widget.name);
```

- [ ] **Step 5: Route `PageViewerScreen` + thread to the two sub-screens**

In `lib/features/library/page_viewer_screen.dart`:

Replace the import line `import 'package:share_plus/share_plus.dart';` with:
```dart
import 'share_channel.dart';
```

Add a field + constructor default (after `printer`):
```dart
  final DocumentPrinter printer;
  final ShareChannel share;
  const PageViewerScreen({
    super.key,
    required this.documentId,
    required this.name,
    required this.repository,
    this.dependencies = const ScanDependencies(),
    this.printer = const SystemDocumentPrinter(),
    this.share = const SystemShareChannel(),
  });
```

Change `_shareQuietly` to delegate to the channel (keep the swallow for prod resilience):
```dart
  Future<void> _shareQuietly(File file) async {
    try {
      await widget.share.share([file.path], subject: _name);
    } catch (_) {/* share unavailable (e.g. host test) — ignore */}
  }
```

Thread the channel into the two screens this file constructs. Change the `PdfPreviewScreen(...)` construction (around line 104) to:
```dart
          builder: (_) => PdfPreviewScreen(
              pdfPath: file.path, name: _name, share: widget.share),
```

Change the `RecognizedTextScreen(...)` construction (around line 304) to add `share: widget.share,`:
```dart
        builder: (_) => RecognizedTextScreen(
          documentId: widget.documentId,
          position: page.position,
          name: _name,
          initialText: page.ocrText,
          repository: widget.repository,
          share: widget.share,
        ),
```

- [ ] **Step 6: Thread `share` from `HomeScreen` into the viewer**

In `lib/features/library/home_screen.dart`, in `_openDocument`'s `PageViewerScreen(...)` construction (around line 116), after `printer: widget.libraryDependencies.printer,` add:
```dart
          share: widget.libraryDependencies.share,
```

- [ ] **Step 7: Run the routing tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/share_routing_test.dart`
Expected: PASS (3/3).

- [ ] **Step 8: Confirm the existing protect/preview tests still pass**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_protect_test.dart test/features/library/pdf_preview_screen_test.dart`
Expected: PASS. (The default `SystemShareChannel` throws in host tests, but `_shareQuietly` swallows it, so `page_viewer_protect_test` still sees "Protected PDF ready". If `pdf_preview_screen_test.dart` does not exist, run only the protect test.)

- [ ] **Step 9: Verify no stray `share_plus` imports remain outside the seam**

Run: `cd apps/mobile && grep -rn "package:share_plus" lib/`
Expected: exactly one hit — `lib/features/library/share_channel.dart`. If any screen still imports it, remove that import.

- [ ] **Step 10: Commit**

```bash
git add apps/mobile/lib/features/library/home_screen.dart apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/lib/features/library/pdf_preview_screen.dart apps/mobile/lib/features/library/recognized_text_screen.dart apps/mobile/test/features/library/share_routing_test.dart
git commit -m "refactor(r1): route all share sites through ShareChannel seam"
```

---

### Task 3: "Share" action in the documents list

**Files:**
- Modify: `lib/features/library/widgets/documents_list_view.dart` (add `onShare` + "Share" menu item)
- Modify: `lib/features/library/home_screen.dart` (`_shareDocument` + wire `onShare` in both list usages)
- Test: `test/features/library/documents_list_view_test.dart` (add cases)
- Test: `test/features/library/home_share_test.dart` (create)

**Interfaces:**
- Consumes: `LibraryDependencies.share` (Task 1); `DocumentRepository.exportPdf` (existing).
- Produces: `DocumentsListView` gains `final ValueChanged<DocumentSummary>? onShare`; menu item key `document-share-<id>`.

- [ ] **Step 1: Write the failing list-view test**

In `test/features/library/documents_list_view_test.dart`, add these cases inside `main()`:

```dart
  testWidgets('shows a Share item when onShare is set', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentsListView(summaries: [summary(1)], onShare: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-share-1')), findsOneWidget);
  });

  testWidgets('selecting Share invokes onShare with that summary',
      (tester) async {
    DocumentSummary? shared;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentsListView(
            summaries: [summary(2)], onShare: (s) => shared = s),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-menu-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-share-2')));
    await tester.pumpAndSettle();
    expect(shared, isNotNull);
    expect(shared!.document.id, 2);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/mobile && flutter test test/features/library/documents_list_view_test.dart`
Expected: FAIL to compile — `DocumentsListView` has no `onShare` parameter.

- [ ] **Step 3: Add `onShare` + the Share item to `DocumentsListView`**

In `lib/features/library/widgets/documents_list_view.dart`, add the field to the class + constructor:

```dart
  final ValueChanged<DocumentSummary>? onOpen;
  final ValueChanged<DocumentSummary>? onRename;
  final ValueChanged<DocumentSummary>? onShare;
  const DocumentsListView({
    super.key,
    required this.summaries,
    this.onOpen,
    this.onRename,
    this.onShare,
  });
```

Replace the `trailing:` expression with a value-dispatching menu shown when either callback is present:

```dart
          trailing: (onRename == null && onShare == null)
              ? null
              : PopupMenuButton<String>(
                  key: Key('document-menu-${d.id}'),
                  tooltip: 'Document options',
                  onSelected: (v) {
                    if (v == 'rename') onRename?.call(s);
                    if (v == 'share') onShare?.call(s);
                  },
                  itemBuilder: (context) => [
                    if (onShare != null)
                      PopupMenuItem<String>(
                        key: Key('document-share-${d.id}'),
                        value: 'share',
                        child: const Text('Share'),
                      ),
                    if (onRename != null)
                      PopupMenuItem<String>(
                        key: Key('document-rename-${d.id}'),
                        value: 'rename',
                        child: const Text('Rename'),
                      ),
                  ],
                ),
```

- [ ] **Step 4: Run the list-view tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/documents_list_view_test.dart`
Expected: PASS (existing rename cases + the 2 new Share cases). The "omits the rename menu when onRename is null" case still passes because `onShare` is also null there.

- [ ] **Step 5: Write the failing HomeScreen share test**

Create `test/features/library/home_share_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/library_dependencies.dart';

import '../../support/fake_library.dart';

void main() {
  HomeScreen homeWith(FakeDocumentRepository repo, FakeShareChannel share) =>
      HomeScreen(
        libraryDependencies: LibraryDependencies(
          createRepository: () async => repo,
          share: share,
        ),
      );

  final doc = Document(
    id: 1,
    name: 'Report',
    createdAt: DateTime.utc(2026, 7, 2),
    modifiedAt: DateTime.utc(2026, 7, 2),
  );

  testWidgets('Share on a document exports its PDF and hands it to the channel',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [doc]);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-share-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.exportedIds, contains(1));
    expect(share.calls, 1);
    expect(share.lastFilePaths!.single, endsWith('.pdf'));
    expect(share.lastSubject, 'Report');
  });

  testWidgets('a failing export shows a share error', (tester) async {
    final repo = FakeDocumentRepository(documents: [doc], throwOnExport: true);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-share-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 0);
    expect(find.text("Couldn't share"), findsOneWidget);
  });
}
```

- [ ] **Step 6: Run to verify failure**

Run: `cd apps/mobile && flutter test test/features/library/home_share_test.dart`
Expected: FAIL — no `_shareDocument` handler / no `onShare` wired in `HomeScreen`.

- [ ] **Step 7: Add `_shareDocument` and wire `onShare`**

In `lib/features/library/home_screen.dart`, add the handler after `_renameDocument`:

```dart
  Future<void> _shareDocument(DocumentSummary s) async {
    final repo = _repository;
    if (repo == null) return;
    try {
      final file = await repo.exportPdf(s.document.id);
      await widget.libraryDependencies.share
          .share([file.path], subject: s.document.name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't share")),
      );
    }
  }
```

Wire `onShare: _shareDocument,` into **both** `DocumentsListView(...)` usages in `_buildBody` — the search branch (after `onRename: _renameDocument,`) and the normal branch (after `onRename: _renameDocument,`).

- [ ] **Step 8: Run the HomeScreen share tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/home_share_test.dart`
Expected: PASS (2/2).

- [ ] **Step 9: Library group + analyze**

Set the DARTCV env if a test errors on `libdartcv`: `bash /Users/pablohpsilva/Documents/camscanner-light/scripts/setup-cv-host-test.sh` then export `DARTCV_LIB_PATH=/tmp/dartcv_lib/lib/libdartcv.dylib` + `DYLD_LIBRARY_PATH=/tmp/dartcv_lib/lib`.

Run: `cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 10: Commit**

```bash
git add apps/mobile/lib/features/library/widgets/documents_list_view.dart apps/mobile/lib/features/library/home_screen.dart apps/mobile/test/features/library/documents_list_view_test.dart apps/mobile/test/features/library/home_share_test.dart
git commit -m "feat(r1): Share a document's PDF from the library list"
```

---

### Task 4: BDD, on-device test, verify script, plans index

**Files:**
- Modify: `test/support/fake_library.dart` (inject + record `FakeShareChannel` in `tempLibraryDependencies`)
- Create: `integration_test/r1_share_document.feature`
- Create step defs: `test/step/i_share_the_first_document.dart`, `test/step/the_document_is_handed_to_the_share_sheet.dart`
- Generate: `integration_test/r1_share_document_test.dart` (build_runner; committed)
- Create: `integration_test/r1_share_document_device_test.dart` (deterministic export→share→%PDF on device)
- Create: `scripts/verify/r1.sh` (repo root)
- Modify: `docs/superpowers/plans/00-plans-index.md`

**Interfaces:**
- Consumes: `FakeShareChannel`, `lastBddShareChannel`, `tempLibraryDependencies` (Tasks 1/3); `document-menu-1` / `document-share-1` keys (Task 3).

- [ ] **Step 1: Inject + record the fake channel in the BDD launch deps**

In `test/support/fake_library.dart`, convert `tempLibraryDependencies()` to a block body that installs a recording fake channel. Replace the existing arrow-body definition with:

```dart
LibraryDependencies tempLibraryDependencies() {
  final share = FakeShareChannel();
  lastBddShareChannel = share;
  return LibraryDependencies(
    createRepository: () async => DriftDocumentRepository(
      db: AppDatabase(NativeDatabase.memory()),
      scrubber: const JpegExifScrubber(),
      fileStore:
          DocumentFileStore(await Directory.systemTemp.createTemp('b1bdd')),
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const PerspectiveWarper(),
    ),
    printer: FakeDocumentPrinter(),
    share: share,
  );
}
```

This is harmless for existing scan BDDs (they never share). It stops the real share sheet from opening and lets the R1 scenario assert what was shared.

- [ ] **Step 2: Write the `.feature`**

Create `integration_test/r1_share_document.feature`:

```gherkin
Feature: Share a document

  Scenario: Share the saved document's PDF from the library
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I share the first document
    Then the document is handed to the share sheet
```

- [ ] **Step 3: Write the new step definitions**

Create `test/step/i_share_the_first_document.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I share the first document
Future<void> iShareTheFirstDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-menu-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('document-share-1')));
  await tester.pumpAndSettle();
}
```

Create `test/step/the_document_is_handed_to_the_share_sheet.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_library.dart';

/// Usage: the document is handed to the share sheet
Future<void> theDocumentIsHandedToTheShareSheet(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  final share = lastBddShareChannel;
  expect(share, isNotNull);
  expect(share!.calls, greaterThan(0));
  expect(share.lastFilePaths!.single, endsWith('.pdf'));
}
```

> `the app is launched…`, `I tap the Scan button`, `I capture and accept the first page`, `I tap Done` already exist — reuse. Verify the generated step-function names match the generator's derivation; rename to match if needed.

- [ ] **Step 4: Generate the BDD test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `integration_test/r1_share_document_test.dart` generated. If build_runner rewrote unrelated generated files, `git checkout` them so the commit stays scoped to R1.

- [ ] **Step 5: Write the deterministic on-device test**

Create `integration_test/r1_share_document_device_test.dart`:

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
import 'package:mobile/features/library/pdf/ocr_pdf_text_layer.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/share_channel.dart';

import '../test/support/fake_library.dart';

String _dec(List<int> b) {
  final s = StringBuffer();
  for (final c in b) {
    s.writeCharCode(c);
  }
  return s.toString();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exportPdf output shared through the channel is a valid PDF',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('r1dev');
    final db = AppDatabase(NativeDatabase.memory());
    final store = DocumentFileStore(base);
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(textLayer: OcrPdfTextLayer()),
      warper: const HybridWarper(),
    );

    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Doc', createdAt: now, modifiedAt: now));
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, jpeg);
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id, position: 1, relativeImagePath: rel));

    final pdf = await repo.exportPdf(id);

    // Route the produced file through a recording channel (as the UI does).
    final ShareChannel share = FakeShareChannel();
    await share.share([pdf.path], subject: 'Doc');
    final fake = share as FakeShareChannel;

    expect(fake.lastFilePaths!.single, pdf.path);
    expect(_dec((await pdf.readAsBytes()).sublist(0, 4)), '%PDF');

    await db.close();
    await base.delete(recursive: true);
  });
}
```

- [ ] **Step 6: Write the verify script**

Create `scripts/verify/r1.sh` (repo root), mirroring `scripts/verify/n1.sh`:

```bash
#!/usr/bin/env bash
# Verify R1 (share a document) acceptance criteria.
# Run from repository root: bash scripts/verify/r1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== R1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "ShareChannel seam exists" \
  "apps/mobile/lib/features/library/share_channel.dart" \
  "abstract interface class ShareChannel"

assert_file_has "SystemShareChannel implementation exists" \
  "apps/mobile/lib/features/library/share_channel.dart" \
  "class SystemShareChannel implements ShareChannel"

assert_file_has "LibraryDependencies exposes the channel" \
  "apps/mobile/lib/features/library/library_dependencies.dart" \
  "ShareChannel share"

assert_file_has "documents list wires Share" \
  "apps/mobile/lib/features/library/widgets/documents_list_view.dart" \
  "document-share-"

assert_file_has "home screen shares via exportPdf" \
  "apps/mobile/lib/features/library/home_screen.dart" \
  "_shareDocument"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/r1_share_document.feature" \
  "Share a document"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/r1_share_document_test.dart" \
  "share"

# share_plus must be isolated to the seam (exactly one importer).
COUNT="$(grep -rl "package:share_plus" apps/mobile/lib/ | wc -l | tr -d ' ')"
if [[ "$COUNT" == "1" ]]; then
  pass "share_plus imported only by the seam"
else
  fail "share_plus imported by $COUNT files (want 1 — the seam)"
fi

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device R1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device share PDF test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/r1_share_document_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/r1_share_document_test.dart"
fi

echo "== R1 verification complete =="
```

Make it executable: `chmod +x scripts/verify/r1.sh`.

> `pass`/`fail`/`warn`/`require_tool`/`assert_file_has`/`assert_cmd` are the helpers `lib.sh` defines (verified — there is no `assert_eq`). The `pass`/`fail` block above uses them directly.

- [ ] **Step 7: Host verify + analyze**

Run: `cd apps/mobile && flutter test && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 8: Update the plans index**

In `docs/superpowers/plans/00-plans-index.md`, add after the Q1 row:

```markdown
| R1 | Share a document's PDF (system share sheet) | 12 | `2026-07-02-r1-share-documents.md` | ✅ **built & gated** |
```

Do NOT change Feature 12's status elsewhere — JPG sharing (R2) is still pending, so Feature 12 as a whole is not done.

- [ ] **Step 9: Commit**

```bash
git add apps/mobile/test/support/fake_library.dart apps/mobile/integration_test/r1_share_document.feature apps/mobile/integration_test/r1_share_document_test.dart apps/mobile/integration_test/r1_share_document_device_test.dart apps/mobile/test/step/i_share_the_first_document.dart apps/mobile/test/step/the_document_is_handed_to_the_share_sheet.dart scripts/verify/r1.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(r1): BDD + on-device share tests, verify script, index"
```

---

## Self-Review

- **Spec coverage:**
  - `ShareChannel` interface + `SystemShareChannel` → Task 1. ✅
  - `LibraryDependencies.share` composition root → Task 1. ✅
  - Three existing sites routed through the channel; `HomeScreen → PageViewerScreen → {PdfPreviewScreen, RecognizedTextScreen}` threading → Task 2. ✅
  - Library-list "Share" (shares the PDF via `exportPdf`) → Task 3. ✅
  - Trust-upstream scrub guarantee (share `exportPdf`'s already-scrubbed output; no re-scrub) → Tasks 3/4 assert the shared file is the `exportPdf` result + `%PDF`. ✅
  - Link-share/fax "behind an interface" criterion → Task 1 unit test (`isA<ShareChannel>`). ✅
  - BDD + on-device + verify script + index → Task 4. ✅
  - JPG-share deferred to R2; Feature 12 row stays open → Global Constraints + Task 4 Step 8. ✅
- **Placeholder scan:** every code step shows complete code; the only conditional is the `assert_eq`/`fail` helper check in Task 4 Step 6, which gives the exact fallback. ✅
- **Type consistency:** `ShareChannel.share(List<String> filePaths, {String? subject})` is identical across the seam, `SystemShareChannel`, `FakeShareChannel`, and all four call sites; every screen's `share` param defaults to `const SystemShareChannel()`; menu key `document-share-<id>` matches between `DocumentsListView`, tests, and the BDD step. ✅
- **Regression safety:** `DocumentsListView` menu now shows when `onRename != null || onShare != null` and dispatches by value — the existing "omits menu when onRename null" and "selecting Rename" tests still hold (verified against `documents_list_view_test.dart`); `page_viewer_protect_test` still passes because `_shareQuietly` swallows the default channel's host-test failure. ✅
- **Out of scope kept out:** no JPG sharing, no fax, no link-share, no print changes (N1 untouched). ✅
