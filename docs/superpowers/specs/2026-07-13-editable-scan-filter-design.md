# Editable Scan Filter (Non-Destructive) — Design

**Date:** 2026-07-13
**Status:** Approved (design), pending implementation plan
**Related:** [[composable-page-edits]] (this feature adds the third composable
edit field), `docs/superpowers/specs/2026-07-12-composable-page-edits-design.md`

## Goal

Let the user change a scanned page's enhancement filter (Auto / Original /
Color / Grayscale) after capture, from the page editor, as many times as they
want, without any loss of quality. Achieved by storing the pristine *unfiltered*
original and treating the enhancer as composable page metadata — so the
displayed image is always regenerated from the original.

## Problem (why this is needed)

Today the chosen enhancer is **baked into the base image file at capture time**
(`createFromCapture` / `addPageToDocument` enhance `bytesToStore` before writing)
and the pre-filter pixels are discarded. `_writeFlat` regenerates the display
("flat") derivative by applying only rotate-then-crop from that already-enhanced
base — it never re-enhances. Consequently the filter cannot be changed after the
fact, and re-filtering would stack on top of the previously baked filter.

## The invariant this preserves

The composable-edits invariant already states: the base image
(`Pages.relativeImagePath`) is PRISTINE and write-once; every edit is metadata;
the displayed `flatRelativePath` is ALWAYS regenerated from the base by the
single helper `_writeFlat`. This feature makes the base *truly* pristine
(unfiltered) and adds the enhancer as a third composable metadata field
alongside `rotationQuarterTurns` and `corners`.

## Chosen approach

**Enhancer as composable metadata.** Considered and rejected:

- **Separate "original" sidecar file** (keep base enhanced, add an
  `originalRelativePath` unfiltered file): two sources of truth, extra column
  and storage, breaks the single-pristine-base invariant.
- **Re-scan / replacePage-style flow**: cannot undo a previously applied filter
  without the original, so it collapses into "store the original" anyway.

The chosen approach fits the documented invariant exactly and reuses the
existing `PageProcessor.process(bytes, corners, mode)` pipeline (native +
Dart fallback), which already warps+enhances a crop and enhances a full frame.

## Architecture

### Regeneration model

The displayed flat is regenerated as **`enhance ∘ rotate ∘ crop`** from the
pristine base. `_writeFlat` gains an `EnhancerMode mode` parameter and routes
the pixel work through `PageProcessor.process`:

1. Read pristine base bytes.
2. **Fast path** — when `quarterTurns == 0 && corners == fullFrame &&
   mode == none`, the display equals the base: delete any stale flat and return
   `null` (no flat).
3. Rotate off the UI isolate (existing `compute(rotateAndBakeJpeg, …)`) when
   `quarterTurns != 0`.
4. Let `input = rotatedBytes ?? baseBytes`.
5. Produce `flatBytes`:
   - **Full frame** (`corners == fullFrame`):
     - `mode == none` → `flatBytes = rotatedBytes` (non-null here, since the
       pure pass-through was handled in step 2).
     - `mode != none` → `flatBytes = process(input, fullFrame, mode)`, falling
       back to enhancing `input` directly, else `input`.
   - **Cropped** (`corners != fullFrame`):
     - `flatBytes = process(input, corners, mode)`, falling back to a warp-only
       result, else `rotatedBytes`, matching the current fallback chain.
6. Write `flatBytes` to the flat path (reusing `existingFlatRel` when present);
   return its relative path. When `flatBytes == null`, delete any stale flat and
   return `null`.

All heavy decode/rotate/warp/enhance work stays off the UI isolate (via
`compute` inside `rotateAndBakeJpeg` and inside the processor's warp+enhance
pass), preserving the freeze fix from the composable-edits follow-up.

### Data model (schema v7 → v8)

- Add column `Pages.enhancerMode`:
  `IntColumn get enhancerMode => integer().withDefault(const Constant(0))();`
  It stores the `EnhancerMode` enum **index**. The enum order is fixed as
  `enum EnhancerMode { none, grayscale, auto, color }` → `none=0, grayscale=1,
  auto=2, color=3`.
- Bump `schemaVersion` 7 → 8.
- `onUpgrade`: `if (from < 8) await m.addColumn(pages, pages.enhancerMode);`
- Legacy rows default to `none (0)`.

### Capture path changes

`createFromCapture` and `addPageToDocument`:

- Write the **unfiltered** scrubbed bytes as the base (stop enhancing
  `bytesToStore`).
- Persist the chosen `enhancerMode` on the page row.
- Generate the flat through the shared enhance→rotate→crop path (same code
  `_writeFlat` uses), so a filtered scan stores BOTH the pristine original and
  the enhanced display image (two files when a filter is active; one file when
  the filter is Original and there is no crop/rotation).

`replacePage` (retake) likewise stores an unfiltered base and the chosen
`enhancerMode`, resetting the transform chain (`rotationQuarterTurns = 0`) as it
does today.

### Repository API

Add to `DocumentRepository`:

