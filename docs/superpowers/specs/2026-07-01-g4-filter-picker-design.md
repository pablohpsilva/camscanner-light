# G4 Filter Picker UI — Implementation Design

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** G1 (`GrayscaleEnhancer`), G2 (`BwEnhancer`), G3 (`AutoEnhancer`, `ColorEnhancer`, `_EnhancerMode` enum), `image` 4.9.1
**Feeds:** H1 (multi-page)
**Step in roadmap:** G4 — Filter picker UI (fourth and final of G. Enhancement series)

## Purpose

Replace the four individual AppBar icon toggle buttons (grayscale, bw, auto, color) added in
G1–G3 with a proper **filter picker strip**: a horizontally scrollable row of filter tiles
positioned between the image view and the bottom action bar. Each tile shows the filter name
and a small live thumbnail (generated from a downsampled version of the current image).

Additionally, change the default enhancement mode from `none` to `auto` — Auto/Magic is the
"smart" default for most scans.

### In scope
- `FilterPickerStrip` widget — horizontally scrollable row of filter tiles with live thumbnails
- Remove the four AppBar icon buttons from `CaptureReviewScreen`
- Default `_mode` changed from `_EnhancerMode.none` to `_EnhancerMode.auto`
- Thumbnail generation: downsample image to ≤150 px wide, run each enhancer in a `compute`
  isolate, display result as the tile thumbnail

### Out of scope
- DB column for enhancement mode (deferred — requires schema migration + E3 changes)
- Non-destructive re-selection after save (deferred with DB column)
- Manual sliders (brightness/contrast)
- Multi-page filter application

---

## Architecture

### New: `lib/features/scan/widgets/filter_picker_strip.dart`

A self-contained widget. Takes `_EnhancerMode selectedMode`, `void Function(_EnhancerMode)
onModeChanged`, and `Uint8List? sourceBytes` (nullable — when null, tiles show icon-only
placeholders while the image loads). Generates thumbnails internally using a `FutureBuilder` /
`compute` pattern.

```
FilterPickerStrip
├── Scrollable row of FilterTile widgets
│   ├── FilterTile('Auto',      Key('filter-tile-auto'),       AutoEnhancer)
│   ├── FilterTile('Original',  Key('filter-tile-original'),   NoneEnhancer)
│   ├── FilterTile('Color',     Key('filter-tile-color'),      ColorEnhancer)
│   ├── FilterTile('Grayscale', Key('filter-tile-grayscale'),  GrayscaleEnhancer)
│   └── FilterTile('B&W',       Key('filter-tile-bw'),         BwEnhancer)
└── Thumbnail generation (internal Future<Map<_EnhancerMode, Uint8List?>>)
```

**Filter order (fixed):** Auto · Original · Color · Grayscale · B&W

**Tile anatomy:**
- Selected tile: 2 px border in `colorScheme.primary`, white label
- Unselected tile: no border, grey87 label
- Thumbnail area: 64 × 64 px; shows `CircularProgressIndicator` while loading, then the
  generated thumbnail via `Image.memory`, falls back to a large icon on error
- Label below the thumbnail: filter name, 11 sp, truncated

**Thumbnail generation:**
1. Receive `sourceBytes` (the original image bytes, already read by `CaptureReviewScreen`)
2. Downsample to ≤150 px wide in a `compute` isolate (`_thumbFn` top-level function) using
   `img.copyResize`
3. Run each enhancer's `enhance()` on the downsampled bytes concurrently (5 futures, all
   fired at once with `Future.wait`)
4. Thumbnails are `Uint8List` (JPEG bytes); displayed with `Image.memory`
5. If `sourceBytes` is null or empty, skip generation — show icon placeholders

**Internal state:** `Map<_EnhancerMode, Uint8List?> _thumbs` — null = not yet generated,
non-null = ready. Widget calls `setState` once all five are done (single batch update).

### Modified: `lib/features/scan/capture_review_screen.dart`

Three changes only:

1. **Import** `filter_picker_strip.dart`
2. **Default mode**: `_EnhancerMode _mode = _EnhancerMode.auto;`
3. **AppBar**: Remove the four `IconButton` actions (grayscale-toggle, bw-toggle, auto-toggle,
   color-toggle). AppBar becomes title-only.
