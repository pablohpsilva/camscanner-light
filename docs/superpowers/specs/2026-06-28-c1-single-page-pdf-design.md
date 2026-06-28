# C1 — Single-page PDF (design)

**Status:** approved (design phase)
**Date:** 2026-06-28
**Roadmap:** group **C (PDF)**, step **C1** — the walking-skeleton milestone. First slice of **Feature 07 (PDF export)**.
**Depends on:** B1 (document+page storage, EXIF-scrubbed JPEG keeping Orientation), B2 (documents list), B3 (page viewer + delete).
**Feeds:** C2 (in-app PDF preview), Feature 08 (OCR text layer via the seam below), Feature 12 (sharing).

## Goal

An **Export to PDF** action on a saved document generates a **1-page,
metadata-clean PDF** from the stored JPEG, **orientation-corrected losslessly**,
with a **pluggable text-layer seam** so OCR can later inject a searchable layer
with no rework. The PDF is generated **on demand** to a deterministic on-device
path. Preview (C2) and the other Feature-07 surfaces are out of scope here.

## Scope (locked)

**In:** the Export action; lossless single-page PDF generation; matrix-based
orientation correction; metadata scrubbing (by construction); the pluggable
`PdfTextLayer` seam (image-only impl today).
**Deferred (each its own step):** multi-page (group **H**), in-app preview
(**C2**), password/AES-256 (later Feature-07 slice), off-UI-thread isolate,
sharing (Feature 12), DB persistence of the artifact.

## What B1/B2/B3 already provide (so C1 does not rebuild it)

- `DocumentRepository.getDocumentPages(int) → Future<List<PageImage>>` where
  `PageImage { int position; String imagePath (absolute) }` (B3).
- Stored page JPEGs are EXIF-scrubbed but **keep the Orientation tag**
  losslessly (B1). **Verified by spike:** the `exif` package reads `Image
  Orientation` correctly from an actual `JpegExifScrubber` *output* (not just the
  input fixture).
- `DocumentFileStore` (relative→absolute at read time) — extended with
  `pdfRelativeFor(int docId) → 'documents/$docId/export.pdf'`.
- The B3 `PageViewerScreen` AppBar (already hosts the delete action) — gains the
  Export action. `deleteDocumentDir` already deletes `documents/<id>/`
  recursively, so `export.pdf` is cleaned up for free on document delete.

## Dependency

The pure-Dart **`pdf`** package (DavBfr) — fully on-device, no network.
**Spike-confirmed** on this toolchain:
- `pw.MemoryImage(jpegBytes)` embeds the JPEG **losslessly** — the output PDF
  contains `/DCTDecode` and the **original JPEG bytes verbatim** (no decode, no
  re-encode).
- The **default `pw.Document()` is already metadata-clean**: it emits **no**
  `/Producer`, `/Creator`, `/Author`, or `/CreationDate`. (Counter-intuitively,
  passing `producer: ''` is *worse* — it injects a `dart_pdf` attribution URL
  and a `/CreationDate`. So the scrub is: **set no info fields.**) Only a trailer
  `/ID` remains.

## Architecture (SOLID/KISS/DRY)

Split along the existing grain — the repository is the single IO surface the
widget knows; the build is a pure unit.

```
PdfBuilder
  build(List<PageImage> pages, PdfTextLayer textLayer) : Future<Uint8List>
    • reads each page JPEG's bytes + EXIF Orientation (exif pkg)
    • embeds the raw JPEG LOSSLESSLY (pw.MemoryImage → /DCTDecode)
    • orientation: pageMatrix() applies pdfOrientationTransform(exif) (see below)
    • Stacks textLayer.overlayFor(page) over the image (image-only → nothing)
    • builds with the DEFAULT pw.Document() — no info fields (metadata-clean)

DocumentRepository.exportPdf(int documentId) : Future<File>
    • getDocumentPages(documentId) → PdfBuilder.build(...) →
      fileStore.writeRelative(pdfRelativeFor(documentId), bytes) → return File
    • throws DocumentExportException on any failure (e.g. a missing page file)

abstract interface PdfTextLayer { List<pw.Widget> overlayFor(PageImage page); }
class ImageOnlyTextLayer implements PdfTextLayer { overlayFor(_) => const []; }
```

- **`PdfBuilder` is injected into `DriftDocumentRepository`** exactly like
  `scrubber` / `fileStore` / `clock` already are;
  `LibraryDependencies._defaultCreateRepository` constructs the real one with
  `ImageOnlyTextLayer()`. Host tests pass a real `PdfBuilder` on a temp file
  store (it is pure — no mocking).
- **No read-model change:** `PageImage` stays `{position, imagePath}`; the
  builder reads bytes + EXIF itself (it already opens each file to embed it).
