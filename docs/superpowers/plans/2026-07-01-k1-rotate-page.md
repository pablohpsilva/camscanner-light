# K1 — Rotate a page 90° Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Rotate a page 90° clockwise per tap in the page viewer, baking the rotation into the display derivative and rotating the cached OCR boxes to match.

**Architecture:** `rotatePage` rotates the flat/display JPEG via `image.copyRotate(angle: 90)` (90° CW) and rotates each cached `OcrWordBox` by the matching normalized transform `(l,t,r,b) → (1−b, l, 1−t, r)`. Downstream consumers read the flat file + boxes unchanged. The viewer clears the image cache (FileImage caches by path) then reloads.

**Tech Stack:** Flutter/Dart, drift, `image` (pure-Dart raster), `bdd_widget_test` + `build_runner`.

## Global Constraints

- **iOS + Android**: pure-Dart raster + Material menu; no platform channels.
- **On-device only**: rotation stays in the app's document folder.
- **CW consistency**: `image.copyRotate(src, angle: 90)` is 90° CLOCKWISE (verified in source); the box transform MUST use the matching CW formula so image and boxes stay aligned.
- **No new DB column, no re-OCR, no consumer changes** beyond the viewer menu.
- **Image-cache eviction is required** in the viewer after rotate (FileImage caches by path).
- **TDD/BDD first**; SOLID/KISS.
- **Commits**: explicit file paths (never `git add -A`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Do NOT touch**: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, `.superpowers/`. Do NOT commit report files.
- **On-device gate**: BDD + integration tests pass on Samsung `RZCY51D0T1K`.
- Paths relative to `apps/mobile/` unless noted (`scripts/`, `docs/` are repo-root).

---

### Task 1: `OcrWordBox.rotate90Cw()`

**Files:**
- Modify: `lib/features/library/ocr/ocr_result.dart`
- Test: `test/features/library/ocr/ocr_word_box_rotate_test.dart` (create)

**Interfaces:**
- Produces: `OcrWordBox OcrWordBox.rotate90Cw()`.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/ocr/ocr_word_box_rotate_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';

void main() {
  test('rotate90Cw moves a top-left box to the top-right', () {
    const b = OcrWordBox(text: 'x', left: 0, top: 0, right: 0.2, bottom: 0.1);
    final r = b.rotate90Cw();
    expect(r.left, closeTo(0.9, 1e-9));
    expect(r.top, closeTo(0.0, 1e-9));
    expect(r.right, closeTo(1.0, 1e-9));
    expect(r.bottom, closeTo(0.2, 1e-9));
    expect(r.text, 'x');
  });

  test('four rotations return the original box', () {
    const b = OcrWordBox(text: 'x', left: 0.1, top: 0.2, right: 0.5, bottom: 0.7);
    var r = b;
    for (var i = 0; i < 4; i++) {
      r = r.rotate90Cw();
    }
    expect(r.left, closeTo(0.1, 1e-9));
    expect(r.top, closeTo(0.2, 1e-9));
    expect(r.right, closeTo(0.5, 1e-9));
    expect(r.bottom, closeTo(0.7, 1e-9));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/ocr/ocr_word_box_rotate_test.dart`
Expected: FAIL — `rotate90Cw` not defined.

- [ ] **Step 3: Implement**

In `lib/features/library/ocr/ocr_result.dart`, add to `OcrWordBox` (after the constructor):

```dart
  /// This box after the page image is rotated 90° CLOCKWISE (normalized coords).
  /// Matches `image.copyRotate(angle: 90)`: a top-left box moves to the top-right.
  OcrWordBox rotate90Cw() => OcrWordBox(
        text: text,
        left: 1 - bottom,
        top: left,
        right: 1 - top,
        bottom: right,
      );
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/ocr/ocr_word_box_rotate_test.dart`
Expected: PASS (2/2).

- [ ] **Step 5: Analyze + commit**

Run: `cd apps/mobile && flutter analyze --no-fatal-infos` → `No issues found`.

```bash
git add apps/mobile/lib/features/library/ocr/ocr_result.dart apps/mobile/test/features/library/ocr/ocr_word_box_rotate_test.dart
git commit -m "feat(k1): OcrWordBox.rotate90Cw — CW box transform for rotation"
```

---

### Task 2: `rotatePage` repository method

**Files:**
- Modify: `lib/features/library/document_repository.dart` (interface)
- Modify: `lib/features/library/drift/drift_document_repository.dart` (impl + imports)
- Modify: `test/support/fake_library.dart` (fake)
- Test: `test/features/library/rotate_page_test.dart` (create)

**Interfaces:**
- Consumes: `_fileStore` (`flatForImage`, `writeRelative`, `absoluteFor`), `OcrResult`/`OcrWordBox.rotate90Cw` (Task 1), `image` package, `_clock`.
- Produces: `Future<void> rotatePage(int documentId, int position)`.

- [ ] **Step 1: Write the failing test**

Create `test/features/library/rotate_page_test.dart`:

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
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('k1rot');
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

  test('rotates the display image (dims swap) and the cached boxes', () async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: 'Doc', createdAt: now, modifiedAt: now));
    // 40x20 (non-square) JPEG so a dims-swap is observable.
    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 40, height: 20), quality: 95));
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, jpeg);
    const box = OcrWordBox(text: 'hi', left: 0.0, top: 0.0, right: 0.2, bottom: 0.1);
    await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id,
          position: 1,
          relativeImagePath: rel,
          ocrText: const Value('hi'),
          ocrBoxes: Value(const OcrResult(text: 'hi', words: [box]).encodeBoxes()),
        ));

    await repo.rotatePage(id, 1);

    final pages = await repo.getDocumentPages(id);
    final page = pages.single;
    // Flat now exists and is the rotated (dims-swapped) image.
    expect(page.flatImagePath, isNotNull);
    final decoded = img.decodeImage(File(page.flatImagePath!).readAsBytesSync())!;
    expect(decoded.width, 20);
    expect(decoded.height, 40);
    // Box rotated CW: (0,0,0.2,0.1) -> (0.9, 0, 1.0, 0.2).
    final r = page.ocrWords.single;
    expect(r.left, closeTo(0.9, 1e-6));
    expect(r.top, closeTo(0.0, 1e-6));
    expect(r.right, closeTo(1.0, 1e-6));
    expect(r.bottom, closeTo(0.2, 1e-6));
    expect(page.ocrText, 'hi'); // text unchanged
  });

  test('throws when the page row is missing', () async {
    expect(() => repo.rotatePage(999, 1), throwsA(isA<DocumentSaveException>()));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/rotate_page_test.dart`
Expected: FAIL — `rotatePage` not defined.

- [ ] **Step 3: Add the interface method**

In `lib/features/library/document_repository.dart`, after `runOcr` (or near `updatePageCorners`):

```dart
  /// Rotates the page at [position] of [documentId] 90° CLOCKWISE: rotates the
  /// display derivative (flat) image and the cached OCR word boxes to match, and
  /// bumps the document's modifiedAt. Idempotent per call (each rotates one more
  /// quarter-turn). Nothing leaves the device. Throws [DocumentSaveException]
  /// when the page row is missing or its image cannot be decoded.
  Future<void> rotatePage(int documentId, int position);
```

- [ ] **Step 4: Implement in the Drift repository**

Ensure these imports exist at the top of `drift_document_repository.dart` (add any missing):

```dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;
```
(`OcrResult` is already imported — `getDocumentPages` uses `OcrResult.decodeBoxes`.)

Add the method (near `updatePageCorners`):

```dart
  @override
  Future<void> rotatePage(int documentId, int position) async {
    final row = await (_db.select(_db.pages)
          ..where((t) =>
              t.documentId.equals(documentId) & t.position.equals(position)))
        .getSingleOrNull();
    if (row == null) {
      throw DocumentSaveException('rotatePage: no page ($documentId, $position)');
    }
    // Rotate the DISPLAY image (flat if present, else original) 90° CW.
    final displayRel = row.flatRelativePath ?? row.relativeImagePath;
    final bytes = await _fileStore.absoluteFor(displayRel).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const DocumentSaveException('rotatePage: undecodable image');
    }
    final rotated = img.copyRotate(decoded, angle: 90); // 90° clockwise
    final out = Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
    // Bake into the flat derivative (create it if this page had none).
    final flatRel =
        row.flatRelativePath ?? _fileStore.flatForImage(row.relativeImagePath);
    await _fileStore.writeRelative(flatRel, out);

    // Rotate the cached OCR boxes CW to stay aligned; text is unchanged.
    final boxes = OcrResult.decodeBoxes(row.ocrBoxes);
    final String? newBoxes = boxes.isEmpty
        ? row.ocrBoxes
        : OcrResult(text: '', words: [for (final b in boxes) b.rotate90Cw()])
            .encodeBoxes();

    await (_db.update(_db.pages)
          ..where((t) =>
              t.documentId.equals(documentId) & t.position.equals(position)))
        .write(PagesCompanion(
            flatRelativePath: Value(flatRel), ocrBoxes: Value(newBoxes)));
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
        .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
  }
```

- [ ] **Step 5: Implement in the fake repository**

In `test/support/fake_library.dart`, add fields + method to `FakeDocumentRepository`:

```dart
  int rotateCalls = 0;
  int? lastRotatedPosition;

  @override
  Future<void> rotatePage(int documentId, int position) async {
    if (throwOnUpdate) {
      throw const DocumentSaveException('fake: rotate failed');
    }
    rotateCalls++;
    lastRotatedPosition = position;
  }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/rotate_page_test.dart`
Expected: PASS (2/2). (Pure-Dart `image` raster — no OpenCV needed for this file.)

- [ ] **Step 7: Library group + analyze**

Run (set the DARTCV env if a test errors on `libdartcv`: `bash /Users/pablohpsilva/Documents/camscanner-light/scripts/setup-cv-host-test.sh` then export `DARTCV_LIB_PATH=/tmp/dartcv_lib/lib/libdartcv.dylib` + `DYLD_LIBRARY_PATH=/tmp/dartcv_lib/lib`):
`cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/document_repository.dart apps/mobile/lib/features/library/drift/drift_document_repository.dart apps/mobile/test/support/fake_library.dart apps/mobile/test/features/library/rotate_page_test.dart
git commit -m "feat(k1): rotatePage — bake 90° CW rotation into flat + rotate boxes"
```

---

### Task 3: Page-viewer "Rotate" action

**Files:**
- Modify: `lib/features/library/page_viewer_screen.dart`
- Test: `test/features/library/page_viewer_rotate_test.dart` (create)

**Interfaces:**
- Consumes: `DocumentRepository.rotatePage`, the existing `page-viewer-page-menu` popup, `PaintingBinding.imageCache`.
- Produces: `page-viewer-rotate` menu item + `_rotatePage()`.

- [ ] **Step 1: Write the failing widget test**

Create `test/features/library/page_viewer_rotate_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('Rotate invokes rotatePage for the current page', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-rotate')));
    await tester.pumpAndSettle();

    expect(repo.rotateCalls, 1);
    expect(repo.lastRotatedPosition, 1);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_rotate_test.dart`
Expected: FAIL — no `page-viewer-rotate` item.

- [ ] **Step 3: Add the handler**

In `lib/features/library/page_viewer_screen.dart`, ensure `package:flutter/rendering.dart` isn't needed — `PaintingBinding` comes from `package:flutter/widgets.dart` (already transitively imported via material). Add a method near `_editCrop`:

```dart
  Future<void> _rotatePage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    try {
      await widget.repository.rotatePage(widget.documentId, page.position);
      // FileImage caches by path; the rotated bytes reuse the flat path, so
      // clear the cache before reloading or the stale image would show.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't rotate")),
      );
    }
  }
```

- [ ] **Step 4: Add the menu item**

In the `PopupMenuButton`'s `onSelected`, add:

```dart
              if (v == 'rotate') unawaited(_rotatePage());
```

In `itemBuilder`'s list, add after the `view-text` item (rotate is a common edit, keep it high):

```dart
              PopupMenuItem<String>(
                value: 'rotate',
                key: Key('page-viewer-rotate'),
                child: Text('Rotate'),
              ),
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_rotate_test.dart`
Expected: PASS.

- [ ] **Step 6: Library group + analyze**

Run (with the DARTCV env if needed): `cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/test/features/library/page_viewer_rotate_test.dart
git commit -m "feat(k1): page viewer 'Rotate' action with image-cache eviction"
```

---

### Task 4: BDD, on-device test, verify script, plans index

**Files:**
- Create: `integration_test/k1_rotate_page.feature`
- Create step def: `test/step/i_rotate_the_page.dart`
- Generate: `integration_test/k1_rotate_page_test.dart` (build_runner; committed)
- Create: `integration_test/k1_rotate_page_device_test.dart` (deterministic rotate on device)
- Create: `scripts/verify/k1.sh` (repo root)
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Write the `.feature`** (reuses I1's scan flow → a real image)

Create `integration_test/k1_rotate_page.feature`:

```gherkin
Feature: Rotate a page

  Scenario: Rotate the open page
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I rotate the page
    Then I see the page viewer
```

- [ ] **Step 2: Write the new step definition**

Create `test/step/i_rotate_the_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I rotate the page
Future<void> iRotateThePage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-rotate')));
  await tester.pumpAndSettle();
}
```

> `the app is launched…`, `I tap the Scan button`, `I capture and accept the first page`, `I tap Done`, `I open the first document`, and `I see the page viewer` already exist — reuse. Verify the generated function name for the new step matches the generator's derivation; rename to match if needed.

- [ ] **Step 3: Generate the BDD test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `integration_test/k1_rotate_page_test.dart` generated, importing `iRotateThePage` + the reused steps. If build_runner rewrote unrelated generated files, `git checkout` them so the commit stays scoped to K1.

- [ ] **Step 4: Write the deterministic on-device test**

Create `integration_test/k1_rotate_page_device_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rotatePage swaps image dims and rotates boxes on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('k1dev');
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
        img.encodeJpg(img.Image(width: 40, height: 20), quality: 95));
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, jpeg);
    const box = OcrWordBox(text: 'hi', left: 0.0, top: 0.0, right: 0.2, bottom: 0.1);
    await db.into(db.pages).insert(PagesCompanion.insert(
          documentId: id,
          position: 1,
          relativeImagePath: rel,
          ocrBoxes: Value(const OcrResult(text: 'hi', words: [box]).encodeBoxes()),
        ));

    await repo.rotatePage(id, 1);

    final page = (await repo.getDocumentPages(id)).single;
    final decoded = img.decodeImage(File(page.flatImagePath!).readAsBytesSync())!;
    expect(decoded.width, 20);
    expect(decoded.height, 40);
    expect(page.ocrWords.single.left, closeTo(0.9, 1e-6));

    await db.close();
    await base.delete(recursive: true);
  });
}
```

- [ ] **Step 5: Write the verify script**

Create `scripts/verify/k1.sh` (repo root), mirroring `scripts/verify/o1.sh`:

```bash
#!/usr/bin/env bash
# Verify K1 (rotate a page 90°) acceptance criteria.
# Run from repository root: bash scripts/verify/k1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== K1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "rotate90Cw on OcrWordBox" \
  "apps/mobile/lib/features/library/ocr/ocr_result.dart" \
  "rotate90Cw"

assert_file_has "rotatePage on the interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "rotatePage"

assert_file_has "rotatePage in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "copyRotate"

assert_file_has "page viewer wires Rotate" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-rotate"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/k1_rotate_page.feature" \
  "Rotate a page"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/k1_rotate_page_test.dart" \
  "rotate"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device K1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device rotate test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/k1_rotate_page_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/k1_rotate_page_test.dart"
fi

echo "== K1 verification complete =="
```

Make it executable: `chmod +x scripts/verify/k1.sh`.

- [ ] **Step 6: Host verify + analyze**

Run: `cd apps/mobile && flutter test && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 7: Update the plans index**

In `docs/superpowers/plans/00-plans-index.md`, add after the J1 row:

```markdown
| K1 | Rotate a page 90° | 09 | `2026-07-01-k1-rotate-page.md` | ✅ **built & gated** |
```

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/integration_test/k1_rotate_page.feature apps/mobile/integration_test/k1_rotate_page_test.dart apps/mobile/integration_test/k1_rotate_page_device_test.dart apps/mobile/test/step/i_rotate_the_page.dart scripts/verify/k1.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(k1): BDD + on-device rotate tests, verify script, index"
```

---

## Self-Review

- **Spec coverage:** box transform (Task 1), rotatePage bake+box-rotate (Task 2), viewer action + cache eviction (Task 3), BDD + device + verify + index (Task 4). ✅
- **CW consistency:** image `copyRotate(angle: 90)` (CW, source-verified) + box `(l,t,r,b)→(1−b,l,1−t,r)` (CW). The device test asserts both dims-swap AND box position. ✅
- **Cache eviction:** `_rotatePage` clears the image cache before reload (FileImage path-caching). ✅
- **Placeholder scan:** complete code in every step. ✅
- **Type consistency:** `rotatePage(int,int) → Future<void>` identical across interface/Drift/fake; `rotate90Cw()` used identically in Task 2 impl + tests. ✅
- **Out of scope kept out:** no rotation metadata column, no re-OCR, no per-consumer rotation, no arbitrary angles. Documented limitation: rotate-then-recrop discards rotation. ✅
