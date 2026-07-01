# H5 Multi-page PDF Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove and gate that a multi-page document exports to a single PDF with one page per document page, in order, each at its original aspect, with no personal metadata.

**Architecture:** Multi-page generation already exists (`PdfBuilder.build` loops all pages; `exportPdf` → `getDocumentPages` orders by `position ASC`). This plan adds the missing **test coverage** — no production code change is expected. If a test reveals an actual generation/order defect, fixing it becomes in-scope.

**Tech Stack:** `pdf` package (PDF writing), `package:image` ^4.5.0 (generate distinct test JPEGs), `pdfx` 2.9.2 (`PdfDocument.openFile` / `pagesCount`), `bdd_widget_test` + `build_runner`.

## Global Constraints

- **No production code change is expected.** These are test/verification deliverables. Do not modify `pdf_builder.dart`, `drift_document_repository.dart`, `pdf_preview_screen.dart`, or the export UI unless a test proves a real defect — if so, STOP and report before changing production code.
- Material only; identical iOS/Android (no platform branching). `pdfx` works on both.
- Host test success marker is exactly `All tests passed!`; `flutter analyze --no-fatal-infos` (from `apps/mobile`) must print `No issues found` (repo is currently clean — keep it clean, no unused imports).
- BDD scenarios are authored as `.feature` files under `apps/mobile/integration_test/`, generated to `*_test.dart` via `dart run build_runner build` (run from `apps/mobile`; there is NO `mobile:build_runner` nx target). Generated files are committed. Step defs live in `apps/mobile/test/step/`.
- `/Type /Page` and `/Width`/`/Height` (image XObject) tokens are greppable even in compressed PDF output — page-dictionary and XObject-dictionary objects are not inside the deflated streams (proven by the existing "builds a valid single-page PDF" test which greps `/Type /Page` on default-compressed output).
- Commit with EXPLICIT file paths (never `git add -A`). End every commit message with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- DO NOT stage or touch the pre-existing uncommitted files: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`. Do NOT touch `.superpowers/`.
- Tooling: `pnpm nx run mobile:test --skip-nx-cache -- --name "a|b"` breaks (shell parses `|`). Run focused tests with `flutter test <file>` directly; use plain `pnpm nx run mobile:test --skip-nx-cache` for the full suite.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `apps/mobile/test/features/library/pdf/pdf_builder_test.dart` | Builder-level PDF assertions | Add multi-page count + order + aspect test |
| `apps/mobile/test/features/library/drift_document_repository_test.dart` | Repo-level export assertions | Add multi-page `exportPdf` count test |
| `apps/mobile/integration_test/h5_multipage_pdf.feature` (+ generated `_test.dart`) | On-device 3-page export | New |
| `apps/mobile/test/step/i_capture_and_accept_the_third_page.dart` | BDD step | New |
| `apps/mobile/test/step/the_exported_pdf_has3_pages.dart` | BDD step (pdfx page count) | New |
| `scripts/verify/h5.sh` | Acceptance gate | New |
| `docs/superpowers/plans/00-plans-index.md` | Roadmap status | H5 → built & gated |

---

### Task 1: Multi-page unit coverage (builder count/order/aspect + exportPdf count)

Two pure test additions (no production code). Both prove multi-page behavior — one at the `PdfBuilder` level (count + order + aspect), one at the `exportPdf` repository level (all pages flow through).

**Files:**
- Modify: `apps/mobile/test/features/library/pdf/pdf_builder_test.dart`
- Modify: `apps/mobile/test/features/library/drift_document_repository_test.dart`

**Interfaces:**
- Consumes: `PdfBuilder.build(List<PageImage>, {bool compress})`, `PageImage(position, imagePath)`, `DriftDocumentRepository.exportPdf(int)`, `createFromCapture`, `addPageToDocument`, `package:image` (`img.Image(width,height)`, `img.encodeJpg`).
- Produces: nothing consumed by later tasks (test-only).

- [ ] **Step 1: Write the failing builder multi-page test**

  In `apps/mobile/test/features/library/pdf/pdf_builder_test.dart`, add this import at the top (with the other imports):
  ```dart
  import 'package:image/image.dart' as img;
  ```
  Then add this test inside `main()` (after the existing "builds a valid single-page PDF" test):
  ```dart
  test('multi-page: one PDF page per input page, in order, at each image aspect',
      () async {
    // Three JPEGs with DISTINCT dimensions so each embedded image XObject's
    // /Width + /Height uniquely identify its page and encode order.
    // Return List<int> (writeAsBytesSync accepts it) so this is robust to
    // encodeJpg's return type across image package versions.
    List<int> makeJpeg(int w, int h) =>
        img.encodeJpg(img.Image(width: w, height: h));
    final tmp = Directory.systemTemp.createTempSync('h5builder');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final f1 = File('${tmp.path}/p1.jpg')..writeAsBytesSync(makeJpeg(120, 60));
    final f2 = File('${tmp.path}/p2.jpg')..writeAsBytesSync(makeJpeg(80, 160));
    final f3 = File('${tmp.path}/p3.jpg')..writeAsBytesSync(makeJpeg(200, 100));
    final pages = [
      PageImage(position: 1, imagePath: f1.path),
      PageImage(position: 2, imagePath: f2.path),
      PageImage(position: 3, imagePath: f3.path),
    ];

    final pdf = await const PdfBuilder().build(pages, compress: false);
    final s = dec(pdf);

    // Count: exactly three page objects (/Page not followed by 's' -> not /Pages).
    expect(RegExp(r'/Type\s*/Page(?![s])').allMatches(s).length, 3,
        reason: 'one PDF page per document page');

    // Order + aspect: the three embedded image XObjects (one per page) carry
    // /Width and /Height in page order. Image-only PDF => no other /Width.
    final widths = RegExp(r'/Width\s+(\d+)')
        .allMatches(s)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    final heights = RegExp(r'/Height\s+(\d+)')
        .allMatches(s)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(widths, [120, 80, 200], reason: 'image widths follow page order');
    expect(heights, [60, 160, 100], reason: 'heights follow page order (aspect)');
  });
  ```

- [ ] **Step 2: Run the builder test to verify it PASSES (coverage backfill)**

  ```bash
  cd apps/mobile && flutter test test/features/library/pdf/pdf_builder_test.dart
  ```
  Expected: PASS. This test asserts already-correct behavior (the builder already loops pages in order), so it passes immediately — it is a coverage backfill for the H5 acceptance criterion. If it FAILS (wrong count/order/aspect), STOP: you found a real generation defect — report it before any production change.

  > If `widths`/`heights` don't match, first print `s` around the `/Width` matches to confirm the pdf package's token spacing; the regex `/Width\s+(\d+)` matches `/Width 120`. Do NOT weaken the assertion to make it pass — a mismatch is a real finding.

- [ ] **Step 3: Write the failing exportPdf multi-page test**

  In `apps/mobile/test/features/library/drift_document_repository_test.dart`, add this import at the top if not already present:
  ```dart
  import 'dart:convert'; // latin1
  ```
  Then add this test inside `main()` (near the existing `exportPdf` tests, ~line 279):
  ```dart
  test('exportPdf writes one PDF page per document page (3-page doc)', () async {
    final r = repo();
    final doc = await r.createFromCapture(capture); // page 1
    Uint8List fixture() =>
        File('test/fixtures/exif_sample.jpg').readAsBytesSync();
    CapturedImage cap(String name) => CapturedImage(
        (File('${base.path}/$name.jpg')..writeAsBytesSync(fixture())).path);
    await r.addPageToDocument(doc.id, cap('c2')); // page 2
    await r.addPageToDocument(doc.id, cap('c3')); // page 3

    final file = await r.exportPdf(doc.id);
    final s = latin1.decode(file.readAsBytesSync(), allowInvalid: true);
    expect(RegExp(r'/Type\s*/Page(?![s])').allMatches(s).length, 3,
        reason: 'exportPdf passes ALL pages, not just the first');
  });
  ```

- [ ] **Step 4: Run the exportPdf test to verify it PASSES**

  ```bash
  cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart
  ```
  Expected: PASS (the whole drift suite, including the new test). If the new test FAILS with a page count != 3, STOP and report a real defect.

- [ ] **Step 5: Full suite + analyze**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  ```
  Expected: `All tests passed!` and `No issues found`.