- **DIP intact:** the viewer calls `widget.repository.exportPdf(documentId)` —
  the **same one-dependency shape as `deleteDocument`**. The viewer stays dumb.

### Orientation: lossless matrix-rotate (pure mapping, all 8 values)

PDF image XObjects ignore EXIF Orientation, so a JPEG that displays upright
on-screen (via its tag) would render rotated in a PDF. C1 corrects it with the
PDF transform matrix on the **losslessly-embedded** raw JPEG (no re-encode).

The mapping is a **pure, independently-tested function**:

```
pdfOrientationTransform(int exifOrientation) : ({int quarterTurns, bool flip})
  1→(0,false) 2→(0,true) 3→(2,false) 4→(2,true)
  5→(1,true)  6→(1,false) 7→(3,true) 8→(3,false)   // 1=90° CW
```

The builder swaps the **page** width/height for the 90°/270° cases (orientations
5,6,7,8) so the page aspect matches the corrected image aspect. The image
dimensions are read from the JPEG header (no full decode).

### Why off-thread is safely deferred (not hand-waved)

The embed is **lossless / decode-free** (DCTDecode passthrough), and page-sizing
reads dimensions from the JPEG header — so single-page generation does **no pixel
decode** and stays fast *regardless of image megapixels*. The isolate arrives
with multi-page (group H). Feature-07 criterion 5 (off-UI-thread) is therefore
explicitly **deferred** for C1.

## Deliverable & UX

- **Export action** (`Icons.picture_as_pdf`, key `page-viewer-export`) in the
  `PageViewerScreen` AppBar, beside delete. **Disabled while `_loading`/`_error`**
  (no pages to export).
- Tap → `repository.exportPdf(documentId)` writes `documents/<id>/export.pdf`
  (overwrites) → a **"PDF saved" SnackBar**. No preview yet (C2); the observable
  result is the SnackBar + the file on disk.
- **Failure** (missing/corrupt page, empty doc) → `DocumentExportException` →
  caught by the viewer → **error SnackBar "Couldn't export PDF", stays on the
  viewer** (mirrors B3's screen-owned delete-failure path; `mounted`-guarded
  after the await).

## Migration surface (exact files)

- `lib/.../document_repository.dart` — add `exportPdf` + `DocumentExportException`.
- `lib/.../drift/drift_document_repository.dart` — implement `exportPdf` (inject `PdfBuilder`).
- `lib/.../pdf/pdf_builder.dart` — **new** `PdfBuilder` + `pdfOrientationTransform`.
- `lib/.../pdf/pdf_text_layer.dart` — **new** `PdfTextLayer` + `ImageOnlyTextLayer`.
- `lib/.../document_file_store.dart` — add `pdfRelativeFor`.
- `lib/.../library_dependencies.dart` — construct the real `PdfBuilder`.
- `lib/.../page_viewer_screen.dart` — Export action + success/error SnackBars.
- `test/support/fake_library.dart` — `FakeDocumentRepository.exportPdf` + a `throwOnExport` flag (returns a synthesized temp `File`).
- `pubspec.yaml` — add `pdf`.
- New non-square fixture (see Testing) + new test files + `integration_test/c1_export_pdf.feature` (+ generated test + steps).

## Testing (TDD/BDD first)

- **`pdfOrientationTransform` (pure):** unit-test **all 8** EXIF values →
  expected `(quarterTurns, flip)` — exercises the flip cases (2,4,5,7) with no
  image fixture.
- **`PdfBuilder`:**
  - valid 1-page PDF (`%PDF` header; exactly one page object — use a **robust
    tokenizer** for the page count, NOT a naive `/Type /Page` literal: the `pdf`
    package may emit `/Type/Page` without a space).
  - **lossless:** `/DCTDecode` present **and** the original JPEG bytes appear
    **verbatim** in the output.
  - **orientation (non-vacuous):** uses a **new non-square fixture** (e.g.
    200×100) tagged **EXIF Orientation = 6** — assert the **page width/height are
    swapped** to the corrected aspect (a square fixture cannot prove this).
  - **metadata-clean:** output contains no `/Author`, `/Producer`, `/Creator`,
    `/CreationDate`, and no `dart_pdf`/`DavBfr` URL (these live in the
    **uncompressed** Info dict — greppable).
  - **seam (two ways, because page content is `/FlateDecode`-compressed):**
    (1) a **spy `PdfTextLayer`** asserts `overlayFor` was **called** with the
    correct `PageImage` (no PDF parsing); (2) build that one case with
    `compress: false` and a stub layer emitting known text → assert the text
    appears in the (uncompressed) stream. `ImageOnlyTextLayer` → no overlay.
