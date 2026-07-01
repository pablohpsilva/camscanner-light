# H5 Multi-page PDF Export — Design Spec

**Date:** 2026-07-01
**Status:** Approved
**Step:** H5 — Multi-page PDF export (Feature 07 / PDF export)
**Depends on:** C1/C2 (single-page PDF generate + preview), H1–H4 (multi-page documents), all gated
**Feeds:** I1 (export page as image), later sharing (12)

---

## Goal

A document with multiple pages exports to a **single PDF whose pages are all the
document's pages, in document order, each at its original aspect** — and this is
proven by tests (unit: page count + order; BDD: 3-page export end-to-end on
device). The exported PDF carries **no personal/device metadata**.

---

## Key finding: generation already works — H5 is a **gating** step

The multi-page generation path already exists and is code-verified:

- `PdfBuilder.build(pages)` (`apps/mobile/lib/features/library/pdf/pdf_builder.dart`)
  already **loops over every page** (`for (final page in pages) doc.addPage(...)`),
  embedding each JPEG losslessly at its own `PdfPageFormat(image.width, image.height)`
  (original aspect), EXIF auto-oriented. The default `pw.Document()` writes no info
  dict (metadata-clean).
- `DriftDocumentRepository.exportPdf(documentId)` calls `getDocumentPages(documentId)`
  → `_pdfBuilder.build(pages)`. `getDocumentPages` orders rows by **`position ASC`**,
  so the builder receives pages in document order (stable after H3 reorder / H4
  delete, which keep positions contiguous).
- The export UI (export button → `PdfPreviewScreen`) already exists (C1/C2) and
  operates on the whole document.

So **no production code change is required**. What is missing is *test coverage* of
the multi-page acceptance criteria — today only single-page cases are tested
(`pdf_builder_test.dart` asserts exactly one `/Type /Page`; the drift `exportPdf`
test uses a one-page doc; the c2 BDD captures one page). Per the roadmap Definition
of Done, an acceptance criterion is not "done" until mapped to a passing test. H5
closes that gap.

If, while writing the tests, any of the above claims proves false (e.g. order
wrong, a page dropped), that becomes an in-scope production fix — but the code
review above indicates the path is correct.

---

## Architecture

No new production files; no production edits expected. Three test deliverables +
a verify script:

| Layer | Change |
|---|---|
| `pdf_builder_test.dart` | Add a multi-page test: **count == N** and **pages in input order**, each at its image's aspect |
| `drift_document_repository_test.dart` | Add a multi-page **exportPdf** test: a 3-page document's written PDF has 3 pages (full repo→builder path) |
| BDD `h5_multipage_pdf.feature` (+ generated test) + step defs | On-device **3-page export**: capture 3 pages → export → preview opens **and the exported PDF has 3 pages** |
| `scripts/verify/h5.sh` | Acceptance gate (static asserts + host tests + analyze + on-device BDD) |

---

## Unit test A — `PdfBuilder` multi-page count + order

`PdfBuilder.build` embeds each JPEG verbatim and sets each PDF page's size from the
image's own dimensions. So **distinct image dimensions per page** give each PDF page
a unique `/MediaBox`, and the sequence of MediaBoxes in the (uncompressed) PDF encodes
page order.

Approach:
1. Generate 3 tiny JPEGs with **distinct dimensions** using `package:image` (already a
   dependency, `^4.5.0`) — e.g. 120×60, 80×160, 200×100 — write them to a temp dir,
   build 3 `PageImage`s (position 1..3, `imagePath` = each file, full-frame).
2. `build(pages, compress: false)` (uncompressed so the structure is greppable).
3. Assert **count**: `RegExp(r'/Type\s*/Page(?![s])')` matches exactly **3**.
4. Assert **order + aspect**: extract every `/MediaBox [0 0 W H]` in document order and
   assert the `(W,H)` sequence equals `[(120,60), (80,160), (200,100)]` — proving pages
   appear in the input order, each sized to its own image (original aspect).

This is deterministic, host-only, fast, and would catch a dropped page, a reorder, or a
wrong-aspect regression.

> Rationale for MediaBox-order over byte-offset-of-JPEG: MediaBox is a stable,
> explicitly-ordered PDF structure; asserting the dimension sequence is clearer and less
> brittle than searching for embedded JPEG byte signatures.

## Unit test B — `exportPdf` full path is multi-page

