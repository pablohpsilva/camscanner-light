# R2 — Share images + close Feature 12 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route the two image-export actions through the existing `ShareChannel` so a page (or all pages) can be shared as JPG via the system share sheet, add a re-entrancy guard to the library-list Share, and close Feature 12.

**Architecture:** Reuse R1's `ShareChannel` seam unchanged. `_exportPageAsImage`/`_exportAllImages` now export-then-`share(...)` instead of writing to app-private storage and showing a "saved" snackbar. `_shareDocument` gains a `_sharing` re-entrancy flag. Tests and the shared image-export BDD steps are rewritten from "saved" assertions to channel assertions.

**Tech Stack:** Flutter/Dart, `share_plus` (via `ShareChannel`), `pdf`, drift, `image`, `bdd_widget_test`.

## Global Constraints

- **Reuse R1's `ShareChannel`** (`share(List<String> filePaths, {String? subject})`) — no seam change. `share_channel.dart` stays the ONLY file importing `package:share_plus`.
- **Change export → share** (not add): the two existing image-export actions now open the share sheet with the scrubbed JPG(s). Menu-item **keys/values unchanged** (`page-viewer-export-image`/`export-image`, `page-viewer-export-all-images`/`export-all-images`); only visible **labels** change to "Share as image" / "Share all as images".
- **No success snackbar** (the OS sheet is the feedback), consistent with R1. Failure snackbars: **"Couldn't share image"** (single) and **"Couldn't share images"** (all). Keep the existing `showExportQualityDialog` and `_exporting` guard.
- **Multi-file share:** "share all" is one `share(...)` call with N `.jpg` paths (no zip).
- **Trust-upstream scrub:** JPGs are already scrubbed by the export pipeline (Q1); no re-scrub.
- **No new `.feature` and no build_runner:** R2 changes only step *bodies* (same names), so the generated i1/j1/q1 tests are unaffected; R2's on-device BDD proof is the rewritten i1 (single) + j1 (all) scenarios. Do NOT run build_runner.
- **TDD/BDD first**; SOLID/KISS/DRY.
- **Commits**: explicit file paths (never `git add -A`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Do NOT commit report files.
- **Do NOT touch**: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, `.superpowers/`.
- **On-device gate**: tests pass on Samsung `RZCY51D0T1K`.
- Paths relative to `apps/mobile/` unless noted (`scripts/`, `docs/` are repo-root).

---

### Task 1: Image-export actions share via the channel

**Files:**
- Modify: `lib/features/library/page_viewer_screen.dart` (`_exportPageAsImage`, `_exportAllImages`, two menu labels)
- Test (rewrite): `test/features/library/page_viewer_i1_test.dart`
- Test (rewrite): `test/features/library/page_viewer_export_all_test.dart`
- Test (rewrite): `test/features/library/page_viewer_q1_test.dart`

**Interfaces:**
- Consumes: `PageViewerScreen`'s existing `final ShareChannel share` param (added in R1, default `const SystemShareChannel()`); `FakeShareChannel` (fields `lastFilePaths`, `lastSubject`, `int calls`; ctor `FakeShareChannel({bool throwOnShare = false})`); `FakeDocumentRepository` (`throwOnExportImage`, `lastExportedImagePosition`, `lastImageExportQuality`).
- Produces: no new public API — behavior change only.

- [ ] **Step 1: Rewrite the three affected host tests to expect share behavior**

Replace `test/features/library/page_viewer_i1_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Future<void> pushViewer(WidgetTester tester, FakeDocumentRepository repo,
      FakeShareChannel share) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const Key('open'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PageViewerScreen(
                    documentId: 1, name: 'Doc', repository: repo, share: share),
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

  testWidgets('overflow menu exposes Share as image', (tester) async {
    await pushViewer(tester, twoPageRepo(), FakeShareChannel());
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-viewer-export-image')), findsOneWidget);
  });

  testWidgets('sharing the current page exports it then shares the JPG',
      (tester) async {
    final repo = twoPageRepo();
    final share = FakeShareChannel();
    await pushViewer(tester, repo, share);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pumpAndSettle();
    expect(repo.lastExportedImagePosition, 1);
    expect(share.calls, 1);
    expect(share.lastFilePaths!.single, endsWith('.jpg'));
    expect(share.lastSubject, 'Doc');
  });

  testWidgets('export failure shows a share error and does not share',
      (tester) async {
    final repo = twoPageRepo(throwOnExportImage: true);
    final share = FakeShareChannel();
    await pushViewer(tester, repo, share);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pumpAndSettle();
    expect(share.calls, 0);
    expect(find.text("Couldn't share image"), findsOneWidget);
  });
}
```

Replace `test/features/library/page_viewer_export_all_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('Share all as images shares one JPG per page', (tester) async {
    final repo = FakeDocumentRepository(pages: const [
      PageImage(position: 1, imagePath: '/a.jpg'),
      PageImage(position: 2, imagePath: '/b.jpg'),
    ]);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(
          documentId: 1, name: 'Doc', repository: repo, share: share),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 1);
    expect(share.lastFilePaths!.length, 2);
    expect(share.lastFilePaths!.every((p) => p.endsWith('.jpg')), isTrue);
    expect(share.lastSubject, 'Doc');
  });

  testWidgets('a failing export shows a share error', (tester) async {
    final repo = FakeDocumentRepository(
      throwOnExportImage: true,
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(
          documentId: 1, name: 'Doc', repository: repo, share: share),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 0);
    expect(find.text("Couldn't share images"), findsOneWidget);
  });
}
```

In `test/features/library/page_viewer_q1_test.dart`, change `_pumpViewer` to accept a share channel, and rewrite the two image tests (leave the PDF export test unchanged). New `_pumpViewer`:

```dart
Future<void> _pumpViewer(WidgetTester tester, FakeDocumentRepository repo,
    FakeShareChannel share) async {
  await tester.pumpWidget(MaterialApp(
    home: PageViewerScreen(
      repository: repo,
      documentId: 4,
      name: 'Doc',
      share: share,
    ),
  ));
  await tester.pumpAndSettle();
}
```

Replace the first two `testWidgets` with:

```dart
  testWidgets('image share: choosing Medium passes quality + shares',
      (tester) async {
    final repo = FakeDocumentRepository();
    final share = FakeShareChannel();
    await _pumpViewer(tester, repo, share);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-medium')));
    await tester.pumpAndSettle();
    expect(repo.lastImageExportQuality, ExportQuality.medium);
    expect(share.calls, 1);
  });

  testWidgets('image share: cancelling the dialog is a no-op', (tester) async {
    final repo = FakeDocumentRepository();
    final share = FakeShareChannel();
    await _pumpViewer(tester, repo, share);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-cancel')));
    await tester.pumpAndSettle();
    expect(repo.lastImageExportQuality, isNull);
    expect(share.calls, 0);
  });
```

The third test (`PDF export: choosing Low …`) also calls `_pumpViewer`; update its call to pass a fresh `FakeShareChannel()` as the third arg (the PDF path does not share, so `share.calls` is irrelevant there):
```dart
    await _pumpViewer(tester, repo, FakeShareChannel());
```

- [ ] **Step 2: Run the rewritten tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_i1_test.dart test/features/library/page_viewer_export_all_test.dart test/features/library/page_viewer_q1_test.dart`
Expected: FAIL — production still shows "Page saved as image"/"Exported N images" and never calls the channel, so the new `share.calls`/`endsWith('.jpg')`/"Couldn't share image(s)" assertions fail.

- [ ] **Step 3: Change `_exportPageAsImage` to share**

In `lib/features/library/page_viewer_screen.dart`, replace the body of `_exportPageAsImage` (currently lines ~213-235) with:

```dart
  Future<void> _exportPageAsImage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final file = await widget.repository
          .exportPageAsImage(widget.documentId, page.position, quality: quality);
      await widget.share.share([file.path], subject: _name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't share image")),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
```

- [ ] **Step 4: Change `_exportAllImages` to share**

Replace the body of `_exportAllImages` (currently lines ~237-255) with:

```dart
  Future<void> _exportAllImages() async {
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final files = await widget.repository
          .exportAllPagesAsImages(widget.documentId, quality: quality);
      await widget.share.share(
          files.map((f) => f.path).toList(), subject: _name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't share images")),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
```

- [ ] **Step 5: Update the two menu labels**

In the `PopupMenuButton`'s `itemBuilder`, change the two labels (keys/values unchanged):

- `page-viewer-export-image` item child: `Text('Export as image')` → `Text('Share as image')`
- `page-viewer-export-all-images` item child: `Text('Export all as images')` → `Text('Share all as images')`

- [ ] **Step 6: Run the rewritten tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_i1_test.dart test/features/library/page_viewer_export_all_test.dart test/features/library/page_viewer_q1_test.dart`
Expected: PASS.

- [ ] **Step 7: Library group + analyze**

Set the DARTCV env if a test errors on `libdartcv`: `bash /Users/pablohpsilva/Documents/camscanner-light/scripts/setup-cv-host-test.sh` then export `DARTCV_LIB_PATH=/tmp/dartcv_lib/lib/libdartcv.dylib` + `DYLD_LIBRARY_PATH=/tmp/dartcv_lib/lib`.

Run: `cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/test/features/library/page_viewer_i1_test.dart apps/mobile/test/features/library/page_viewer_export_all_test.dart apps/mobile/test/features/library/page_viewer_q1_test.dart
git commit -m "feat(r2): share page/all images via ShareChannel instead of app-private save"
```

---

### Task 2: Library-list Share re-entrancy guard

**Files:**
- Modify: `lib/features/library/home_screen.dart` (`_sharing` flag in `_shareDocument`)
- Test: `test/features/library/home_share_test.dart` (add a re-entrancy case)

**Interfaces:**
- Consumes: `FakeDocumentRepository`'s existing `exportGate` (`Completer<void>?`) and `exportedIds`; `FakeShareChannel.calls`; the existing `homeWith`/`doc` helpers in `home_share_test.dart`.

- [ ] **Step 1: Write the failing re-entrancy test**

In `test/features/library/home_share_test.dart`, add `import 'dart:async';` at the top if not present, and add this test inside `main()`:

```dart
  testWidgets('double-tapping Share does not launch two exports',
      (tester) async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(documents: [doc], exportGate: gate);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    // First Share — blocks inside exportPdf on the gate.
    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-share-1')));
    await tester.pump();

    // Second Share while the first is still in-flight.
    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-share-1')));
    await tester.pump();

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.exportedIds.length, 1);
    expect(share.calls, 1);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/home_share_test.dart`
Expected: FAIL — without a guard the second tap calls `exportPdf` again; after the gate completes `exportedIds.length == 2` and `share.calls == 2`.

- [ ] **Step 3: Add the `_sharing` guard**

In `lib/features/library/home_screen.dart`, add the field to `_HomeScreenState` (near `_searching`):

```dart
  bool _sharing = false;
```

Replace `_shareDocument` with:

```dart
  Future<void> _shareDocument(DocumentSummary s) async {
    final repo = _repository;
    if (repo == null || _sharing) return;
    _sharing = true;
    try {
      final file = await repo.exportPdf(s.document.id);
      await widget.libraryDependencies.share
          .share([file.path], subject: s.document.name);
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

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/home_share_test.dart`
Expected: PASS (the two R1 cases + the new re-entrancy case = 3).

- [ ] **Step 5: Analyze**

Run: `cd apps/mobile && flutter analyze --no-fatal-infos`
Expected: `No issues found`.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/home_screen.dart apps/mobile/test/features/library/home_share_test.dart
git commit -m "fix(r2): re-entrancy guard on library-list Share (no overlapping exports)"
```

---

### Task 3: BDD steps, on-device test, verify script, index, close Feature 12

**Files:**
- Modify: `test/step/i_see_the_image_export_confirmation.dart` (assert the channel, not the snackbar)
- Modify: `test/step/i_see_the_all_images_export_confirmation.dart` (assert the channel)
- Create: `integration_test/r2_share_image_device_test.dart`
- Create: `scripts/verify/r2.sh` (repo root)
- Modify: `docs/superpowers/plans/00-plans-index.md`

**Interfaces:**
- Consumes: top-level `lastBddShareChannel` (`FakeShareChannel?`, set by `tempLibraryDependencies()` in R1); the rewritten export→share behavior (Task 1); the i1/j1 generated tests (`integration_test/i1_export_image_test.dart`, `integration_test/j1_export_all_images_test.dart`).

- [ ] **Step 1: Rewrite the single-image BDD confirmation step**

Replace `test/step/i_see_the_image_export_confirmation.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_library.dart';

/// Usage: I see the image export confirmation
///
/// After R2 the page-image export shares the JPG through the ShareChannel
/// instead of showing a "saved" snackbar; the on-device BDD injects a recording
/// FakeShareChannel (via tempLibraryDependencies), so we assert what it received.
Future<void> iSeeTheImageExportConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  final share = lastBddShareChannel;
  expect(share, isNotNull);
  expect(share!.calls, greaterThan(0));
  expect(share.lastFilePaths, isNotNull);
  expect(share.lastFilePaths!.every((p) => p.endsWith('.jpg')), isTrue);
}
```

- [ ] **Step 2: Rewrite the all-images BDD confirmation step**

Replace `test/step/i_see_the_all_images_export_confirmation.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_library.dart';

/// Usage: I see the all images export confirmation
///
/// After R2 "export all" shares one JPG per page through the ShareChannel; the
/// on-device BDD injects a recording FakeShareChannel, so we assert every shared
/// path is a JPG.
Future<void> iSeeTheAllImagesExportConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  final share = lastBddShareChannel;
  expect(share, isNotNull);
  expect(share!.calls, greaterThan(0));
  expect(share.lastFilePaths, isNotNull);
  expect(share.lastFilePaths!.isNotEmpty, isTrue);
  expect(share.lastFilePaths!.every((p) => p.endsWith('.jpg')), isTrue);
}
```

> No build_runner run: these are body-only changes to existing step functions; the generated i1/j1/q1 `*_test.dart` call them by name and pick up the new bodies automatically.

- [ ] **Step 3: Write the on-device deterministic test**

Create `integration_test/r2_share_image_device_test.dart`:

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exportPageAsImage output shared through the channel is a JPEG',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('r2dev');
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

    final file = await repo.exportPageAsImage(id, 1);

    final ShareChannel share = FakeShareChannel();
    await share.share([file.path], subject: 'Doc');
    final fake = share as FakeShareChannel;

    expect(fake.lastFilePaths!.single, file.path);
    final bytes = await file.readAsBytes();
    expect(bytes[0], 0xFF); // JPEG SOI
    expect(bytes[1], 0xD8);

    await db.close();
    await base.delete(recursive: true);
  });
}
```

> If `PagesCompanion.insert`'s image-path field is not named `relativeImagePath`, match `integration_test/r1_share_document_device_test.dart`'s seeding (it inserts the same row) — copy its exact field names.

- [ ] **Step 4: Write the verify script**

Create `scripts/verify/r2.sh` (repo root), mirroring `scripts/verify/r1.sh`:

```bash
#!/usr/bin/env bash
# Verify R2 (share images + close Feature 12) acceptance criteria.
# Run from repository root: bash scripts/verify/r2.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== R2 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "page viewer shares a single image via the channel" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "Couldn't share image"

assert_file_has "page viewer shares all images via the channel" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "Couldn't share images"

assert_file_has "library share has a re-entrancy guard" \
  "apps/mobile/lib/features/library/home_screen.dart" \
  "_sharing"

assert_file_has "image-export BDD step asserts the share channel" \
  "apps/mobile/test/step/i_see_the_image_export_confirmation.dart" \
  "lastBddShareChannel"

# share_plus stays isolated to the seam (exactly one importer).
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
  warn "VERIFY_SKIP_DEVICE=1 — on-device R2 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device image-share deterministic test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/r2_share_image_device_test.dart"
  assert_cmd "on-device single-image share BDD passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/i1_export_image_test.dart"
  assert_cmd "on-device all-images share BDD passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/j1_export_all_images_test.dart"
fi

echo "== R2 verification complete =="
```

Make it executable: `chmod +x scripts/verify/r2.sh`.

> Before running, confirm the generated BDD filenames: `ls apps/mobile/integration_test/i1_export_image_test.dart apps/mobile/integration_test/j1_export_all_images_test.dart`. If they differ, use the actual generated names in the two `assert_cmd` lines.

- [ ] **Step 5: Host verify + analyze**

Run: `cd apps/mobile && flutter test && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 6: Update the plans index + note Feature 12 closure**

In `docs/superpowers/plans/00-plans-index.md`, add after the R1 row:

```markdown
| R2 | Share images (JPG) + close Feature 12 | 12 | `2026-07-02-r2-share-images.md` | ✅ **built & gated** |
```

Then add one line directly under the plan-files table (not inside it):

```markdown
> **Feature 12 (sharing) is complete on-device:** PDF share (R1) + JPG share (R2)
> via the system share sheet. Link-share and fax remain deferred behind the
> `ShareChannel`/`FaxProvider` interface.
```

Do NOT change the design-status table in `00-overview-roadmap.md` (that column tracks design approval, not build status).

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/test/step/i_see_the_image_export_confirmation.dart apps/mobile/test/step/i_see_the_all_images_export_confirmation.dart apps/mobile/integration_test/r2_share_image_device_test.dart scripts/verify/r2.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(r2): BDD steps assert share, on-device image-share test, verify script, index"
```

---

## Self-Review

- **Spec coverage:**
  - Route `_exportPageAsImage`/`_exportAllImages` through `ShareChannel` (single + N-file) → Task 1. ✅
  - Labels → "Share…"; no success snackbar; failure "Couldn't share image(s)"; keep quality dialog + `_exporting` → Task 1. ✅
  - `_shareDocument` re-entrancy guard → Task 2. ✅
  - Rewrite affected host tests (i1/export-all/q1) → Task 1. ✅
  - Rewrite the shared BDD step(s) (single + all) to assert the channel → Task 3. ✅
  - On-device deterministic image-share test + verify script + index + Feature 12 closure → Task 3. ✅
  - Trust-upstream scrub (no re-scrub) → Task 1 shares the export output directly. ✅
  - `ShareChannel` unchanged; `share_plus` stays isolated (verify-script guard) → Task 3. ✅
  - No build_runner / no new feature (reuse i1/j1 as on-device share proof) → Global Constraints + Task 3. ✅
- **Placeholder scan:** complete code in every step; the two "confirm the field/filename" notes give exact fallbacks (copy from the R1 device test / `ls` the generated names). ✅
- **Type consistency:** `FakeShareChannel` fields (`calls`, `lastFilePaths`, `lastSubject`) and `share(List<String>, {String? subject})` match R1 and are used identically across Tasks 1–3; `PageViewerScreen`'s `share` param (from R1) is the injection point; menu keys `page-viewer-export-image`/`page-viewer-export-all-images` unchanged throughout. ✅
- **Out of scope kept out:** no save-to-gallery, no link-share/fax, no `ShareChannel` signature change, no new `.feature`, no build_runner. ✅