- **`DocumentRepository.exportPdf`:** writes `documents/<id>/export.pdf`, returns
  a `File` that exists and is a valid PDF; a missing page file →
  `DocumentExportException`.
- **`PageViewerScreen` export action:** success → "PDF saved" SnackBar, stays;
  failure (fake `throwOnExport`) → error SnackBar, stays; action disabled while
  loading/error. (Viewer tests use the fake `exportPdf` — assert wiring.)
- **Regression (privacy spine):** the metadata-clean assertion **is** C1's
  privacy check; B1/B2/B3 guarantees unaffected.

## Proof tiers

| Tier | Proves | Automatable |
|---|---|---|
| 1 — host (`PdfBuilder` + `exportPdf` on a temp store) | valid + lossless + metadata-clean + page-dim swap + seam fires | ✅ in-gate |
| 2 — integration (android + ios) | seed doc → cold launch → open → tap Export → "PDF saved" SnackBar + `export.pdf` exists & is a valid 1-page PDF | ✅ |
| 3 — **REAL_DEVICE** (deferred) | the exported PDF opens and the page is **visually upright + legible** | ❌ manual |

Host asserts the **page-dimension swap + that a transform is applied + lossless
bytes**; the *pixel-level* upright/legibility is REAL_DEVICE, consistent with the
B2/B3 thumbnail-upright deferral.

## Verification harness

`scripts/verify/c1.sh` on the existing `lib.sh`:
- static asserts: `PdfBuilder`, `pdfOrientationTransform`, `exportPdf` on the
  interface, `PdfTextLayer`/`ImageOnlyTextLayer`, `pdf` in `pubspec`,
  `pdfRelativeFor`, `schemaVersion => 1` (no schema change), scrubber
  `minimalExifApp1` (privacy regression),
- codegen-current, `mobile:test`, `analyze`, coverage floor 70,
- `verify_integration_android`/`_ios c1_export_pdf_test.dart`,
- **no-empty-stub guard** (each new BDD step is real + the generated test calls
  every step),
- negative control: `VERIFY_SKIP_DEVICE=1 → GATE: FAIL` (fail-closed),
- opt-in REAL_DEVICE Tier-3 (open the PDF, confirm upright),
- `GATE: PASS` only on exit 0 + marker.

## Acceptance criteria (each closed only by a passing test)

1. An Export action produces a valid **1-page PDF** on-device from the stored
   JPEG. — *BDD: export · unit: valid single page*
2. The embedded image is **lossless** (`/DCTDecode` + original JPEG verbatim, no
   re-encode). — *unit*
3. Orientation is **matrix-corrected**: `pdfOrientationTransform` is correct for
   all 8 EXIF values, and the page dimensions swap for 90°/270° (non-square
   fixture). *(REAL_DEVICE: visually upright.)* — *unit*
4. The PDF is **metadata-clean** — no author/producer/creator/creationdate, no
   library-attribution URL. — *unit (privacy spine)*
5. **Pluggable `PdfTextLayer`** — a stub injects text (and `overlayFor` is
   invoked per page) with no `PdfBuilder` change; image-only adds none. — *unit*
6. Export failure (missing/corrupt page, empty doc) → **graceful error**
   (SnackBar), never a crash. — *unit/widget*
7. *(REAL_DEVICE, deferred)* the exported PDF opens and renders upright +
   legible. — *manual*

Criteria 1–6 are gated host/emulator/sim. Criterion 7 is the opt-in REAL_DEVICE
lane, deferred-with-sign-off consistent with B1/B2/B3.

## Known gaps / non-goals (explicit)

- No multi-page (H), no in-app preview (C2), no password/AES-256, no
  off-UI-thread isolate (justified above), no DB persistence (regenerate on
  demand), no sharing (Feature 12).
- The trailer `/ID` (a file identifier, not personal/device data) remains —
  **accepted**, neutralizable later if desired.
- "Renders upright/legible" pixel verification is REAL_DEVICE; host verifies the
  page-dim swap + transform wiring + lossless bytes.
- Mirrored EXIF orientations (2,4,5,7) are covered by the pure-function test, not
  by image fixtures (no such camera fixture exists yet).

## Spikes

**Already green (this design):** (1) `pdf` lossless JPEG embed + metadata-clean
default; (2) `exif` reads Orientation from a real `JpegExifScrubber` output.
**For the plan's first task:** confirm the `PdfBuilder` orientation path yields
the host-assertable **page-dim swap** on the new non-square EXIF-6 fixture.

## Privacy spine (binding, unchanged)

PDF generated **on-device** only; no cloud, no network calls. Metadata-clean **by
construction**; the file lives in the app's documents dir beside its source.
Nothing is uploaded, shared, cached off-device, or indexed externally.