4. **Body**: Insert `FilterPickerStrip` between the image stack and the `bottomNavigationBar`.
   Pass `sourceBytes: _sourceBytes` (a new `Uint8List?` field populated by the existing
   `readBytes` call — see Data Flow below).

**New field `_sourceBytes`:** `Uint8List? _sourceBytes;` — populated in `initState` alongside
`decodeImageSize`:
```dart
widget.readBytes(widget.image.path).then((b) {
  if (!mounted) return;
  setState(() => _sourceBytes = b);
}).catchError((_) {});
```
(The existing `readBytes` injectable is already present; this just captures its result.)

**Layout change (body):**

```dart
body: Column(
  children: [
    Expanded(
      child: Stack(
        children: [
          // ... existing image + overlay ...
        ],
      ),
    ),
    FilterPickerStrip(
      key: const Key('filter-picker-strip'),
      selectedMode: _mode,
      onModeChanged: (m) => setState(() => _mode = m),
      sourceBytes: _sourceBytes,
    ),
  ],
),
```

The `bottomNavigationBar` (Retake / Reset / Accept) is unchanged.

---

## Data Flow

```
CaptureReviewScreen.initState()
  → readBytes(image.path) → _sourceBytes: Uint8List?
  → setState() → FilterPickerStrip(sourceBytes: _sourceBytes)

FilterPickerStrip._generateThumbs(sourceBytes)
  → compute(_thumbFn, sourceBytes)     // downsample to ≤150px wide
      → _autoFn(downsampled)           // in parallel (Future.wait)
      → _colorFn(downsampled)
      → GrayscaleEnhancer().enhance()
      → BwEnhancer().enhance()
      → NoneEnhancer().enhance()       // identity; returns immediately
  → setState({ _thumbs = results })

User taps 'Grayscale' tile
  → FilterPickerStrip.onModeChanged(_EnhancerMode.grayscale)
  → CaptureReviewScreen setState(_mode = .grayscale)
  → Accept button switch → GrayscaleEnhancer() → repository
```

---

## Keys (testable anchors)

| Widget | Key |
|--------|-----|
| FilterPickerStrip container | `Key('filter-picker-strip')` |
| Auto tile | `Key('filter-tile-auto')` |
| Original tile | `Key('filter-tile-original')` |
| Color tile | `Key('filter-tile-color')` |
| Grayscale tile | `Key('filter-tile-grayscale')` |
| B&W tile | `Key('filter-tile-bw')` |

**Removed keys** (icon buttons deleted from AppBar):
`Key('grayscale-toggle')`, `Key('bw-toggle')`, `Key('auto-toggle')`, `Key('color-toggle')`

---

## Global Constraints

- JPEG output quality 92 (thumbnails too — `img.encodeJpg(thumb, quality: 85)` for thumbnails
  is acceptable since they are display-only; source remains unmodified)
- `compute()` isolate for all CPU work — `_thumbFn` is a top-level function
- `img.bakeOrientation(decoded)` in `_thumbFn` before resize
- OCP: `ImageEnhancer`, `GrayscaleEnhancer`, `BwEnhancer`, `AutoEnhancer`, `ColorEnhancer`,
  `NoneEnhancer`, `SaveController`, `DriftDocumentRepository`, `CameraScreen` must not be
  modified
- Error resilience: any thumbnail generation failure → that tile shows the icon placeholder
- `FilterPickerStrip` is `StatefulWidget`; const constructor; all enhancer calls remain
  const-constructible at the Accept site in `CaptureReviewScreen`

---

## BDD Scenarios

**Feature file:** `integration_test/g4_filter_picker.feature`

```gherkin
Feature: G4 Filter picker strip

  Scenario: Filter picker strip is visible on the review screen
    Given the review screen is open with a captured image
    Then I see the filter picker strip

  Scenario: Auto filter is selected by default
    Given the review screen is open with a captured image
    Then the auto filter tile is selected

  Scenario: Tapping Grayscale tile saves with GrayscaleEnhancer
    Given the review screen is open with a captured image
    When I tap the grayscale filter tile
    And I tap Accept
    Then the document is saved with grayscale enhancement

  Scenario: Tapping Original tile saves without enhancement
    Given the review screen is open with a captured image
    When I tap the original filter tile
    And I tap Accept
    Then the document is saved without enhancement
```

