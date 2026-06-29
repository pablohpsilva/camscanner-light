# E1 — Corner Overlay: Design

**Status:** Approved (brainstorming) — ready for writing-plans
**Date:** 2026-06-29
**Roadmap:** Group E (Manual crop) — E1 corner overlay · E2 perspective flatten · E3 re-edit. E1 is the first slice. Builds on A3 (capture→review), B1 (save/Drift/scrub), B3 (viewer), C1/C2 (PDF), D1/D2/D3 (library mgmt, all done).

## Goal

Let the user adjust the four crop corners of a freshly captured document via a
draggable overlay on the Review screen, and persist the chosen quad as page
metadata. E1 ships only the overlay + persistence; **E2** later applies the
perspective-flatten using these corners, **E3** re-edits them after save.

## Decisions (locked during brainstorming)

1. **Placement:** the overlay is drawn on the existing `CaptureReviewScreen`
   over the captured image (no new screen).
2. **Non-destructive (load-bearing):** Accept persists the corner quad as
   metadata; the stored image bytes remain the **original EXIF-scrubbed
   capture, unflattened**. E2 flattens *from* corners at display/export time;
   E3 re-edits because original + corners both persist. Baking the crop into
   pixels in E1 would make re-edit impossible.
3. **Storage location:** on the **Pages** row (per-page corners) — correct
   granularity and forward-compatible with multi-page (group H); no
   re-migration later. Behavior today is identical (1 page/doc).
4. **Representation:** four **role-tagged** normalized corners
   (`topLeft, topRight, bottomRight, bottomLeft`), each `Offset` in `[0..1]`,
   in the **display (EXIF-applied) frame**, top-left origin.
5. **Reset button:** included (`crop-reset`) — restores full-frame.

## The coordinate-frame contract (critical — read before implementing)

Corners are normalized `[0..1]` against the **displayed** image, i.e. with the
JPEG's EXIF **Orientation** tag applied. This frame must be stable across
review → storage → later consumers:

- `JpegExifScrubber` does **not** decode/re-encode; it copies pixels
  byte-for-byte and **re-emits a minimal Exif APP1 carrying only the original
  Orientation** (rotation preserved as a tag, never baked). Flutter's
  `Image.file` (and the framework image codec) **honor that tag**, so the
  review image, the stored image, and the viewer image are all oriented
  identically. The normalized frame is therefore stable.
- **Natural size must be the EXIF-applied size.** Derive it from the framework
  decoder (`FileImage(...).resolve(...)` → `info.image.width/height`), which
  bakes orientation — **never** from a raw JPEG SOF header read (that returns
  pre-rotation sensor dimensions and misaligns handles on any rotated capture).
- **Contract handed to E2 (documented, must be honored there):** E2's flatten
  must operate in this same display/EXIF-applied frame (honor Orientation), and
  must guard degenerate / self-crossing quads (E1 clamps to bounds only and
  does **not** enforce convexity — see §Components/CropOverlay).

## Architecture

```
shutter
  → CaptureReviewScreen (StatefulWidget)
        ├─ decodes natural size (EXIF-applied, injectable resolver)
        ├─ _imageSize == null → plain image (current behavior)
        └─ _imageSize != null → CropOverlay(imageSize, image, corners, onCornersChanged, enabled)
        └─ bottom bar: Retake · Reset(crop-reset) · Accept(corners)
  → Accept(corners) → camera_screen._onAccept(image, corners)
        → SaveController.save(image, corners: corners)
        → DriftDocumentRepository.createFromCapture(capture, corners: corners)
              → writes scrubbed ORIGINAL bytes (unchanged) + page.corners = corners.toStorage()
```

Image bytes are untouched; only `pages.corners` metadata is added.

## Components

### 1. `lib/features/library/crop_corners.dart` (new, pure Dart)

Persisted page metadata, imported by both the scan overlay and the Drift repo.