- [ ] **Step 6: Commit**

  ```bash
  git add apps/mobile/test/features/library/pdf/pdf_builder_test.dart \
          apps/mobile/test/features/library/drift_document_repository_test.dart
  git commit -m "test(h5): multi-page PDF coverage — builder count/order/aspect + exportPdf count

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 2: BDD — 3-page export on device

Author the feature, two new step defs, generate the test, run it. The generated `_test.dart` is committed with the authored files.

**Existing steps to REUSE (do NOT recreate):**
`the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart`,
`i_tap_the_scan_button.dart`, `i_capture_and_accept_the_first_page.dart`,
`i_capture_and_accept_the_second_page.dart`, `i_tap_done.dart`,
`i_open_the_first_document.dart`, `i_export_the_open_document_to_pdf.dart`,
`the_pdf_preview_opens.dart`.

**Files:**
- Create: `apps/mobile/integration_test/h5_multipage_pdf.feature`
- Create: `apps/mobile/test/step/i_capture_and_accept_the_third_page.dart`
- Create: `apps/mobile/test/step/the_exported_pdf_has3_pages.dart`
- Create (generated): `apps/mobile/integration_test/h5_multipage_pdf_test.dart`

**Interfaces:**
- Consumes: keys `scan-shutter`, `review-accept`; `PdfPreviewScreen` (public `pdfPath`); pdfx `PdfDocument.openFile` / `pagesCount` / `close`.

- [ ] **Step 1: Write the feature file**

  Create `apps/mobile/integration_test/h5_multipage_pdf.feature`:
  ```gherkin
  Feature: H5 Multi-page PDF export

    Scenario: Exporting a three-page document produces a three-page PDF
      Given the app is launched with camera permission granted and empty storage
      When I tap the Scan button
      And I capture and accept the first page
      And I capture and accept the second page
      And I capture and accept the third page
      And I tap Done
      And I open the first document
      And I export the open document to PDF
      Then the PDF preview opens
      And the exported PDF has 3 pages
  ```

- [ ] **Step 2: Write the third-page step (mirrors first/second)**

  Create `apps/mobile/test/step/i_capture_and_accept_the_third_page.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';

  /// Usage: I capture and accept the third page
  Future<void> iCaptureAndAcceptTheThirdPage(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
  }
  ```

- [ ] **Step 3: Write the page-count step (opens the real PDF via pdfx)**

  Create `apps/mobile/test/step/the_exported_pdf_has3_pages.dart`:
  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:mobile/features/library/pdf_preview_screen.dart';
  import 'package:pdfx/pdfx.dart';

  /// Usage: the exported PDF has 3 pages
  ///
  /// Reads the mounted preview screen's real on-disk PDF path and opens it with
  /// pdfx (the same opener the screen uses) to assert the file itself has three
  /// pages — a genuine on-device page-count check against the written PDF.
  Future<void> theExportedPdfHas3Pages(WidgetTester tester) async {
    final screen =
        tester.widget<PdfPreviewScreen>(find.byType(PdfPreviewScreen));
    final doc = await PdfDocument.openFile(screen.pdfPath);
    expect(doc.pagesCount, 3);
    await doc.close();
  }
  ```

