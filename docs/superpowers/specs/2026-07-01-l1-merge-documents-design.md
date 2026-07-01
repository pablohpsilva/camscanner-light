# L1 — Merge documents (design)

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 3 — PDF/page editing (Feature 09, "organize → merge")
**Depends on:** B1 (page/file model), D2 (`deleteDocument`).

## Purpose

Users often scan related pages into separate documents and later want them as
one. This slice merges **another document's pages into the currently-open
document**, in order, then removes the now-empty source — a core "organize"
capability.

## Approach

Merge operates on our own page model (no PDF surgery): each source page's
**image, flat derivative, corners, and cached OCR text/boxes are copied
verbatim** into the target document at continuing positions, then the source
document is deleted. Because every page is copied as-is (image + its own
boxes), there is **no orientation/OCR-alignment coupling** — a copied page looks
and searches exactly as it did in the source.

**Collision-free file naming (the key correctness point):** page image
filenames are fixed at creation and decoupled from position (reorder/delete
don't rename files), so a leftover file from a deleted page can occupy a
position-derived name. To guarantee no clash in the target directory, merged
files are named from the **source document id + source position**:
`documents/<targetId>/page_m<sourceId>_<sourcePos>.jpg` (and its flat via the
existing `flatForImage`). The source id is unique and never previously used in
the target, so the name is guaranteed free. Nothing parses these names — page
order comes from the position column — so an arbitrary unique name is safe.

## UX

- The page viewer's per-page overflow menu (`page-viewer-page-menu`) gains a
  **"Merge another document…"** item (`page-viewer-merge`).
- Selecting it opens a **picker dialog** (`merge-picker-dialog`) listing every
  OTHER document (name + page count), newest first. Tapping one merges its pages
  into the open document and reloads the viewer showing the combined pages.
- If there are no other documents, the dialog shows *"No other documents to
  merge."* (`merge-picker-empty`).
- On failure, a "Couldn't merge" snackbar. Identical on iOS/Android (pure Dart
  + a Material dialog).

## Architecture

- **`DocumentRepository.mergeInto(int targetDocumentId, int sourceDocumentId)`**
  (new interface method):
  1. Reject `target == source` → `DocumentSaveException`.
  2. Load target pages (for the current max position; 0 if none) and source
     pages (ascending position).
  3. For each source page k (1-based, in position order):
     - Copy the source image bytes → `documents/<targetId>/page_m<sourceId>_<sourcePos>.jpg`.
     - If the source page has a flat, copy its bytes → `flatForImage(thatImageRel)`.
     - Insert a target page row: `position = targetMax + k`, `relativeImagePath`
       = the new image path, `flatRelativePath` = the new flat path (or null),
       `corners`, `ocrText`, `ocrBoxes` copied from the source row.
  4. Bump the target's `modifiedAt`.
  5. `deleteDocument(sourceDocumentId)` (reused — removes source rows + dir).
  - Row inserts run in one transaction; file copies happen before the inserts.
    An IO failure throws `DocumentSaveException` (target unchanged enough to be
    safe — worst case is orphan copied files, which no row references).
- **`MergePickerDialog`** (new widget): given the current document id and the
  repository, loads `listDocumentSummaries`, filters out the current document,
  and returns the chosen document id (or null). Empty → the empty message.
- **Page viewer** wires the menu item → shows the dialog → on a chosen id calls
  `mergeInto(currentId, chosenId)`, evicts nothing special (new files have new
  names — no stale cache), then reloads.

## Data flow

```
menu "Merge another document…" ─▶ MergePickerDialog(list other docs)
      └─ pick sourceId ─▶ repo.mergeInto(currentId, sourceId)
             ├─ copy each source page's image/flat → target dir (unique names)
             ├─ insert target rows at maxPos+1.. (corners/ocrText/ocrBoxes copied)
             └─ deleteDocument(sourceId)
      ─▶ reload ─▶ viewer shows combined pages in order
```

## Error handling

- `target == source`, or IO/DB failure → `DocumentSaveException` → "Couldn't
  merge" snackbar; the viewer stays put.
- Picker cancelled (tap outside / no selection) → no-op.

## Testing strategy (TDD/BDD first)

**Unit (host):**
- target (2 pages) + source (2 pages, one with a flat + OCR boxes) →
  `mergeInto` → target has **4** pages, positions 1..4, the source pages last
  and in order; the source document and its dir are gone; the copied page's flat
  file exists and its `ocrWords`/`ocrText` match the source; the copied image
  files exist under the target dir with the `page_m<sourceId>_*` names.
- `mergeInto(x, x)` throws `DocumentSaveException`.
- merging a source whose page has NO flat leaves the copied page's
  `flatImagePath` null.

**Widget (host):**
- `MergePickerDialog` lists other documents (not the current one) and returns
  the tapped id; with only the current document it shows `merge-picker-empty`.
- The viewer's "Merge another document…" opens the dialog; choosing a document
  calls the fake repo's `mergeInto(currentId, chosenId)` and reloads.

**BDD (on-device Samsung):** two real scans then merge —
- *Given the app launched, when I scan and accept a page, then scan and accept
  another as a separate document, open the first, and merge the second into it,
  then the document shows two page thumbnails.*

**On-device deterministic:** seed a 2-page target + 1-page source with real
files, `mergeInto`, assert target has 3 pages and the source is gone.

## Cross-platform

Pure Dart file IO + drift + a Material dialog. No platform channels.

## Definition of Done

- `mergeInto` on the interface + Drift impl (+ fake), TDD-covered.
- `MergePickerDialog` + viewer wiring, widget-tested.
- `.feature` BDD generated + green on-device; deterministic device test green.
- `flutter analyze` clean; host suite green; `scripts/verify/l1.sh` passes on
  device; plans index updated.