```dart
class CropCorners {
  final Offset topLeft, topRight, bottomRight, bottomLeft; // normalized 0..1, display/EXIF frame
  const CropCorners({required this.topLeft, required this.topRight,
                     required this.bottomRight, required this.bottomLeft});

  static const CropCorners fullFrame = CropCorners(
    topLeft: Offset(0, 0), topRight: Offset(1, 0),
    bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1));

  CropCorners clamp();                         // each Offset → [0,1]×[0,1]
  String toStorage();                          // "x0,y0,x1,y1,x2,y2,x3,y3", role order TL,TR,BR,BL, fixed precision
  static CropCorners? tryParse(String? s);     // fail-soft: null/malformed/NaN/inf/wrong-count → null
  // value == / hashCode
}
```

- **Role-tagged fields, never a `List<Offset>`** — dragging never reassigns
  roles; E2 maps slot → output corner even after a crossed drag.
- `fullFrame` is the canonical "uncropped" value — what an untouched / raced /
  decode-failed Accept persists, and what `null`/legacy reads back as.
- `tryParse` never throws (fail-soft) so a bad value can't brick the list/viewer.

### 2. `lib/features/scan/widgets/crop_overlay.dart` (new)

Controlled component (state in the parent, like `SortControlBar`).

```dart
class CropOverlay extends StatelessWidget {
  final Size imageSize;                        // EXIF-applied natural size, INJECTED
  final Widget image;                          // injected (prod: Image.file; tests: sized box)
  final CropCorners corners;
  final ValueChanged<CropCorners> onCornersChanged;
  final bool enabled;                          // false while saving
  const CropOverlay({ super.key, required this.imageSize, required this.image,
    required this.corners, required this.onCornersChanged, this.enabled = true });
}
```

- **Fitted-rect math:** inside a `LayoutBuilder`, compute the `BoxFit.contain`
  rect from `imageSize` + constraints
  (`scale = min(boxW/imgW, boxH/imgH)`; `rect = centeredOffset & (imgSize*scale)`).
  The injected `image` fills `rect`; handles are placed in the **same** `rect`
  → aligned by construction. Handle display pos for `(nx,ny)` =
  `rect.topLeft + Offset(nx*rect.width, ny*rect.height)`.
- **Handles:** four `Positioned` circular handles (keys `crop-handle-tl/-tr/-br/-bl`),
  each its own `GestureDetector` (fixed role — no "which corner" tracking).
  `onPanUpdate` is **delta-based, stateless**: `dNorm = delta / rect.size`,
  `newCorner = (old + dNorm)` clamped to `[0,1]`, then `onCornersChanged`.
- **Clamp-to-bounds only** (topology deferred to E2). A `CustomPainter` draws
  the quad outline `TL→TR→BR→BL→TL` + a dimmed scrim outside it.
- **Accessibility:** each handle wrapped in `Semantics(label: '<corner> crop
  corner')` (consistent with the app-wide icon-label standard).
- **Defensive:** if `imageSize.isEmpty` → render no handles (avoids div-by-zero).
- **Disabled** (`enabled == false`, while saving) → gestures ignored.
- **Handle hit targets** are a comfortable size; an edge corner at full-frame is
  half-grabbable in the letterbox. Add inward bias only if device testing shows
  edge corners are hard to grab — not baked in. When the quad is dragged small,
  overlapping hit targets resolve to the last-painted (topmost) handle.

Root key `crop-overlay`. Testable with an injected `imageSize` + plain `image`
child — no real decode, so no `Image.file` host-test hang.

### 3. `lib/features/scan/capture_review_screen.dart` (modify → StatefulWidget)

- New injectable seam `Future<Size> Function(String path) decodeImageSize`
  (default = real `FileImage` resolver, EXIF-applied).
- State: `CropCorners _corners = CropCorners.fullFrame; Size? _imageSize;`.
  `initState` resolves size → `setState`. **Lifecycle (Gap 17):** the resolve is
  async — `setState` must be `mounted`-guarded (the user may pop first), the
  default resolver's `ImageStreamListener` must be removed in `dispose` (no
  leak), and a decode error must be caught → leave `_imageSize` null (plain
  image), never crash.
