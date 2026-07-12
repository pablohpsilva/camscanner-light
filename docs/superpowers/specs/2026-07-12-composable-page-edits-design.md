# Composable, Non-Destructive Page Edits — Design

**Date:** 2026-07-12
**Status:** Approved (design), pending spec review
**Feature area:** `lib/features/library` (page editor + persistence), `lib/features/scan` (capture wiring)

## Problem

Editing a page more than once, or mixing edit operations, corrupts the page or
appears to error. Reproduced on host: rotate a 60×40 landscape page to portrait
(40×60), then crop → the result comes back **48×32 landscape**, i.e. the crop
silently re-derived from the *un-rotated* base and discarded the rotation.

### Root cause

Each page has two files: the **base** (`Pages.relativeImagePath`, the scanned
image) and a **flat** derivative (`Pages.flatRelativePath`, the displayed image
with edits baked into pixels). The image-transform edit operations disagree
about what they read and write:

- `rotatePage` rotates the **flat** (composes on top of prior edits).
- `updatePageCorners` (crop) reads the **base**, warps it, and **overwrites the
  flat** — discarding any rotation that was in the flat.
- `replacePage` (retake) overwrites the base and rebuilds the flat, unaware of
  any transform state.

Because the three operations derive the display from different sources, there is
no single source of truth for the transform chain, so operations do not compose.
This is the whole "can only edit once / mix-and-match breaks" class of bugs.

### The two reported bugs, unified

1. **"Can only edit once; a 2nd rotate/crop or mixing throws/breaks."** → the
   composition flaw above.
2. **"Save the original so the user can crop/alter as many times as they want;
   we currently save the cropped image."** → same root: no preserved original
   that every edit re-derives from.

## Constraints discovered

- **OS scanner gives no pre-crop original.** `cunning_document_scanner`
  (`CunningDocumentScanner.getPictures`) returns an already document-cropped,
  perspective-corrected image. We cannot recover pixels outside the OS's
  document crop. Therefore "the original" we preserve is **the scanned page as
  the OS delivered it** (after our EXIF scrub + enhancement, before the user's
  crop/rotate edits). Named gap — not silent.
- **Never persist absolute image paths** (iOS container GUID changes on
  reinstall). Continue storing relative paths only.
- **TDD + BDD, verified on Android AND iOS** is the non-negotiable gate.

## Approved decisions

