# J1 — Export all pages as images (design)

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 4 — PDF conversion (Feature 10) → document → images
**Depends on:** I1 (`exportPageAsImage` — per-page scrubbed JPG export)
**Reuses:** I1's per-page export (DRY), the shared metadata scrubber.

## Purpose

I1 exports a single page as an image. Users who scanned a multi-page document
often want **every page as an image** in one action (e.g. to attach photos, post
individual pages). This slice adds a document-level "Export all pages as images".

## Scope

**In:**
- `DocumentRepository.exportAllPagesAsImages(documentId)` — exports every page as
  a scrubbed JPG (reusing `exportPageAsImage` per page), returns the files.
- A page-viewer menu action "Export all as images" with a confirmation snackbar.

**Out:** the OS share sheet / save-to-gallery (native, non-assertable — a
follow-up); PDF→image rasterisation of *external* PDFs (that's a different
Feature 10 slice); ZIP bundling.

## UX

- The page viewer's per-page overflow menu (`page-viewer-page-menu`) gains an
  **"Export all as images"** item (`page-viewer-export-all-images`), listed after
  the per-page "Export as image".
- Selecting it exports every page and shows a snackbar **"Exported N image(s)"**
  (singular/plural correct). On failure: **"Couldn't export images"**.
- Mirrors I1's exact interaction (persistent write to the app's document folder +
  confirmation snackbar) — no native sheet, so the flow is fully testable
  on-device. Getting the files off-device (share/save-to-gallery) is a separate
  follow-up, consistent with I1 today.

## Architecture

- **`DocumentRepository.exportAllPagesAsImages(int documentId) → Future<List<File>>`**
  (new interface method):
  - Loads the document's pages (position order) via `getDocumentPages`.
  - Throws `DocumentExportException` when the document has no pages.
  - For each page, delegates to the existing `exportPageAsImage(documentId,
    position)` — same display-image selection (flat ?? original), same metadata
    scrub, same `documents/<id>/page_<n>_export.jpg` target (DRY: zero new file
    logic). Returns the files in page order.
  - Any per-page failure propagates as `DocumentExportException` (partial
    exports are acceptable on disk but the call reports failure).
- **Page viewer** adds the menu item + `_exportAllImages()` that calls the repo
  method and shows the snackbar. Reuses the existing overflow-menu dispatch.

## Data flow

```
menu "Export all as images" ─▶ _exportAllImages()
   └─ repo.exportAllPagesAsImages(docId)
        └─ for each page (order): exportPageAsImage(docId, pos) → scrubbed page_<n>_export.jpg
   ─▶ snackbar "Exported N images"
```

## Error handling

- No pages → `DocumentExportException` → "Couldn't export images" snackbar.
- A missing page file / scrub failure → `DocumentExportException` (propagated
  from `exportPageAsImage`) → same snackbar; the viewer stays put.

## Testing strategy (TDD/BDD first)

**Unit (host):** a 2-page doc with real page files → `exportAllPagesAsImages`
returns 2 files, each starting with the JPEG magic bytes (`0xFF 0xD8`), named
`page_1_export.jpg` / `page_2_export.jpg`; an empty document throws
`DocumentExportException`.

**Widget (host):** fake repo returns 2 files → tapping "Export all as images"
shows "Exported 2 images"; a throwing fake shows "Couldn't export images". Uses
non-loadable page image paths (no `Image.file` host hang).

**BDD (on-device Samsung):** mirrors I1's real-scan flow (no persistent seed
needed — the scan produces a real image):
- *Given the app launched with permission + empty storage, when I scan and
  accept a page, open the document, and Export all as images, then I see the
  export confirmation.*

**On-device deterministic:** seed a 2-page doc with real JPEGs →
`exportAllPagesAsImages` → 2 JPEG files on device.

## Cross-platform

Pure Dart file IO + a Material menu item + snackbar. Identical on iOS/Android.

## Definition of Done

- `exportAllPagesAsImages` on the interface + Drift impl (+ fake), TDD-covered.
- Page-viewer menu action + snackbar, widget-tested.
- `.feature` BDD generated and green on-device; deterministic device test green.
- `flutter analyze` clean; host suite green; `scripts/verify/j1.sh` passes on
  device; plans index updated.
