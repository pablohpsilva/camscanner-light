# Scan ID — Design

Date: 2026-07-08
Status: Approved (pending spec review)
Branch: `feat/scan-id`

## Goal

Add a "Scan ID" feature: a guided 2-step capture (front, then back of an ID card)
that produces a document whose PDF export is a **single portrait A4 page with
both images centered, vertically stacked**. The ID is stored as a normal 2-page
document in the library, flagged as an ID card so only its PDF layout differs.

## Decisions (approved)

- **Stored as a library document** (2 pages: front, back), flagged `isIdCard`.
- **PDF layout:** one portrait A4 page, front on the top half + back on the
  bottom half, both centered horizontally, aspect ratio preserved, with margins.
- **No filter/review step:** scan front → scan back → saved. Images are the OS
  scanner's already-cropped output (full-frame corners, `NoneEnhancer`).
- **Entry point:** a Home app-bar action `home-scan-id` (credit-card icon),
  alongside the existing Import action.

## Architecture

Feature-first, following existing patterns (const-constructible `*Dependencies`
DI; Drift schema + migration; `PdfBuilder` for PDF; `SaveController` +
`DriftDocumentRepository` for persistence).

### 1. Entry point + `IdScanScreen`

- `HomeScreen`: add an app-bar `IconButton` (key `home-scan-id`,
  `Icons.badge_outlined`, tooltip "Scan ID card") that
  pushes `IdScanScreen(dependencies:, repository:)` and `_refresh()` on return.
- `IdScanScreen` (StatefulWidget, `lib/features/scan/id_scan_screen.dart`) — a
  thin coordinator with two steps:
  1. Shows "Scan the front" prompt; calls
     `dependencies.createDocumentScanner().scan(pageLimit: 1)`. On a returned
     page, holds it as `_front` and advances to step 2. On empty/cancel, pops.
  2. Shows "Scan the back" prompt; `scan(pageLimit: 1)`. On a returned page,
     holds it as `_back` and proceeds to save. On empty/cancel, offers
     retry/back (nothing persisted yet).
  - **Save (only after both captured):**
    `doc = SaveController.save(front, corners: CropCorners.fullFrame, enhancer: NoneEnhancer())`
    then `addPage(back, doc.id, corners: fullFrame, enhancer: NoneEnhancer())`,
    then mark the document `isIdCard = true` (see repository below). Pop to Home.
  - On save failure, surface a SnackBar and offer retry (mirror `ScanScreen`'s
    save-failure handling).
  - Build: a minimal scaffold showing the current step ("Front"/"Back") + a
    spinner while the native scanner is up. Same constructor shape considerations
    as `ScanScreen` (dependencies + repository).

### 2. Storage: `isIdCard` flag

- **Schema (Drift, `drift/app_database.dart`):** add
  `BoolColumn get isIdCard => boolean().withDefault(const Constant(false))();`
  to the **Documents** table. Bump `schemaVersion 5 → 6`; add
  `if (from < 6) await m.addColumn(documents, documents.isIdCard);` to
  `onUpgrade`. Regenerate `app_database.g.dart` via build_runner.
- **Domain model (`document.dart`):** `Document` gains `final bool isIdCard`
  (default false); map it in the row→model conversion.
- **Repository:** a way to persist the flag. Simplest: after saving both pages,
  call a new `DocumentRepository.markAsIdCard(int documentId)` (updates the row's
  `isIdCard = true`, bumps `modifiedAt`). Alternatively thread an `isIdCard`
  param through `createFromCapture` — but a dedicated `markAsIdCard` keeps the
  capture path unchanged and is simpler to test. **Use `markAsIdCard`.**

### 3. Combined PDF layout: `PdfBuilder`

- Current `PdfBuilder.build(List<PageImage> pages, {bool compress, ExportQuality quality})`
  adds one `pw.Page` per image, page format = image dimensions.
- Add an id-card layout mode via an optional `bool idCardLayout = false`
  parameter on `build(...)`. When true: emit **one**
  `pw.Page(pageFormat: PdfPageFormat.a4)` whose body is a centered
  `pw.Column` (main-axis center) of the pages' images, each wrapped so it
  preserves aspect ratio and fits the page width minus margins (front first,
  back second), with vertical spacing between them and page margins around.
  Handle 1 image (just center it) and 2 images (stack) gracefully; if >2, still
  stack all on the one page (ID is expected to be exactly 2).
- Keep the default (per-image page) path unchanged.

### 4. Export wiring

- `DriftDocumentRepository.exportPdf` (and everything routed through it —
  preview, share, print) reads the document's `isIdCard` and calls
  `PdfBuilder.build(pages, idCardLayout: doc.isIdCard, ...)`. No other library
  behavior (OCR, viewer, rename, delete, sort, search) changes — an ID is an
  ordinary 2-page document everywhere else.

## Data flow

Home "Scan ID" → `IdScanScreen` → OS scanner ×2 (front, back) → `save(front)` +
`addPage(back)` → `markAsIdCard(docId)` → Home refresh. Later: export/share/print
→ `exportPdf` sees `isIdCard` → `PdfBuilder` id-card layout → 1-page A4 PDF.

## Error handling

- Cancel/empty on front → pop, no document created.
- Cancel/empty on back → nothing persisted (save happens only after both); offer
  retry or discard.
- Save failure (create or add-page) → SnackBar + retry affordance; if `addPage`
  fails after `create` succeeded, the doc exists with only the front — surface
  the error and let the user retry the back from the viewer (existing retake), or
  delete. (Acceptable rare path; do not silently leave a broken state.)
- iOS PNG capture is already handled by `ensureJpegBytes` in the save pipeline.

## Testing (TDD/BDD, both platforms)

- **Host unit:** `pdf_builder_id_card_test.dart` — 2 `PageImage`s with
  `idCardLayout: true` → the built PDF has exactly **1** page (vs 2 in default
  mode); assert both images are placed (via the page-count / RecordingPdfBuilder
  pattern already used in `export_combined_pdf_test.dart`). Aspect-ratio /
  centering assertion where feasible.
- **Host widget:** `id_scan_screen_test.dart` with a fake `DocumentScannerService`
  returning one page per `scan()` call (non-loadable paths) + `FakeDocumentRepository`:
  two scans → `createCalls == 1`, `addPageCalls == 1`, `markAsIdCard` called with
  the doc id; front-cancel → no save; back-cancel → no save.
- **Migration:** a v5→v6 schema test (open a v5 DB, upgrade, assert `isIdCard`
  column exists and defaults false) following the existing migration-test pattern.
- **Repository:** `markAsIdCard` sets the flag + bumps `modifiedAt`; `exportPdf`
  passes `idCardLayout` when `isIdCard`.
- **BDD `.feature`:** scan an ID (fake scanner) → a 2-page id-card document is in
  the library → exporting it yields a 1-page PDF.
- **Device (Android + iOS):** the real 2-step OS-scanner flow, save, and the
  1-page PDF export/share. Named required device gap.

## Out of scope

- No dedicated ID "template" fields (name/number extraction), no MRZ parsing.
- No change to the normal (non-ID) scan, import, OCR, or export paths.
- No new ID-specific viewer; the standard 2-page viewer is used.

## Risks / open items

- `PdfPageFormat.a4` + preserving each image's aspect ratio within the page:
  compute display size from image aspect vs available box; verify no overflow.
- `markAsIdCard` vs threading a flag through `createFromCapture`: chose
  `markAsIdCard` to keep the capture path untouched; the small window where the
  doc exists un-flagged (between save and mark) is harmless (defaults to false →
  normal layout) and only matters if the app is killed mid-flow.
</content>