In `drift_document_repository_test.dart`, add a test that exercises the real
repository→builder path end to end (host):
1. `createFromCapture` (page 1) + `addPageToDocument` ×2 (pages 2, 3) using the fixture.
2. `final file = await repo().exportPdf(doc.id);`
3. Read the written bytes; assert `/Type /Page` count == **3**.

Proves `exportPdf` passes **all** pages (not just the first) through to the PDF. (The
default builder compresses, but page-dictionary objects — `/Type /Page`, `/MediaBox` —
are NOT inside the deflated content streams; only the drawing streams are compressed.
Evidence: the existing "builds a valid single-page PDF" test greps `/Type /Page` on
**default-compressed** builder output and passes. So the count regex matches on the
saved compressed file.)

## BDD — 3-page export on device

Reuse the established capture→save flow (H1 add-page) and preview flow (C2).

`apps/mobile/integration_test/h5_multipage_pdf.feature`:
```gherkin
Feature: H5 Multi-page PDF export

  Scenario: Exporting a three-page document produces a three-page PDF
    Given the app is launched with camera permission granted and empty storage
    When I capture and accept the first page
    And I capture and accept the second page
    And I capture and accept the third page
    And I tap Done
    And I open the first document
    And I export the open document to PDF
    Then the PDF preview opens
    And the exported PDF has 3 pages
```

- **Reused steps** (already exist — do NOT recreate): the "given" launch step,
  `iCaptureAndAcceptTheFirstPage`, `iCaptureAndAcceptTheSecondPage`, `iTapDone`,
  `iOpenTheFirstDocument`, `iExportTheOpenDocumentToPdf`, `thePdfPreviewOpens`.
- **New steps:**
  - `i_capture_and_accept_the_third_page.dart` — mirrors the first/second-page step
    (tap shutter → tap accept), adding a 3rd page via the H1 add-page flow.
  - `the_exported_pdf_has3_pages.dart` — reads the mounted `PdfPreviewScreen.pdfPath`
    (public field) via `tester.widget<PdfPreviewScreen>(...)`, opens it with pdfx
    `PdfDocument.openFile(path)` (the same opener the screen uses by default), asserts
    `document.pagesCount == 3`, then `await document.close()` (release the native
    handle). A second read-only open of the already-open file is safe (pdfx opens
    read-only). This is a genuine on-device page-count assertion against the real
    written PDF — no production UI change needed.

This scenario captures three real pages, exports through the real repository + real
`PdfBuilder`, renders via pdfx, and asserts the on-disk PDF has exactly 3 pages —
covering the spec's "opened PDF has N pages in order" on-device check. Order is
authoritatively proven by Unit test A; the BDD proves the end-to-end 3-page flow.

---

## Error Handling

No new error paths. Existing `exportPdf` already throws `DocumentExportException` on a
missing page file / build failure, and `PdfPreviewScreen` shows a `pdf-preview-error`
view when pdfx can't open the file — both already tested. The new BDD step's pdfx
open is on a PDF that `thePdfPreviewOpens` already proved renders, so it will not add a
flaky failure mode.

---

## Testing summary (acceptance-criteria mapping)

Spec 07 acceptance: *"Single/multi-page document exports to a PDF in the library, pages
in order, Original aspect — BDD: 3-page export · unit: page count/order"* and
*"contains no personal metadata"*.

| Criterion | Test |
|---|---|
| Multi-page count | Unit A (`/Type /Page` == 3) + Unit B (exportPdf == 3) |
| Pages in order | Unit A (MediaBox dimension sequence == input order) |
| Original aspect | Unit A (each MediaBox == its image's dimensions) |
| 3-page export end-to-end | BDD (capture 3 → export → preview opens → PDF pagesCount == 3) |
| No personal metadata (multi-page) | Existing `metadata-clean` unit test (same `pw.Document()`; page count doesn't change the info dict) |

Verify harness `scripts/verify/h5.sh` (built on `scripts/verify/lib.sh`, mirrors
`h4.sh`): static asserts that the multi-page unit tests and BDD feature/generated test
exist, host suite green (`All tests passed!`), `flutter analyze` clean (`No issues
found`), and on-device BDD passes. Silence = FAIL; independent adversarial verifier runs
it from a clean state.

---

## Out of Scope (YAGNI)

- Searchable-PDF text layer / OCR (feature 08) — `ImageOnlyTextLayer` stays the default.
- Page-count indicator UI on `PdfPreviewScreen` — not needed; the BDD reads the file
  directly via pdfx.
- Per-page size/quality options, page ranges, password — later features.
- Any change to generation, ordering, or the export button/preview (already built).