- **Breaking signature change (Gap 16):** `onAccept` becomes
  `ValueChanged<CropCorners>`. Unlike the repo's optional `corners` (Gap 6),
  there is **no backward-compat default** here — so the plan MUST migrate every
  existing construction site (`camera_screen`) and every existing
  `capture_review_screen_test` to the new signature, or the suite won't compile.
  (The `review-accept` *key* is unchanged, so the BDD `i_tap_accept` step still
  works.)
- Build: `_imageSize != null` → `CropOverlay(... enabled: !saving,
  onCornersChanged: (c) => setState(() => _corners = c))`; else the plain image
  (current behavior).
- `onAccept` signature changes `VoidCallback` → `ValueChanged<CropCorners>`;
  Accept calls `onAccept(_corners)`.
- Bottom bar: **Retake · Reset · Accept**. `crop-reset` (labeled) →
  `setState(_corners = CropCorners.fullFrame)`, disabled while `saving` or no
  overlay. Retake unchanged (new capture resets corners for free).

### 4. `lib/features/scan/camera_screen.dart` (modify)

`_onAccept(CapturedImage image, CropCorners corners)` →
`_saveController.save(image, corners: corners)`; `ListenableBuilder` wires
`onAccept: (c) => _onAccept(image, c)`.

### 5. `lib/features/scan/save_controller.dart` (modify)

`save(CapturedImage image, {CropCorners corners = CropCorners.fullFrame})` —
optional default keeps existing save tests compiling.

### 6. Repository (migration surface = 3: interface + Drift + Fake)

- **Interface** `document_repository.dart`:
  `createFromCapture(CapturedImage capture, {CropCorners? corners})` — optional
  so existing callers/tests are unbroken.
- **`DriftDocumentRepository`:** write `corners?.toStorage()` on the page insert
  (`null` column = uncropped). `getDocumentPages` returns
  `CropCorners.tryParse(row.corners) ?? CropCorners.fullFrame` (fail-soft).
- **`FakeDocumentRepository`:** accepts `corners` (records `savedCorners` for
  assertions); its `getDocumentPages` + `_FlakyPagesRepo` return the new
  `PageImage` shape.

### 7. `lib/features/library/page_image.dart` (modify)

Add `final CropCorners corners;` with default `= CropCorners.fullFrame` →
existing construction sites (fake, flaky) and consumers (B3 viewer, C1
`PdfBuilder` — both use only `imagePath`) stay non-breaking.

### 8. `lib/features/library/drift/app_database.dart` (modify — schema)

- `Pages` gains `TextColumn get corners => text().nullable()();`.
- `schemaVersion => 2`.
- `MigrationStrategy.onUpgrade: (m, from, to) { if (from < 2) await
  m.addColumn(pages, pages.corners); }`; `beforeOpen` FK pragma stays.
- Old/`null` rows survive and read back as `fullFrame` — no backfill.

## Error handling & edge cases

- **Decode pending / failure:** plain image, no handles; Accept saves
  `fullFrame` (Gap: Accept-before-decode race resolves to full-frame).
- **Degenerate `imageSize`:** no handles (defensive).
- **Malformed/legacy `corners` string:** `tryParse → null → fullFrame`, never
  throws.
- **Self-crossing quad:** allowed in E1 (clamp-to-bounds only); E2 must guard.

## Privacy spine

On-device only; corners are 8 local numbers. Image bytes unchanged (scrubbed
original, Orientation preserved). No network, no new dependency, one nullable
column, relative paths.

## Testing (TDD/BDD)

- **Unit `crop_corners_test.dart`:** `fullFrame`; `clamp`; `toStorage`↔`tryParse`
  round-trip (role order + precision); `tryParse` fail-soft (null/empty/wrong
  count/non-numeric/NaN-inf → null); equality.
- **Widget `crop_overlay_test.dart`:** inject `Size(1000,750)` + plain child (no
  decode/no hang); 4 handles by key + correct full-frame positions; drag
  `crop-handle-tl` → expected normalized `topLeft`; drag past edge → clamps;
  `Size.zero` → no handles; `enabled:false` → no-op; handles carry Semantics
  labels.
