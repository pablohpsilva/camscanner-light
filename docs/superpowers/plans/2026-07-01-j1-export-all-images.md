# J1 — Export all pages as images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A document-level "Export all pages as images" that exports every page as a scrubbed JPG, reusing the per-page export (I1).

**Architecture:** `DocumentRepository.exportAllPagesAsImages(documentId)` loops the document's pages and delegates each to the existing `exportPageAsImage` (DRY). The page viewer gets an overflow-menu action + confirmation snackbar.

**Tech Stack:** Flutter/Dart, drift, `bdd_widget_test` + `build_runner`.

## Global Constraints

- **iOS + Android**: pure Dart file IO + Material menu/snackbar; no platform channels.
- **On-device only**: images stay in the app's document folder (like I1); no native sheet in the gated path.
- **DRY**: reuse `exportPageAsImage` per page — no new file/scrub logic.
- **TDD/BDD first**; SOLID/KISS.
- **Commits**: explicit file paths (never `git add -A`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Do NOT touch**: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, `.superpowers/`.
- **On-device gate**: BDD + integration tests pass on Samsung `RZCY51D0T1K`. Host `flutter test` skips `integration_test/`.
- Paths relative to `apps/mobile/` unless noted (`scripts/`, `docs/` are repo-root).

---

### Task 1: `exportAllPagesAsImages` repository method

**Files:**
- Modify: `lib/features/library/document_repository.dart` (interface)
- Modify: `lib/features/library/drift/drift_document_repository.dart` (impl)
- Modify: `test/support/fake_library.dart` (fake)
- Test: `test/features/library/export_all_images_test.dart` (create)

**Interfaces:**
- Consumes: `getDocumentPages`, existing `exportPageAsImage`, `DocumentExportException`.
- Produces: `Future<List<File>> exportAllPagesAsImages(int documentId)`.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/export_all_images_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

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
    base = await Directory.systemTemp.createTemp('j1all');
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

  Future<int> seedDoc(int pageCount) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));
    for (var pos = 1; pos <= pageCount; pos++) {
      final rel = 'documents/$id/page_$pos.jpg';
      await store.writeRelative(rel, jpeg);
      await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id, position: pos, relativeImagePath: rel));
    }
    return id;
  }

  test('exports every page as a JPG, in order', () async {
    final id = await seedDoc(2);
    final files = await repo.exportAllPagesAsImages(id);

    expect(files.length, 2);
    expect(files[0].path, endsWith('page_1_export.jpg'));
    expect(files[1].path, endsWith('page_2_export.jpg'));
    for (final f in files) {
      final bytes = await f.readAsBytes();
      expect(bytes.sublist(0, 2), [0xFF, 0xD8]); // JPEG magic
    }
  });

  test('throws when the document has no pages', () async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Empty', createdAt: now, modifiedAt: now));
    expect(() => repo.exportAllPagesAsImages(id),
        throwsA(isA<DocumentExportException>()));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/export_all_images_test.dart`
Expected: FAIL — `exportAllPagesAsImages` not defined.

- [ ] **Step 3: Add the interface method**

In `lib/features/library/document_repository.dart`, after the `exportPageAsImage` declaration:

```dart
  /// Exports EVERY page of [documentId] as a standalone scrubbed JPG (delegating
  /// to [exportPageAsImage] per page), returning the files in page order.
  /// Nothing leaves the device. Throws [DocumentExportException] when the
  /// document has no pages or any page fails to export.
  Future<List<File>> exportAllPagesAsImages(int documentId);
```

- [ ] **Step 4: Implement in the Drift repository**

In `lib/features/library/drift/drift_document_repository.dart`, add near `exportPageAsImage`:

```dart
  @override
  Future<List<File>> exportAllPagesAsImages(int documentId) async {
    final pages = await getDocumentPages(documentId);
    if (pages.isEmpty) {
      throw const DocumentExportException('exportAll failed: no pages');
    }
    final files = <File>[];
    for (final page in pages) {
      files.add(await exportPageAsImage(documentId, page.position));
    }
    return files;
  }
```

> `getDocumentPages` returns pages in ascending position order, so the files come out in page order. `exportPageAsImage` already throws `DocumentExportException` on a missing file/scrub failure, which propagates.

- [ ] **Step 5: Implement in the fake repository**

In `test/support/fake_library.dart`, add to `FakeDocumentRepository` near `exportPageAsImage`:

```dart
  @override
  Future<List<File>> exportAllPagesAsImages(int documentId) async {
    if (throwOnExportImage) {
      throw const DocumentExportException('fake: exportAll failed');
    }
    final pages = await getDocumentPages(documentId);
    return [
      for (final p in pages)
        File('${Directory.systemTemp.path}/fake-all-$documentId-${p.position}.jpg')
    ];
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/export_all_images_test.dart`
Expected: PASS (2/2).

- [ ] **Step 7: Analyze**

Run: `cd apps/mobile && flutter analyze --no-fatal-infos`
Expected: `No issues found`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/document_repository.dart apps/mobile/lib/features/library/drift/drift_document_repository.dart apps/mobile/test/support/fake_library.dart apps/mobile/test/features/library/export_all_images_test.dart
git commit -m "feat(j1): exportAllPagesAsImages — every page as a scrubbed JPG"
```

---

### Task 2: Page-viewer "Export all as images" action

**Files:**
- Modify: `lib/features/library/page_viewer_screen.dart`
- Test: `test/features/library/page_viewer_export_all_test.dart` (create)

**Interfaces:**
- Consumes: `DocumentRepository.exportAllPagesAsImages`, existing `page-viewer-page-menu` popup.
- Produces: `page-viewer-export-all-images` menu item + `_exportAllImages()`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/library/page_viewer_export_all_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('Export all as images shows a confirmation with the count',
      (tester) async {
    final repo = FakeDocumentRepository(pages: const [
      PageImage(position: 1, imagePath: '/a.jpg'),
      PageImage(position: 2, imagePath: '/b.jpg'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
    await tester.pump(); // let the async export + snackbar schedule
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Exported 2 images'), findsOneWidget);
  });

  testWidgets('a failing export shows an error snackbar', (tester) async {
    final repo = FakeDocumentRepository(
      throwOnExportImage: true,
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Couldn't export images"), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_export_all_test.dart`
Expected: FAIL — no `page-viewer-export-all-images` item.

- [ ] **Step 3: Add the handler**

In `lib/features/library/page_viewer_screen.dart`, add a method near `_exportPageAsImage`:

```dart
  Future<void> _exportAllImages() async {
    try {
      final files =
          await widget.repository.exportAllPagesAsImages(widget.documentId);
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
    }
  }
```

- [ ] **Step 4: Add the menu item**

In the `PopupMenuButton`'s `onSelected`, add:

```dart
              if (v == 'export-all-images') unawaited(_exportAllImages());
```

In `itemBuilder`'s list, add after the existing `export-image` item:

```dart
              PopupMenuItem<String>(
                value: 'export-all-images',
                key: Key('page-viewer-export-all-images'),
                child: Text('Export all as images'),
              ),
```

> `unawaited` is already imported (`dart:async`) and used by the sibling handlers.

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_export_all_test.dart`
Expected: PASS (2/2).

- [ ] **Step 6: Run the library group + analyze**

Run (set the DARTCV env if a test errors on `libdartcv`: `bash /Users/pablohpsilva/Documents/camscanner-light/scripts/setup-cv-host-test.sh` then export `DARTCV_LIB_PATH=/tmp/dartcv_lib/lib/libdartcv.dylib` + `DYLD_LIBRARY_PATH=/tmp/dartcv_lib/lib`):
`cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/test/features/library/page_viewer_export_all_test.dart
git commit -m "feat(j1): page viewer 'Export all as images' with confirmation"
```

---

### Task 3: BDD `.feature`, on-device test, verify script, plans index

**Files:**
- Create: `integration_test/j1_export_all_images.feature`
- Create step defs: `test/step/i_export_all_pages_as_images.dart`, `test/step/i_see_the_all_images_export_confirmation.dart`
- Generate: `integration_test/j1_export_all_images_test.dart` (build_runner; committed)
- Create: `integration_test/j1_export_all_images_device_test.dart` (deterministic Drift export on device)
- Create: `scripts/verify/j1.sh` (repo root)
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Write the `.feature`** (mirrors `i1_export_image.feature` — the real scan flow makes a real image, so no persistent seed needed)

Create `integration_test/j1_export_all_images.feature`:

```gherkin
Feature: Export all pages as images

  Scenario: Exporting all pages of the open document saves them as images
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I export all pages as images
    Then I see the all images export confirmation
```

- [ ] **Step 2: Write the new step definitions**

Create `test/step/i_export_all_pages_as_images.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I export all pages as images
Future<void> iExportAllPagesAsImages(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
  await tester.pumpAndSettle();
}
```

Create `test/step/i_see_the_all_images_export_confirmation.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the all images export confirmation
Future<void> iSeeTheAllImagesExportConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.textContaining('Exported'), findsOneWidget);
}
```

> `the app is launched…`, `I tap the Scan button`, `I capture and accept the first page`, `I tap Done`, `I open the first document` already exist — reuse. Verify the generated function names for the two new steps match the generator's derivation; rename to match if needed.

- [ ] **Step 3: Generate the BDD test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `integration_test/j1_export_all_images_test.dart` generated, importing the two new steps + the reused ones. If build_runner rewrote unrelated generated files, `git checkout` them so the commit stays scoped to J1.

- [ ] **Step 4: Write the deterministic on-device test**

Create `integration_test/j1_export_all_images_device_test.dart`:

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

  testWidgets('exportAllPagesAsImages writes every page as a JPG on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('j1dev');
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
    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));
    for (var pos = 1; pos <= 2; pos++) {
      final rel = 'documents/$id/page_$pos.jpg';
      await store.writeRelative(rel, jpeg);
      await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id, position: pos, relativeImagePath: rel));
    }

    final files = await repo.exportAllPagesAsImages(id);
    expect(files.length, 2);
    for (final f in files) {
      expect(await f.exists(), isTrue);
      expect((await f.readAsBytes()).sublist(0, 2), [0xFF, 0xD8]);
    }

    await db.close();
    await base.delete(recursive: true);
  });
}
```

- [ ] **Step 5: Write the verify script**

Create `scripts/verify/j1.sh` (repo root), mirroring `scripts/verify/o1.sh`:

```bash
#!/usr/bin/env bash
# Verify J1 (export all pages as images) acceptance criteria.
# Run from repository root: bash scripts/verify/j1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== J1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "exportAllPagesAsImages on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "exportAllPagesAsImages"

assert_file_has "exportAllPagesAsImages in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "exportAllPagesAsImages"

assert_file_has "page viewer wires Export all as images" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-export-all-images"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/j1_export_all_images.feature" \
  "Export all pages as images"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/j1_export_all_images_test.dart" \
  "images"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device J1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device export-all test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/j1_export_all_images_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/j1_export_all_images_test.dart"
fi

echo "== J1 verification complete =="
```

Make it executable: `chmod +x scripts/verify/j1.sh`.

- [ ] **Step 6: Host verify + analyze**

Run: `cd apps/mobile && flutter test && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`. (Generated + device integration_test files must compile — analyze covers this.)

- [ ] **Step 7: Update the plans index**

In `docs/superpowers/plans/00-plans-index.md`, add after the O5 row:

```markdown
| J1 | Export all pages as images | 10 | `2026-07-01-j1-export-all-images.md` | ✅ **built & gated** |
```

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/integration_test/j1_export_all_images.feature apps/mobile/integration_test/j1_export_all_images_test.dart apps/mobile/integration_test/j1_export_all_images_device_test.dart apps/mobile/test/step/i_export_all_pages_as_images.dart apps/mobile/test/step/i_see_the_all_images_export_confirmation.dart scripts/verify/j1.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(j1): BDD + on-device export-all-images tests, verify script, index"
```

---

## Self-Review

- **Spec coverage:** repo export-all (Task 1), viewer action + snackbar (Task 2), BDD + device + verify + index (Task 3). ✅
- **DRY:** `exportAllPagesAsImages` delegates entirely to `exportPageAsImage`; no new file/scrub logic. ✅
- **Placeholder scan:** complete code in every step. ✅
- **Type consistency:** `exportAllPagesAsImages(int) → Future<List<File>>` identical across interface/Drift/fake; menu key consistent across Task 2 code and Task 2/3 tests. ✅
- **Out of scope kept out:** no native share sheet, no gallery save, no ZIP. ✅
