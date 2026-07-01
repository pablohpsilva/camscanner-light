# K1 — Rotate a page 90° (design)

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 3 — PDF/page editing (Feature 09, "organize → rotate")
**Depends on:** E2 (flat derivative model), O1/O2 (per-page OCR boxes), the
`image` package (pure-Dart raster).

## Purpose

EXIF auto-orientation fixes how a photo is *displayed*, but not the *content*
orientation — a receipt photographed sideways, or a gallery import that came in
rotated, still reads sideways. This slice lets the user rotate a page 90°
clockwise per tap until it's upright, in the page viewer.

## Approach (why baking + box-rotate)

Rotation is **baked into the page's display derivative** (the "flat" file), and
the page's **cached OCR word boxes are rotated by the same quarter-turn**. Every
downstream reader — viewer, thumbnails, PDF builder, searchable text layer,
image export — already reads the flat file (via `displayPath`) and the stored
boxes, so **none of them change**: they simply render/embed the already-rotated
file with boxes that still line up. No new DB column, no re-OCR, no per-consumer
rotation logic.

The `image` package's `copyRotate(src, angle: 90)` rotates **90° clockwise**
(verified in source: a top-left pixel maps to top-right). The matching
normalized box transform is therefore `(l,t,r,b) → (1−b, l, 1−t, r)`, applied
with the identical CW convention so image and boxes stay aligned.

**Accepted limitation (documented):** re-cropping a page *after* rotating
regenerates the flat from the pristine original and thus discards the rotation
(the user would re-rotate). Rotate-then-recrop is uncommon; crop-first-then-
rotate is the normal order. Storing rotation as orthogonal metadata would avoid
this but requires rotation logic in every consumer — rejected as disproportionate.

## UX

- The page viewer's per-page overflow menu (`page-viewer-page-menu`) gains a
  **"Rotate"** item (`page-viewer-rotate`). Each selection rotates the current
  page 90° clockwise and reloads — the rotation is its own visual feedback (no
  snackbar). Repeated taps cycle through orientations.
- Works identically on iOS/Android (pure-Dart raster + a Material menu item).

## Architecture

- **`OcrWordBox.rotate90Cw()`** (new method on the model): returns a new box
  `OcrWordBox(text: text, left: 1 - bottom, top: left, right: 1 - top, bottom:
  right)`. Pure, unit-tested.
- **`DocumentRepository.rotatePage(int documentId, int position)`** (new
  interface method):
  1. Load the page row; throw `DocumentSaveException` if missing.
  2. Read the display bytes (`flatRelativePath ?? relativeImagePath`), decode,
     `img.copyRotate(decoded, angle: 90)`, `img.encodeJpg(rotated, quality: 95)`.
     (`encodeJpg` output carries no EXIF — already metadata-clean, no extra scrub.)
  3. Target flat path = existing `flatRelativePath` ?? `flatForImage(relativeImagePath)`.
     Write the rotated bytes there.
  4. Rotate the cached boxes: `OcrResult.decodeBoxes(row.ocrBoxes)` →
     `.map((b) => b.rotate90Cw())` → re-encode; leave null/empty boxes untouched.
     `ocrText` is unchanged (rotation doesn't change the words).
  5. Update the row: `flatRelativePath` = target (idempotent when already set),
     `ocrBoxes` = rotated encoding, and bump the document's `modifiedAt`.
     `corners` unchanged.
- **Page viewer** adds the menu item + `_rotatePage()` that calls the repo
  method, **evicts the Flutter image cache**, then reloads the pages. On
  failure, a "Couldn't rotate" snackbar.
  - **Image-cache eviction (required):** the rotated bytes are written to the
    **same** flat path on the 2nd+ rotation, but `FileImage` caches by path (not
    content), so the viewer/thumbnail would show the stale pre-rotation image
    without eviction. `_rotatePage` calls
    `PaintingBinding.instance.imageCache.clear()` (and `clearLiveImages()`)
    after `rotatePage` and before `_load()` — one infrequent action, so clearing
    the whole cache is the simplest fully-correct choice (covers the full-res
    viewer image and the `cacheWidth` thumbnails, which have different cache
    keys).

## Data flow

```
menu "Rotate" ─▶ _rotatePage() ─▶ repo.rotatePage(docId, pos)
   ├─ copyRotate(display bytes, 90° CW) ─▶ write flat (rotated)
   └─ decodeBoxes → rotate90Cw each → persist ocrBoxes
 ─▶ reload ─▶ viewer/thumbnail/PDF/export all read the rotated flat + aligned boxes
```

## Error handling

- Missing page row → `DocumentSaveException` → "Couldn't rotate" snackbar.
- Undecodable image bytes → `DocumentSaveException` (thrown) → same snackbar; DB
  and files unchanged.

## Testing strategy (TDD/BDD first)

**Unit (host, pure Dart — no OpenCV):**
- `OcrWordBox.rotate90Cw()`: a top-left box `(0,0,0.2,0.1)` → `(0.9,0,1.0,0.2)`
  (top-right); a round-trip of four rotations returns the original box (within
  float tolerance).
- `rotatePage`: a seeded page with a **non-square** JPEG (e.g. 40×20) and two
  cached boxes → after `rotatePage`, the stored flat image decodes to **20×40**
  (dimensions swapped) and the stored boxes equal the CW-transformed boxes;
  `ocrText` unchanged; a missing page throws `DocumentSaveException`.

**Widget (host):** the viewer's overflow menu shows "Rotate"; tapping it calls
the repository's `rotatePage` (fake records the call) and triggers a reload.

**BDD (on-device Samsung):** mirrors the scan flow —
- *Given the app launched with permission, when I scan and accept a page, open
  it, and Rotate, then the page viewer still shows the page* (proves the action
  is reachable and the reload survives on-device).

**On-device deterministic:** seed a non-square page + real OCR, `rotatePage`,
assert the flat image dimensions swapped and the boxes rotated (the real
correctness proof).

## Cross-platform

Pure-Dart `image` raster + Material menu. No platform channels; identical on
iOS/Android.

## Definition of Done

- `OcrWordBox.rotate90Cw()` + `rotatePage` on the interface + Drift impl (+ fake),
  TDD-covered.
- Viewer "Rotate" action, widget-tested.
- `.feature` BDD generated + green on-device; deterministic device test green.
- `flutter analyze` clean; host suite green; `scripts/verify/k1.sh` passes on
  device; plans index updated.
