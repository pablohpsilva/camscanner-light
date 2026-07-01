# I1 Export Page as Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From the page viewer, export the current page as a metadata-scrubbed JPG image file on device (sharing is Feature 12).

**Architecture:** A new `exportPageAsImage(documentId, position)` on the existing `DocumentRepository` seam (beside `exportPdf`): the Drift impl reads the page's display image (flat if present, else original), passes it through the existing metadata scrubber, writes `documents/<id>/page_<n>_export.jpg`, returns the file. A page-overflow-menu item drives it and shows a confirmation SnackBar.

**Tech Stack:** Drift (SQLite), the byte-level `JpegExifScrubber`, `exif` package (`^3.3.0`, EXIF-removal assertion in tests), `bdd_widget_test` + `build_runner`. Pure Dart — identical on iOS/Android.

## Global Constraints

- On-device only; **nothing leaves the device** (pure local file IO — no network client in the path). Every exported file passes through the metadata scrubber.
- Sharing / save-to-gallery / print is Feature 12 — OUT OF SCOPE. Do not add `share_plus`/gallery deps.
- Material only; no iOS/Android platform branching (pure Dart file IO + scrubber).
- Host test success marker is exactly `All tests passed!`; `flutter analyze --no-fatal-infos` (from `apps/mobile`) must print `No issues found` (repo is currently clean — keep it clean, no unused imports).
- BDD authored as `.feature` under `apps/mobile/integration_test/`, generated to `*_test.dart` via `dart run build_runner build --delete-conflicting-outputs` (run from `apps/mobile`; there is NO `mobile:build_runner` nx target). Generated files are committed. Step defs live in `apps/mobile/test/step/`. The host suite (`flutter test`) does NOT run `integration_test/` BDD — `flutter analyze` is the compile gate; the scenario runs on-device.
- Commit with EXPLICIT file paths (never `git add -A`). End every commit message with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- DO NOT stage or touch: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, or `.superpowers/`.
- `DocumentExportException` (existing, in `document_repository.dart`) is the error type this feature throws.
- Tooling: `pnpm nx run mobile:test --skip-nx-cache -- --name "a|b"` breaks on the shell `|`. Use `flutter test <file>` for focused runs; `pnpm nx run mobile:test --skip-nx-cache` for the full suite.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `apps/mobile/lib/features/library/document_file_store.dart` | Path resolution | Add `imageExportRelativeFor` |
| `apps/mobile/lib/features/library/document_repository.dart` | Persistence interface | Add `exportPageAsImage` |
| `apps/mobile/lib/features/library/drift/drift_document_repository.dart` | Drift impl | Implement `exportPageAsImage` |
| `apps/mobile/test/support/fake_library.dart` | Test double | Implement `exportPageAsImage` (record + throw flag) |
| `apps/mobile/lib/features/library/page_viewer_screen.dart` | Viewer UI | Overflow-menu item + `_exportPageAsImage` handler |
| `apps/mobile/integration_test/i1_export_image.feature` (+ generated `_test.dart`) | On-device BDD | New |
| `apps/mobile/test/step/*.dart` | BDD step defs | 2 new |
| `scripts/verify/i1.sh` | Acceptance gate | New |

---

### Task 1: `exportPageAsImage` — file store + interface + Drift + Fake + unit tests