- **Widget `capture_review_screen_test.dart` (extend + migrate, Gap 16):** first
  migrate the existing tests + the `camera_screen` call site to the new
  `onAccept: ValueChanged<CropCorners>` signature (else no compile). Then inject
  `decodeImageSize`→known size; overlay after resolve, plain image before/on
  failure; Accept passes current `_corners`; `crop-reset` → full-frame;
  `saving:true` disables Reset + overlay; assert no setState-after-dispose if the
  screen is popped before the resolver completes (Gap 17). Non-loadable image
  path (no hang).
- **Repo `drift_document_repository_test.dart` (extend):** `createFromCapture`
  with corners → `getDocumentPages` round-trips them; without corners → reads
  `fullFrame`.
- **Migration `…/drift/migration_test.dart` (hand-rolled):** build a v1-shaped
  DB (pages without `corners`), insert a page, open `AppDatabase` (v2) to
  trigger `onUpgrade`, assert the column exists, the old row reads `fullFrame`,
  and a fresh corners write works. (Adopt Drift's official schema-dump harness
  when later steps add more migrations.)
- **Integration `e1_crop.feature` → `e1_crop_test.dart`** (wiring smoke test;
  correctness is unit/repo/migration): launch-empty → scan → shutter → see the
  crop overlay → drag the top-left corner → Accept → see the document in the
  list. Two new no-stub-guarded steps: `i_see_the_crop_overlay` (finds
  `crop-overlay`), `i_drag_the_top_left_crop_corner` (drags `crop-handle-tl`).
  Reuses launch/scan/shutter/accept.

## Verification — `scripts/verify/e1.sh` (modeled on d1/d3)

Static asserts: `CropCorners`/`fullFrame`/`toStorage`/`tryParse`;
**`schemaVersion => 2`** + Pages `corners` column + `onUpgrade` `addColumn`;
`CropOverlay` + keys `crop-overlay`/`crop-handle-{tl,tr,br,bl}` + a `Semantics`
label; `crop-reset`; `createFromCapture(` takes `corners`; `PageImage` has
`corners`; **scrubber still re-emits Orientation** (`_minimalExifApp1`/
Orientation — guards the E2 frame contract) and `minimalExifApp1` privacy guard;
no-stub guard on the 2 steps + generated calls; codegen-current +
no-uncommitted-generated-diff; `mobile:test` (incl. migration test) +
`mobile:analyze` + `assert_coverage_floor 70`;
`verify_integration_android/ios e1_crop_test.dart`; fail-closed
`VERIFY_SKIP_DEVICE=1 → GATE:FAIL`; opt-in `REAL_DEVICE` Tier-3 (drag corners on
a physical device; confirm handles track the finger and the doc saves).

## Acceptance criteria

1. Review shows a draggable 4-corner overlay over the captured image once its
   size resolves; hidden before resolve / on decode failure (plain image).
2. Dragging a handle moves that corner, clamped to image bounds; Reset restores
   full-frame.
3. Corners are normalized `[0..1]` in the display (EXIF-applied) frame,
   role-tagged TL/TR/BR/BL.
4. Accept persists the chosen quad on the page row; image bytes remain the
   scrubbed original (non-destructive); corners survive a storage round-trip;
   untouched / null → full-frame.
5. `schemaVersion` 1→2 migration adds the nullable `Pages.corners` column;
   existing rows read back as full-frame; the migration is tested.
6. Handles + Reset are accessibility-labeled (app a11y standard).
7. Privacy: one column, no new dependency, no network, EXIF still scrubbed
   (Orientation preserved), paths relative.
8. Documented contract to E2: flatten must honor EXIF Orientation (same display
   frame) and guard degenerate / self-crossing quads.
9. TDD/BDD: unit + widget + repo round-trip + migration + both-platform
   integration + verify gate green; `REAL_DEVICE` Tier-3 deferred with standing
   sign-off.