1. **Crop editor shows the current (rotated) view** — the user crops what they
   see. Crop corners are therefore captured and stored in the **display frame**
   (the rotated image's coordinate space).
2. **Reuse the existing base as the pristine source** (`relativeImagePath`). No
   new "original" column. The invariant is that **no edit ever writes the base**;
   the flat is a regenerated cache.
3. **Full redesign** of the edit model (not a targeted patch), with exhaustive
   TDD/BDD and device verification.

## Design

### Single source of truth + composable metadata

The base file is pristine and write-once (only `createFromCapture`/`replacePage`
write it, when a *new* image is captured). Every edit is **metadata**; the
displayed flat is **always regenerated** from the base by applying the full
transform chain. Edits therefore compose and repeat infinitely — the bug is
impossible by construction.

### Schema change (Drift `Pages`)

Add:

```dart
/// Number of 90° clockwise quarter-turns applied to the display image
/// (0..3). Rotation is metadata, re-applied during flat regeneration — never
/// baked destructively into the base.
IntColumn get rotationQuarterTurns => integer().withDefault(const Constant(0))();
```

- Bump `schemaVersion` 6 → 7.
- `onUpgrade`: `if (from < 7) await m.addColumn(pages, pages.rotationQuarterTurns);`
- `corners` and `flatRelativePath` keep their columns; `flatRelativePath` is now
  purely a regenerated cache.

### Coordinate model

- `corners` are normalized `[0..1]` in the **display frame** (the image after
  `rotationQuarterTurns` is applied), consistent with decision 1.
- `CropCorners.fullFrame.rotate90Cw() == fullFrame` (rotating the unit square
  yields the unit square with roles relabeled), so an uncropped page stays
  uncropped through any rotation.

### New value-type helper: `CropCorners.rotate90Cw()`

Mirrors the existing `OcrWordBox.rotate90Cw()`. Rotates the four role-tagged
corners (and the four mid-edge deviations) by one 90° clockwise turn in
normalized space, relabeling roles so the *same physical region* is described in
the newly-rotated frame:

- point map (CW): `(x, y) → (1 - y, x)`
- role remap (CW): `topLeft ← bottomLeft`, `topRight ← topLeft`,
  `bottomRight ← topRight`, `bottomLeft ← bottomRight`
- mid deviations rotate with their edges: `top ← left`, `right ← top`,
  `bottom ← right`, `left ← bottom`, each deviation vector `(dx, dy) → (-dy, dx)`.

Pure function, unit-tested independently (4× = identity; fullFrame invariant).

### One regeneration function (used by ALL edit paths)

A single private repository method is the only place that writes the flat:

```
_regenerateFlat(page):
  baseBytes = read(page.relativeImagePath)          // pristine
  rotated   = rotate baseBytes by k×90° CW          // k = rotationQuarterTurns
  if corners == fullFrame:
      flatBytes = (k == 0) ? null : rotated
  else:
      flatBytes = warp(rotated, corners)            // corners in rotated frame
  if flatBytes == null:
      delete existing flat (if any); flatRelativePath = null   // display base
  else:
      write flatBytes to flatForImage(relativeImagePath); flatRelativePath = it
```

Transform order is **rotate-then-crop**: rotate the base pixels, then crop in the
rotated (display) frame. This matches what the user sees and what the editor
captures.

### The three edit operations, unified

- **`rotatePage`**: `k = (k + 1) % 4`; `corners = corners.rotate90Cw()` (keep the
  same physical crop in the new frame); rotate cached OCR boxes (`rotate90Cw`, as
  today); `_regenerateFlat`; bump `modifiedAt`.
- **`updatePageCorners`**: store `corners` (already display-frame from the
  editor); `_regenerateFlat`. A `fullFrame` value clears the crop but keeps the
  rotation. No special-case branch that bypasses regeneration.
- **`replacePage` (retake)**: write the new base; **reset** the transform chain
  (`rotationQuarterTurns = 0`, `corners = capture corners ?? fullFrame`, OCR
  boxes reset by the existing OCR re-trigger); `_regenerateFlat`. A retake is a
  fresh image, so resetting is the correct semantics.
- **`createFromCapture` / `addPageToDocument`**: set `rotationQuarterTurns = 0`,
  `corners` from capture; `_regenerateFlat` (at scan `corners == fullFrame` and
  `k == 0`, so flat is null and the base is displayed — unchanged behavior).

### Editor (`EditCropScreen`) changes

- Accept `quarterTurns` (from `PageImage.rotationQuarterTurns`).
- Display the base wrapped in `RotatedBox(quarterTurns: k)` (cheap, no
  re-encode) so the user crops the rotated view.
- Resolve the displayed image size as the base size with width/height **swapped
  when `k` is odd**, so `CropOverlay` maps correctly.
- Initial overlay corners are the stored display-frame `corners` (no transform
  needed — they are already in the displayed frame).
- Accept pops the edited display-frame corners, stored as-is.

### `PageImage` changes

Add `final int rotationQuarterTurns` (default 0), populated by
`getDocumentPages`, so `_editCrop` can pass `k` to the editor. `displayPath`
logic unchanged (`flatImagePath ?? imagePath`).

### Image cache

`updatePageCorners` (and `replacePage`) must clear the Flutter image cache the
same way `_rotatePage` already does, because the regenerated flat reuses the same
file path; otherwise the stale image is shown. Centralize the
clear-then-reload in the page viewer so every edit path does it.

## Migration limitation (named, not silent)

Legacy pages never recorded a rotation count. A legacy page that was rotated
*before* this upgrade has its rotation baked into the old flat with
`rotationQuarterTurns` defaulting to 0 after upgrade. On that page's **next**
edit, `_regenerateFlat` rebuilds from the base and the previously-baked rotation
is lost (the page reverts to un-rotated, then the new edit applies). This is a
one-time, rare regression for already-rotated legacy documents; it is documented
here and surfaced in the plan, never hidden. New edits are fully correct.

## Error handling

- All three operations keep throwing `DocumentSaveException` on missing page /
  undecodable base / IO failure; the page viewer keeps its existing
  `try/catch → SnackBar` per operation.
- `_regenerateFlat` treats a `null` warp result as "no crop applied" (keep the
  rotated-only image) rather than silently producing a broken flat.
- The base is never written by an edit, so a mid-edit failure can at worst leave
  a stale flat; a retry regenerates cleanly.

## Testing

### Host TDD (unit / repository)

- `CropCorners.rotate90Cw()`: point map, role remap, mid-deviation rotation,
  `fullFrame` invariant, 4× == identity.
- Repository sequences (each asserts display dimensions/orientation AND that the
  **base file bytes are byte-for-byte unchanged** after the edits):
  - rotate ×1, ×2, ×3, ×4 (4 == identity)
  - crop ×2, ×3 (re-crop always from base)
  - **rotate → crop** (the currently-broken case: rotation preserved)
  - crop → rotate (crop preserved, rotation applied)
  - crop → rotate → crop (re-crop in the new rotated frame)
  - rotate → crop → rotate → crop (arbitrary mixing)
  - reset crop to `fullFrame` while rotated (rotation stays)
  - retake resets rotation + corners
  - OCR boxes stay aligned through rotate sequences
- Migration: open a v6 DB with an edited page, upgrade to v7, assert the new
  column exists with default 0 and the page still loads.

### Widget tests

- `EditCropScreen` shows the rotated view for `k ∈ {1,2,3}` (overlay size swaps
  for odd `k`); accept returns display-frame corners.
- Page viewer clears the image cache and reloads after crop and after retake
  (not only after rotate).

### BDD (`integration_test/*.feature` + shared steps)

- A mixed re-edit journey: open a saved document → rotate → crop → rotate again →
  crop again → the page viewer shows the composed result without error. Generated
  `*_test.dart` + steps in `test/step/`.

### Device (both platforms — the gate)

- Run the mixed re-edit `.feature` on a real Android device and a real iOS
  device (opencv warp + `image` rotate exercised on-device). Record device IDs
  and green results.

## Out of scope

- Recovering pre-document-crop pixels from the OS scanner (plugin limitation).
- Re-editable enhancement/filter as a per-page editor option (enhancement is
  chosen at capture time; not a library-editor action today).
- Cropping OCR word boxes to the crop region (pre-existing behavior; boxes rotate
  with rotation but are not clipped by crop).
- Reorder/flat-naming (already handled by path-derived `flatForImage`).