- [ ] **Step 4: Generate the test**

  ```bash
  cd apps/mobile && dart run build_runner build --delete-conflicting-outputs && cd -
  ```
  Expected: creates `apps/mobile/integration_test/h5_multipage_pdf_test.dart`. Confirm its imports resolve:
  ```bash
  grep "import" apps/mobile/integration_test/h5_multipage_pdf_test.dart
  ```
  Expected to include `i_tap_the_scan_button.dart`, `i_capture_and_accept_the_third_page.dart`, and `the_exported_pdf_has3_pages.dart` (plus the other reused steps). If build_runner emits a differently-named file or an import doesn't resolve, STOP and report — do not hand-edit the generated file.

- [ ] **Step 5: Run the host suite (the generated BDD test also runs under the host runner)**

  ```bash
  pnpm nx run mobile:test --skip-nx-cache
  cd apps/mobile && flutter analyze --no-fatal-infos && cd -
  ```
  Expected: `All tests passed!` and `No issues found`.

  > NOTE: the host suite (`flutter test`) runs `test/` only — it does NOT execute
  > `integration_test/` BDD scenarios (verified: adding H4's BDD did not change the
  > host test count). So the host run here does NOT execute this scenario; its job is
  > to confirm the whole tree still passes. What guarantees the new step files and the
  > generated test COMPILE is `flutter analyze` (it analyzes `integration_test/` too) —
  > so a green analyze is the real compile gate here. The scenario itself runs
  > **on-device** in Task 3's verify (and must be run on a real device before the gate).
  > Because it only runs on-device, `the_exported_pdf_has3_pages.dart`'s use of the
  > native pdfx `PdfDocument.openFile` is safe (native plugin present on device).