```dart
/// Re-applies [mode] to page ([documentId], [position]) non-destructively:
/// regenerates the displayed flat from the pristine base and persists the mode.
/// Never writes the base. OCR is not re-run (a tonal filter changes no text).
Future<void> updatePageEnhancer(int documentId, int position, EnhancerMode mode);
```

Implementation loads the page, calls
`_writeFlat(relativeImagePath, rotationQuarterTurns, corners, mode,
existingFlatRel)`, and writes `enhancerMode` + `flatRelativePath` + bumps
`documents.modifiedAt`.

`PageImage` gains `final EnhancerMode enhancerMode` (default `none`), surfaced
from `getDocumentPages` so the editor can preselect the current filter.

### UI — dedicated Filter screen

- New 7th action on `EditorToolbar`: key `page-viewer-filter`, `Icons.tune`,
  label "Filter". `EditorToolbar` gains an `onFilter` callback. A null callback
  disables it (consistent with the other five).
- Tapping it opens `EditFilterScreen`, which mirrors `CaptureReviewScreen`: the
  page shown large, with the existing `FilterPickerStrip` (Auto / Original /
  Color / Grayscale live thumbnails) at the bottom.
  - Source bytes for the strip previews = the page's **unfiltered base**
    (`pg.imagePath`), so previews are accurate and never stack.
  - Initial selection = the page's stored `enhancerMode`.
  - A Save/confirm control returns the selected `EnhancerMode`
    (`Navigator.pop<EnhancerMode>`); back/cancel returns `null`.
- The page-viewer's `_editFilter` handler applies the result via the existing
  `_runEdit` single-flight guard (disables the toolbar, shows the busy overlay,
  refuses re-entry) and `_reloadAfterEdit`/`_imageEpoch` ValueKey refresh — so
  the freeze and stale-display fixes from the composable-edits follow-up cover
  this action too.
- DRY cleanup: extract the `EnhancerMode → ImageEnhancer` switch (currently
  inline in `capture_review_screen.dart`) into a shared top-level helper
  `ImageEnhancer enhancerForMode(EnhancerMode mode)` and use it in both screens.
  (The repository's `_writeFlat` works in terms of `EnhancerMode` directly via
  `PageProcessor.process`, so it does not need the concrete enhancer.)

## Error handling

- Enhancement/warp failures inside the processor are already silent and fall
  back (enhance the un-warped frame, else the input) — `updatePageEnhancer`
  inherits this; a failed regen still yields a usable page.
- A flat-write IO failure leaves the previous flat/mode untouched: the update
  writes `enhancerMode` and `flatRelativePath` together, so on a thrown IO error
  the whole `updatePageEnhancer` fails and the row is unchanged. `_runEdit`
  surfaces a "Couldn't change filter" snackbar.
- `EditFilterScreen` returning `null` (cancel) is a no-op — no DB write.

## Legacy gap (accepted, documented)

Pages captured before v8 have no stored unfiltered original (the filter was
baked into the base) and default to `enhancerMode = none`. Changing the filter
on such a page re-filters the already-filtered base, so results may stack
(e.g. Grayscale over a previously-baked Auto), and the initially-highlighted
tile ("Original") may not match how the page actually looks. This is the same
class of accepted limitation as the "page rotated before v7 resets rotation on
its next edit" gap. New captures (v8+) are fully lossless.

## Testing

TDD + BDD, verified green on Android AND iOS (project non-negotiable).

**TDD (host):**
- Migration v7 → v8: column added, defaults to 0, existing rows readable.
- `createFromCapture` / `addPageToDocument` store an **unfiltered** base
  (base bytes differ from the enhanced flat), persist the chosen `enhancerMode`,
  and produce an enhanced flat when a filter is active.
- `updatePageEnhancer` regenerates the flat from the pristine base and persists
  the mode; the base file is byte-identical before and after.
- **No stacking**: a sequence filter → crop → filter → rotate re-derives the
  display from the pristine base each time (changing filter twice does not
  compound; switching back to Original yields the un-enhanced crop/rotation).
- `_writeFlat` with a non-`none` mode applies enhance∘rotate∘crop.
- `EditFilterScreen` widget test: renders the strip, preselects the stored mode,
  returns the selected mode on confirm and `null` on cancel.
- Page-viewer Filter button: opens the screen, applies single-flight
  (a 2nd tap while in flight is ignored), and bumps the image key epoch so the
  same-path flat re-decodes.

**BDD:**
- A `.feature` scenario "change a saved page's filter" with steps in
  `test/step/`, generated via `build_runner`.

**Device (Android + iOS):**
- On a real photo, change the filter repeatedly (and mix with crop/rotate):
  verify losslessness, no UI freeze, and that the display refreshes each time.

## Global constraints

- Bump `schemaVersion` and add the `onUpgrade` step for the new column.
- Store RELATIVE image paths only; never write the base during an edit.
- Keep all full-res decode/rotate/warp/enhance work off the UI isolate.
- Edits remain single-flight with the `_imageEpoch` ValueKey display refresh.
- Nothing is "done" until TDD + BDD are green on a real Android device AND a
  real iOS device (or a named, explicit gap).
