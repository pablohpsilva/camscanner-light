# M1 — Split a document (design)

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 3 — PDF/page editing (Feature 09, "organize → split")
**Depends on:** B1 (page/file model), L1 (verbatim page-copy pattern), D2 (delete).

## Purpose

The inverse of merge (L1): divide a multi-page document into two. "Split after
this page" keeps pages 1..N in the current document and moves the pages after
the current one into a **new** document — e.g. separating two receipts scanned
into one document.

## Approach

Reuses L1's verbatim page-copy (image + flat + corners + cached OCR text/boxes,
no re-encode) — but into a **fresh** document directory, so page filenames are
`page_<k>.jpg` with no collision risk (empty dir). The moved pages are then
removed from the source (rows + files); the source keeps its head pages
1..position, which are already contiguous, so **no renumbering** is needed.

## UX

- The page viewer's per-page overflow menu (`page-viewer-page-menu`) gains a
  **"Split after this page"** item (`page-viewer-split`), after "Merge another
  document…".
- Selecting it on any page **except the last** moves the following pages to a new
  document named *"<name> (split)"*, shows a **"Split into a new document"**
  snackbar, and reloads the viewer (now showing only the head pages).
- On the **last** page there is nothing to split off → a *"This is the last page
  — nothing to split after."* snackbar (no repository call).
- On failure, a *"Couldn't split"* snackbar. Identical on iOS/Android.

## Architecture

- **`DocumentRepository.splitAfter(int documentId, int position) → Future<Document>`**
  (new interface method):
  1. Load source pages (ascending). Let `maxPos` = last position. Throw
     `DocumentSaveException` if `position < 1` or `position >= maxPos` (nothing
     to split off).
  2. Create a new document row: name `"<sourceName> (split)"`, `createdAt` =
     `modifiedAt` = now.
  3. For each source page with `pos > position` (ascending), at new position
     `k = 1,2,…`: copy the image bytes → `documents/<newId>/page_<k>.jpg`; copy
     the flat bytes (if any) → `flatForImage(thatImage)`; insert a new-document
     row with `corners`/`ocrText`/`ocrBoxes` copied verbatim.
  4. In one transaction, delete the moved rows from the source and bump the
     source's `modifiedAt`.
  5. Best-effort delete the moved pages' source image/flat files (after commit).
  6. Return the new `Document`.
  - IO/DB failures throw `DocumentSaveException` (rethrowing if already one).
- **Page viewer** adds the menu item + `_splitAfter()`: the last-page guard
  (`_current >= _pages.length - 1`), the repository call, snackbars, and reload.

## Data flow

```
menu "Split after this page" ─▶ _splitAfter()
   ├─ last page? → "nothing to split after" snackbar (no repo call)
   └─ else ─▶ repo.splitAfter(docId, currentPos)
                ├─ new doc "<name> (split)"
                ├─ copy pages > pos (verbatim) → new doc at 1..M
                └─ delete moved pages from source (rows + files)
        ─▶ "Split into a new document" snackbar ─▶ reload (head pages only)
```

## Error handling

- `position` last/invalid → `DocumentSaveException` (also guarded in the UI so
  the last-page case shows a specific message without a repo call).
- IO/DB failure → `DocumentSaveException` → "Couldn't split" snackbar; viewer
  stays put.

## Testing strategy (TDD/BDD first)

**Unit (host):**
- 3-page source, `splitAfter(1)` → source has **1** page (position 1); the new
  document has **2** pages (the former pages 2 & 3, positions 1 & 2), its name
  ends with `(split)`, its page files exist, and a moved page's `ocrText`/
  `ocrWords`/flat are preserved.
- `splitAfter(maxPos)` (last page) throws `DocumentSaveException`.
- `splitAfter(0)` throws `DocumentSaveException`.

**Widget (host):**
- 2-page viewer (current = first page) → "Split after this page" calls the fake
  repo's `splitAfter(docId, 1)` and shows "Split into a new document".
- 1-page viewer (the only page is the last) → "Split after this page" shows
  "This is the last page…" and does NOT call `splitAfter`.
- No `Image.file` host hang (non-loadable page paths).

**BDD (on-device Samsung):** two captures in one scan then split —
- *Given the app launched, when I scan and accept two pages, open the document,
  and split after the first page, then I see the split confirmation.*

**On-device deterministic:** seed a 3-page source, `splitAfter(1)`, assert the
source has 1 page and the returned document has 2.

## Cross-platform

Pure Dart file IO + drift + a Material menu/snackbar. No platform channels.

## Definition of Done

- `splitAfter` on the interface + Drift impl (+ fake), TDD-covered.
- Viewer "Split after this page" action, widget-tested.
- `.feature` BDD generated + green on-device; deterministic device test green.
- `flutter analyze` clean; host suite green; `scripts/verify/m1.sh` passes on
  device; plans index updated.