---

## Testing Strategy

| Layer | What is tested |
|-------|----------------|
| Widget: `FilterPickerStrip` | Five tiles present (`Key('filter-tile-*')`) when `sourceBytes` is null |
| Widget: `FilterPickerStrip` | Tapping a tile calls `onModeChanged` with correct mode |
| Widget: `FilterPickerStrip` | Selected tile has a highlighted border (ColoredBox or DecoratedBox with border color == primary) |
| Widget: `CaptureReviewScreen` | Default mode is Auto (`filter-tile-auto` is selected on first render) |
| Widget: `CaptureReviewScreen` | `filter-picker-strip` present; old toggle keys absent |
| Widget: `CaptureReviewScreen` | Tap Original tile → Accept → `NoneEnhancer` |
| Widget: `CaptureReviewScreen` | Tap Grayscale tile → Accept → `GrayscaleEnhancer` |
| Widget: `CaptureReviewScreen` | Tap B&W tile → Accept → `BwEnhancer` |
| Widget: `CaptureReviewScreen` | Tap Color tile → Accept → `ColorEnhancer` |
| Widget: `CaptureReviewScreen` | Tap Auto tile → Accept → `AutoEnhancer` |
| Widget: `CaptureReviewScreen` | Saving state disables Accept (regression) |
| Widget: `CaptureReviewScreen` | Retake and Reset still work (regression) |
| Unit: `_thumbFn` | Returns 5 valid JPEG entries (one per mode) for a valid input |
| Unit: `_thumbFn` | Corrupt bytes → returns map with null values, no crash |
| BDD | filter picker strip visible |
| BDD | Auto selected by default |
| BDD | Grayscale tile → GrayscaleEnhancer |
| BDD | Original tile → NoneEnhancer |
| Static | `filter_picker_strip.dart` exists; `Key('filter-picker-strip')` in source; old toggle keys absent from `capture_review_screen.dart` |

---

## Verify Script

`scripts/verify/g4.sh` — follows `lib.sh` pattern:
- Static: `filter_picker_strip.dart` exists; `Key('filter-picker-strip')` present; `Key('filter-tile-auto')` present; old toggle keys NOT in `capture_review_screen.dart`; feature file and generated test exist
- `pnpm nx run mobile:test` passes
- `pnpm nx run mobile:analyze` clean
- Coverage ≥ 70%
- BDD device gate (skippable with `VERIFY_SKIP_DEVICE=1`)

---

## Deliverable (user-testable)

The review screen shows a horizontal filter strip below the captured image. Tiles are:
Auto · Original · Color · Grayscale · B&W. Auto is highlighted by default. Tapping a tile
immediately highlights it. Small thumbnails appear (with spinner while generating) showing
what each filter does to the current image. The AppBar is clean (no icon buttons). Accept
saves with the selected filter.

**Test it by:**
1. Take a scan → review screen opens with Auto highlighted.
2. Tap each filter tile — thumbnail previews show the effect.
3. Tap Original → accept → image saved with no enhancement.
4. Tap Grayscale → accept → image saved grayscale.

---

## Acceptance Criteria

- [ ] `FilterPickerStrip` widget in `lib/features/scan/widgets/filter_picker_strip.dart`
- [ ] Five tiles with keys `filter-tile-{auto,original,color,grayscale,bw}`
- [ ] `CaptureReviewScreen` default mode is `_EnhancerMode.auto`
- [ ] Old AppBar icon toggle buttons removed
- [ ] `FilterPickerStrip` embedded in review screen body
- [ ] Tapping a tile passes correct `ImageEnhancer` to `onAccept` — *widget*
- [ ] Thumbnail generation: valid input → thumbnails visible; corrupt → icon fallback — *unit + widget*
- [ ] G1/G2/G3 acceptance pipeline unchanged (`SaveController`, etc.) — *no code changes*
- [ ] BDD scenarios: picker visible, auto default, grayscale tile, original tile — *integration*
- [ ] All host tests pass; analyze clean; coverage ≥ 70% — *verify script*

---

> **Definition of Done gate:** Per `00-overview-roadmap.md`, this feature is not done until
> every acceptance criterion above maps to a passing test, the full suite is green, quality
> gates pass, and the work is reviewed and double-checked.