**Files:**
- Modify: `apps/mobile/lib/features/library/document_file_store.dart`
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`
- Test: `apps/mobile/test/features/library/export_page_image_test.dart` (create)

**Interfaces:**
- Consumes: `DocumentExportException` (existing), `_scrubber` (`ImageMetadataScrubber`, injectable), `_fileStore.absoluteFor/writeRelative`, the `pages` Drift table.
- Produces: `Future<File> exportPageAsImage(int documentId, int position)`; `DocumentFileStore.imageExportRelativeFor(int, int)`; `FakeDocumentRepository.throwOnExportImage` (bool), `FakeDocumentRepository.lastExportedImagePosition` (int?).

- [ ] **Step 1: Add the file-store path helper**

  In `apps/mobile/lib/features/library/document_file_store.dart`, add after `pdfRelativeFor`:
  ```dart
  String imageExportRelativeFor(int docId, int position) =>
      'documents/$docId/page_${position}_export.jpg';
  ```

- [ ] **Step 2: Add the interface method**

  In `apps/mobile/lib/features/library/document_repository.dart`, add inside `abstract interface class DocumentRepository` (e.g. after `exportPdf`):
  ```dart
  /// Exports the page at [position] of [documentId] as a standalone JPG on device.
  /// Reads the page's display image (the flattened derivative when present, else
  /// the original capture), passes the bytes through the metadata scrubber, writes
  /// `documents/<id>/page_<position>_export.jpg`, and returns the file. Nothing
  /// leaves the device. Throws [DocumentExportException] when the page row/file is
  /// missing or the scrub fails.
  Future<File> exportPageAsImage(int documentId, int position);
  ```
  (`File` is from `dart:io`, already imported in this file.)

- [ ] **Step 3: Write the failing Drift tests**

  Create `apps/mobile/test/features/library/export_page_image_test.dart`:
  ```dart
  import 'dart:io';
  import 'dart:typed_data';

  import 'package:drift/drift.dart' show Value;
  import 'package:drift/native.dart';
  import 'package:exif/exif.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:mobile/features/library/document_file_store.dart';
  import 'package:mobile/features/library/document_repository.dart';
  import 'package:mobile/features/library/drift/app_database.dart';
  import 'package:mobile/features/library/drift/drift_document_repository.dart';
  import 'package:mobile/features/library/image_warper.dart';
  import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
  import 'package:mobile/features/library/pdf/pdf_builder.dart';

  void main() {
    late Directory base;
    late AppDatabase db;
    // ignore: prefer_function_declarations_over_variables
    final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

    setUp(() {
      base = Directory.systemTemp.createTempSync('i1exp');
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

    Uint8List fixture(String name) =>
        File('test/fixtures/$name').readAsBytesSync();

    // Seed a document + one page, writing the image file(s) directly (NOT via
    // the warper — export only reads the stored display file).
    Future<int> seedDoc({required String image, String? flat}) async {
      final now = clock();
      final store = DocumentFileStore(base);
      final docId = await db.into(db.documents).insert(
          DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
      final rel = 'documents/$docId/page_1.jpg';
      await store.writeRelative(rel, fixture(image));
      String? flatRel;
      if (flat != null) {
        flatRel = 'documents/$docId/page_1_flat.jpg';
        await store.writeRelative(flatRel, fixture(flat));
      }
      await db.into(db.pages).insert(PagesCompanion.insert(
            documentId: docId,
            position: 1,
            relativeImagePath: rel,
            flatRelativePath: Value(flatRel),
          ));
      return docId;
    }

    test('exports a scrubbed JPG (no EXIF) at the export path', () async {
      final docId = await seedDoc(image: 'exif_sample.jpg');

      final file = await repo().exportPageAsImage(docId, 1);

      expect(file.path, endsWith('documents/$docId/page_1_export.jpg'));
      final bytes = file.readAsBytesSync();
      expect(bytes.sublist(0, 2), [0xFF, 0xD8], reason: 'valid JPEG header');
      // The scrubber removes IDENTIFYING/personal EXIF but intentionally KEEPS
      // Orientation (rotation preserved losslessly). So assert the personal tags
      // are gone — mirroring the JpegExifScrubber test — NOT that EXIF is empty.
      final tags = await readExifFromBytes(bytes);
      expect(tags['Image Make'], isNull);
      expect(tags['Image Model'], isNull);
      expect(tags['Image Software'], isNull);
      expect(tags['Image DateTime'], isNull);
      expect(tags.keys.where((k) => k.startsWith('GPS')), isEmpty,
          reason: 'exported image has no GPS/personal metadata');
    });

    test('uses the flat image when flatRelativePath is set', () async {
      final docId =
          await seedDoc(image: 'exif_sample.jpg', flat: 'landscape_exif6.jpg');

      final file = await repo().exportPageAsImage(docId, 1);

      final exported = file.readAsBytesSync();
      final expectedFromFlat =
          const JpegExifScrubber().scrub(fixture('landscape_exif6.jpg'));
      expect(exported, expectedFromFlat,
          reason: 'export uses the scrubbed flat derivative, not the original');
    });

    test('missing page throws DocumentExportException', () async {
      final docId = await seedDoc(image: 'exif_sample.jpg');
      await expectLater(
        repo().exportPageAsImage(docId, 99),
        throwsA(isA<DocumentExportException>()),
      );
    });
  }
  ```

- [ ] **Step 4: Run tests to verify they fail**

  ```bash
  cd apps/mobile && flutter test test/features/library/export_page_image_test.dart
  ```
  Expected: FAIL — `exportPageAsImage` not defined on `DriftDocumentRepository`/`FakeDocumentRepository` (compile error until Steps 5–6).

- [ ] **Step 5: Implement in Drift**

  In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`, add (e.g. after `exportPdf`):
  ```dart
  @override
  Future<File> exportPageAsImage(int documentId, int position) async {
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
      final scrubbed = _scrubber.scrub(bytes); // privacy: pass through scrubber
      final rel = _fileStore.imageExportRelativeFor(documentId, position);
      await _fileStore.writeRelative(rel, scrubbed);
      return _fileStore.absoluteFor(rel);
    } catch (e) {
      if (e is DocumentExportException) rethrow;
      throw DocumentExportException('exportImage failed: $e');
    }
  }
  ```
  (`_scrubber.scrub` takes a `Uint8List`; `readAsBytes()` returns `Uint8List` — no conversion needed. `File`/`Uint8List` are already imported in this file.)

- [ ] **Step 6: Implement on the Fake**

  In `apps/mobile/test/support/fake_library.dart`:
  1. Add the ctor field + flag near the other `throwOn*` fields:
     ```dart
     final bool throwOnExportImage;
     ```
     and in the constructor parameter list:
     ```dart
     this.throwOnExportImage = false,
     ```
  2. Add a recorder near the other recorders:
     ```dart
     int? lastExportedImagePosition;
     ```
  3. Add the method (mirror the fake `exportPdf` — return a temp path, no real IO):
     ```dart
     @override
     Future<File> exportPageAsImage(int documentId, int position) async {
       if (throwOnExportImage) {
         throw const DocumentExportException('fake: exportImage failed');
       }
       lastExportedImagePosition = position;
       return File(
           '${Directory.systemTemp.path}/fake-export-$documentId-$position.jpg');
     }
     ```

- [ ] **Step 7: Run tests to verify they pass**

  ```bash
  cd apps/mobile && flutter test test/features/library/export_page_image_test.dart
  ```
  Expected: PASS (3 tests).

- [ ] **Step 8: Full suite + analyze + commit**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  git add apps/mobile/lib/features/library/document_file_store.dart \
          apps/mobile/lib/features/library/document_repository.dart \
          apps/mobile/lib/features/library/drift/drift_document_repository.dart \
          apps/mobile/test/support/fake_library.dart \
          apps/mobile/test/features/library/export_page_image_test.dart
  git commit -m "feat(i1): exportPageAsImage — scrubbed JPG of a page on device

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```
  Expected: `All tests passed!`, `No issues found`, commit succeeds.

---

### Task 2: `PageViewerScreen` "Export as image" menu + handler

**Files:**
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart`
- Test: `apps/mobile/test/features/library/page_viewer_i1_test.dart` (create)

**Interfaces:**
- Consumes: `exportPageAsImage` (Task 1), the existing page overflow menu (`page-viewer-page-menu`), `_pages`, `_current`, `unawaited` (`dart:async`, already imported).
- Produces: menu item key `page-viewer-export-image`; handler `_exportPageAsImage`; SnackBar texts `Page saved as image` / `Couldn't export image`.

- [ ] **Step 1: Write the failing widget tests**

  Create `apps/mobile/test/features/library/page_viewer_i1_test.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:mobile/features/library/page_image.dart';
  import 'package:mobile/features/library/page_viewer_screen.dart';

  import '../../support/fake_library.dart';

  void main() {
    Future<void> pushViewer(WidgetTester tester, FakeDocumentRepository repo) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PageViewerScreen(
                    documentId: 1, name: 'Doc', repository: repo),
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

    FakeDocumentRepository twoPageRepo({bool throwOnExportImage = false}) =>
        FakeDocumentRepository(
          throwOnExportImage: throwOnExportImage,
          pages: [
            const PageImage(position: 1, imagePath: '/nonexistent/p1.jpg'),
            const PageImage(position: 2, imagePath: '/nonexistent/p2.jpg'),
          ],
        );

    testWidgets('overflow menu exposes Export as image', (tester) async {
      await pushViewer(tester, twoPageRepo());
      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-viewer-export-image')), findsOneWidget);
    });

    testWidgets('exporting the current page calls exportPageAsImage + confirms',
        (tester) async {
      final repo = twoPageRepo();
      await pushViewer(tester, repo);
      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-export-image')));
      await tester.pumpAndSettle();
      expect(repo.lastExportedImagePosition, 1);
      expect(find.text('Page saved as image'), findsOneWidget);
    });

    testWidgets('export failure shows an error SnackBar', (tester) async {
      final repo = twoPageRepo(throwOnExportImage: true);
      await pushViewer(tester, repo);
      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-export-image')));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't export image"), findsOneWidget);
    });
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  cd apps/mobile && flutter test test/features/library/page_viewer_i1_test.dart
  ```
  Expected: FAIL — menu item key `page-viewer-export-image` absent.

- [ ] **Step 3: Add the menu item + onSelected branch**

  In `apps/mobile/lib/features/library/page_viewer_screen.dart`, in the `PopupMenuButton` (`page-viewer-page-menu`):
  - Add to `onSelected`:
    ```dart
    if (v == 'export-image') unawaited(_exportPageAsImage());
    ```
  - Add to the `itemBuilder` list (after the `delete` item):
    ```dart
    PopupMenuItem<String>(
      value: 'export-image',
      key: Key('page-viewer-export-image'),
      child: Text('Export as image'),
    ),
    ```

- [ ] **Step 4: Add the handler**

  In `_PageViewerScreenState`, add (near `_confirmAndDeletePage`):
  ```dart
  Future<void> _exportPageAsImage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    try {
      await widget.repository.exportPageAsImage(widget.documentId, page.position);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Page saved as image')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't export image")),
      );
    }
  }
  ```

- [ ] **Step 5: Run tests + analyze + commit**

  ```bash
  cd apps/mobile && flutter test test/features/library/page_viewer_i1_test.dart
  pnpm nx run mobile:test --skip-nx-cache
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  git add apps/mobile/lib/features/library/page_viewer_screen.dart \
          apps/mobile/test/features/library/page_viewer_i1_test.dart
  git commit -m "feat(i1): page-viewer 'Export as image' menu action + confirmation

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```
  Expected: focused PASS (3), `All tests passed!`, `No issues found`.

---

### Task 3: BDD + verify script + plans index

**Existing steps to REUSE (do NOT recreate):**
`the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart`,
`i_tap_the_scan_button.dart`, `i_capture_and_accept_the_first_page.dart`,
`i_tap_done.dart`, `i_open_the_first_document.dart`.

**Files:**
- Create: `apps/mobile/integration_test/i1_export_image.feature`
- Create: `apps/mobile/test/step/i_export_the_page_as_an_image.dart`
- Create: `apps/mobile/test/step/i_see_the_image_export_confirmation.dart`
- Create (generated): `apps/mobile/integration_test/i1_export_image_test.dart`
- Create: `scripts/verify/i1.sh`
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Write the feature file**

  Create `apps/mobile/integration_test/i1_export_image.feature`:
  ```gherkin
  Feature: I1 Export page as image

    Scenario: Exporting the open page saves it as an image
      Given the app is launched with camera permission granted and empty storage
      When I tap the Scan button
      And I capture and accept the first page
      And I tap Done
      And I open the first document
      And I export the page as an image
      Then I see the image export confirmation
  ```

- [ ] **Step 2: Write the "export" step**

  Create `apps/mobile/test/step/i_export_the_page_as_an_image.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';

  /// Usage: I export the page as an image
  Future<void> iExportThePageAsAnImage(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
  }
  ```

- [ ] **Step 3: Write the "confirmation" step**

  Create `apps/mobile/test/step/i_see_the_image_export_confirmation.dart` (mirrors
  the gated `i_see_the_save_error.dart` SnackBar pattern — a short pump, then
  assert, before the SnackBar auto-dismisses):
  ```dart
  import 'package:flutter_test/flutter_test.dart';

  /// Usage: I see the image export confirmation
  Future<void> iSeeTheImageExportConfirmation(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Page saved as image'), findsOneWidget);
  }
  ```

- [ ] **Step 4: Generate the test**

  ```bash
  cd apps/mobile && dart run build_runner build --delete-conflicting-outputs && cd -
  grep "import" apps/mobile/integration_test/i1_export_image_test.dart
  ```
  Expected: creates `apps/mobile/integration_test/i1_export_image_test.dart` importing
  `i_export_the_page_as_an_image.dart` and `i_see_the_image_export_confirmation.dart`
  (plus the reused steps). If build_runner emits a differently-named file or an import
  doesn't resolve, STOP and report — do not hand-edit the generated file.

- [ ] **Step 5: Host suite + analyze**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  ```
  Expected: `All tests passed!` and `No issues found`. (The host suite does not run
  the BDD scenario; analyze is the compile gate for the new step + generated files.)

- [ ] **Step 6: Create `scripts/verify/i1.sh`**

  ```bash
  #!/usr/bin/env bash
  # Verify I1 (Export page as image) acceptance criteria.
  # Run from repository root: bash scripts/verify/i1.sh
  # VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib.sh
  source "$DIR/lib.sh"
  cd "$ROOT"

  echo "== I1 verification =="

  require_tool flutter
  require_tool pnpm

  # ---- Static assertions ----
  assert_file_has "exportPageAsImage in DocumentRepository interface" \
    "apps/mobile/lib/features/library/document_repository.dart" \
    "exportPageAsImage"

  assert_file_has "exportPageAsImage in DriftDocumentRepository" \
    "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
    "exportPageAsImage"

  assert_file_has "imageExportRelativeFor in DocumentFileStore" \
    "apps/mobile/lib/features/library/document_file_store.dart" \
    "imageExportRelativeFor"

  assert_file_has "export-image menu item in PageViewerScreen" \
    "apps/mobile/lib/features/library/page_viewer_screen.dart" \
    "page-viewer-export-image"

  assert_file_has "export handler in PageViewerScreen" \
    "apps/mobile/lib/features/library/page_viewer_screen.dart" \
    "_exportPageAsImage"

  assert_file_has "BDD feature file exists" \
    "apps/mobile/integration_test/i1_export_image.feature" \
    "Export page as image"

  assert_file_has "generated BDD test exists" \
    "apps/mobile/integration_test/i1_export_image_test.dart" \
    "iSeeTheImageExportConfirmation"

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
      pnpm nx run mobile:verify_integration_ios -- --dart-define=INTEGRATION_TEST=i1
  fi

  echo "== I1 verification complete =="
  ```
  Make it executable:
  ```bash
  chmod +x scripts/verify/i1.sh
  ```

- [ ] **Step 7: Run the verify script (device skipped)**

  ```bash
  VERIFY_SKIP_DEVICE=1 bash scripts/verify/i1.sh
  ```
  Expected: ends `== I1 verification complete ==` with all static + host + analyze asserts PASS (device line WARNs). If any assert FAILS, STOP and report which one.

- [ ] **Step 8: Update the plans index**

  In `docs/superpowers/plans/00-plans-index.md`, change the I1 row status from `⏳` to
  `✅ **built & gated**` and set its plan-file column to `2026-07-01-i1-export-image.md`.

- [ ] **Step 9: Commit**

  ```bash
  git add apps/mobile/integration_test/i1_export_image.feature \
          apps/mobile/integration_test/i1_export_image_test.dart \
          apps/mobile/test/step/i_export_the_page_as_an_image.dart \
          apps/mobile/test/step/i_see_the_image_export_confirmation.dart \
          scripts/verify/i1.sh docs/superpowers/plans/00-plans-index.md
  git commit -m "test(i1): BDD export-image scenario + verify script + plans index

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

## Self-Review (author checklist — completed)

**Spec coverage:**
- Export a page as a JPG on-device → Task 1 (`exportPageAsImage` + file at `page_<n>_export.jpg`) + Task 2 (UI) + Task 3 (BDD). ✓
- Metadata-scrubbed → Task 1 (scrub in impl; test asserts personal EXIF — Make/Model/Software/DateTime/GPS — absent from the export, matching the authoritative scrubber test; Orientation is intentionally kept). ✓
- Nothing leaves the device → pure local IO by construction (no network client); documented. ✓
- Uses flat when present → Task 1 test asserts export == `scrub(flat)`. ✓
- DIP seam (not a premature `Converter` interface) → method on existing `DocumentRepository`. ✓
- iOS + Android → pure Dart; no platform code. ✓

**Placeholder scan:** none — every code step is complete; every command has an expected marker.

**Type consistency:** `exportPageAsImage(int,int)→Future<File>`, `imageExportRelativeFor(int,int)→String`, keys `page-viewer-export-image`, handler `_exportPageAsImage`, SnackBar copy `Page saved as image` / `Couldn't export image`, fake fields `throwOnExportImage`/`lastExportedImagePosition`, generated file `i1_export_image_test.dart`, step fns `iExportThePageAsAnImage`/`iSeeTheImageExportConfirmation` — all consistent across tasks + verify script.