- [ ] **Step 6: Commit**

  ```bash
  git add apps/mobile/integration_test/h5_multipage_pdf.feature \
          apps/mobile/integration_test/h5_multipage_pdf_test.dart \
          apps/mobile/test/step/i_capture_and_accept_the_third_page.dart \
          apps/mobile/test/step/the_exported_pdf_has3_pages.dart
  git commit -m "test(h5): BDD 3-page export — feature, step defs, generated test

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 3: Verify script + plans index

**Files:**
- Create: `scripts/verify/h5.sh`
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Create `scripts/verify/h5.sh`**

  ```bash
  #!/usr/bin/env bash
  # Verify H5 (Multi-page PDF export) acceptance criteria.
  # Run from repository root: bash scripts/verify/h5.sh
  # VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

  DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib.sh
  source "$DIR/lib.sh"
  cd "$ROOT"

  echo "== H5 verification =="

  require_tool flutter
  require_tool pnpm

  # ---- Static assertions ----
  assert_file_has "builder multi-page test exists" \
    "apps/mobile/test/features/library/pdf/pdf_builder_test.dart" \
    "multi-page: one PDF page per input page"

  assert_file_has "exportPdf multi-page test exists" \
    "apps/mobile/test/features/library/drift_document_repository_test.dart" \
    "exportPdf writes one PDF page per document page"

  assert_file_has "BDD feature file exists" \
    "apps/mobile/integration_test/h5_multipage_pdf.feature" \
    "Multi-page PDF export"

  assert_file_has "generated BDD test exists" \
    "apps/mobile/integration_test/h5_multipage_pdf_test.dart" \
    "theExportedPdfHas3Pages"

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
      pnpm nx run mobile:verify_integration_ios -- --dart-define=INTEGRATION_TEST=h5
  fi

  echo "== H5 verification complete =="
  ```

  Make it executable:
  ```bash
  chmod +x scripts/verify/h5.sh
  ```

- [ ] **Step 2: Run the verify script (device skipped)**

  ```bash
  VERIFY_SKIP_DEVICE=1 bash scripts/verify/h5.sh
  ```
  Expected: ends `== H5 verification complete ==` with all static + host + analyze asserts PASS (device line WARNs, not fails). If any assert FAILS, STOP and report which one.

- [ ] **Step 3: Update the plans index**

  In `docs/superpowers/plans/00-plans-index.md`, change the H5 row status from `⏳` to `✅ **built & gated**` and set its plan-file column to `2026-07-01-h5-multipage-pdf.md`.

- [ ] **Step 4: Commit**

  ```bash
  git add scripts/verify/h5.sh docs/superpowers/plans/00-plans-index.md
  git commit -m "chore(h5): verify script and plans index update

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

## Self-Review (author checklist — completed)

**Spec coverage:**
- Multi-page count → Task 1 (`/Type /Page` == 3, both builder and exportPdf). ✓
- Pages in order → Task 1 (`/Width`+`/Height` sequence == page order). ✓
- Original aspect → Task 1 (each image XObject's /Width,/Height == its image dims). ✓
- 3-page export end-to-end → Task 2 (capture 3 → export → preview opens → pdfx pagesCount == 3). ✓
- No personal metadata (multi-page) → covered by the existing `metadata-clean` unit test (same `pw.Document()`; adding pages doesn't add an info dict). ✓ (no new task needed)
- iOS + Android → all Material + pdfx (cross-platform); no platform branching. ✓

**Placeholder scan:** none — every code step shows complete code; every command has an expected marker.

**Type consistency:** `PdfBuilder.build(pages, compress: false)`, `PdfDocument.openFile(path)`, `.pagesCount`, `.close()`, `PdfPreviewScreen.pdfPath`, step function names (`iCaptureAndAcceptTheThirdPage`, `theExportedPdfHas3Pages`), generated file `h5_multipage_pdf_test.dart` — all consistent across tasks and the verify script's static asserts.

**No-production-change guard:** every task's tests assert already-correct behavior and pass immediately; any failure is flagged as a real defect to report, not silently "fixed". ✓
