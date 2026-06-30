# G3 Color & Auto-Magic Filters — Implementation Design

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** G1 (`GrayscaleEnhancer`), G2 (`BwEnhancer`), `image` 4.9.1, `_EnhancerMode` enum
**Feeds:** G4 (filter picker UI)
**Step in roadmap:** G3 — Color + Auto-Magic binarization filters (third of G. Enhancement series)

## Purpose

Add Color and Auto-Magic enhancement filters to the scan pipeline. After G1
(grayscale) and G2 (B&W), G3 completes the filter set before G4 introduces the
proper picker UI:

- **Color filter**: subtle contrast lift + slight brightness boost. Keeps the
  image in full color; good for already-clean color document scans.
- **Auto/Magic filter**: per-channel histogram auto-levels (1st–99th percentile
  stretch) + saturation boost. Whitens the background, pops contrast, makes any
  document look like a clean, professional scan.

Auto/Magic is the more impactful filter and should be considered the "smart"
default for most scans (Auto/Magic-as-default is deferred to G4's non-destructive
model; in G3 it is a manual toggle matching G1/G2 UX).

## Scope

**In scope:**
- `AutoEnhancer` strategy class implementing `ImageEnhancer`
- `ColorEnhancer` strategy class implementing `ImageEnhancer`
- `_otsuAutoLevels()` private helper — per-channel 1%-99% histogram stretch
- Third and fourth icon buttons (`Key('auto-toggle')`, `Key('color-toggle')`)
  in `CaptureReviewScreen`'s AppBar
- Extend `_EnhancerMode` enum with `.auto` and `.color` variants
- Update Dart 3 exhaustive switch in the Accept button

**Out of scope:**
- Auto as the default filter (G4, non-destructive storage)
- Manual sliders (brightness/contrast; deferred per spec)
- Filter picker UI (G4)
- Live preview thumbnails (G4)
- DB column for enhancement mode (G4)

## Architecture

### New: `lib/features/library/auto_enhancer.dart`

```dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'image_enhancer.dart';

class AutoEnhancer implements ImageEnhancer {
  const AutoEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_autoFn, bytes);
}

Uint8List _autoFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final oriented = img.bakeOrientation(decoded);
    _autoLevels(oriented);                                   // per-channel histogram stretch
    img.adjustColor(oriented, saturation: 1.15);             // subtle saturation boost
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
  } catch (_) {
    return bytes;
  }
}

// Per-channel auto-levels: clips 1% of pixels on each end to find robust
// black/white points, then stretches each channel to [0, 255].
// Operates on an already-decoded Image in-place.
void _autoLevels(img.Image src) {
  final n = src.width * src.height;
  if (n == 0) return;
  final clip = (n * 0.01).round().clamp(1, n ~/ 2);

  for (final channel in [0, 1, 2]) {    // R, G, B
    final hist = List<int>.filled(256, 0);
    for (final px in src) {
      hist[_channel(px, channel).toInt()]++;
    }
    int lo = 0, cumLo = 0;
    while (lo < 255 && cumLo + hist[lo] < clip) { cumLo += hist[lo++]; }
    int hi = 255, cumHi = 0;
    while (hi > lo && cumHi + hist[hi] < clip) { cumHi += hist[hi--]; }
    if (hi <= lo) continue;
    final range = (hi - lo).toDouble();
    for (final px in src) {
      final v = ((_channel(px, channel).toInt() - lo) * 255 / range)
          .round().clamp(0, 255);
      _setChannel(px, channel, v);
    }
  }
}

num _channel(img.Pixel px, int c) =>
    c == 0 ? px.r : c == 1 ? px.g : px.b;

void _setChannel(img.Pixel px, int c, int v) {
  if (c == 0) px.r = v;
  else if (c == 1) px.g = v;
  else px.b = v;
}
```

### New: `lib/features/library/color_enhancer.dart`

```dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'image_enhancer.dart';

class ColorEnhancer implements ImageEnhancer {
  const ColorEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_colorFn, bytes);
}

Uint8List _colorFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final oriented = img.bakeOrientation(decoded);
    img.adjustColor(oriented, contrast: 1.1, brightness: 1.05);
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
  } catch (_) {
    return bytes;
  }
}
```

`img.adjustColor` parameters (`image` 4.9.1) — verified against source:
- `contrast`: factor applied as `r = 0.5*(1-contrast) + r*contrast` (1.0 = no change; 1.1 = 10% boost)
- `brightness`: scalar multiplier on normalised [0,1] pixel values (1.0 = no change; 1.05 = 5% brighter)

### Modified: `lib/features/scan/capture_review_screen.dart`

**Extended enum** (adds two variants):

```dart
enum _EnhancerMode { none, grayscale, bw, auto, color }
```

**AppBar actions** — two new mutually exclusive icon buttons appended after bw-toggle:

```dart
// Auto/Magic — per-channel auto-levels + saturation boost
IconButton(
  key: const Key('auto-toggle'),
  icon: Icon(
    Icons.auto_fix_high,
    color: _mode == _EnhancerMode.auto
        ? Theme.of(context).colorScheme.primary
        : null,
  ),
  tooltip: _mode == _EnhancerMode.auto ? 'Auto on' : 'Auto off',
  onPressed: () => setState(() => _mode =
      _mode == _EnhancerMode.auto
          ? _EnhancerMode.none
          : _EnhancerMode.auto),
),
// Color — gentle contrast lift, full-color output
IconButton(
  key: const Key('color-toggle'),
  icon: Icon(
    Icons.color_lens,
    color: _mode == _EnhancerMode.color
        ? Theme.of(context).colorScheme.primary
        : null,
  ),
  tooltip: _mode == _EnhancerMode.color ? 'Color on' : 'Color off',
  onPressed: () => setState(() => _mode =
      _mode == _EnhancerMode.color
          ? _EnhancerMode.none
          : _EnhancerMode.color),
),
```

**Accept button** — Dart 3 exhaustive switch (add two arms):

```dart
switch (_mode) {
  _EnhancerMode.grayscale => const GrayscaleEnhancer(),
  _EnhancerMode.bw        => const BwEnhancer(),
  _EnhancerMode.auto      => const AutoEnhancer(),
  _EnhancerMode.color     => const ColorEnhancer(),
  _EnhancerMode.none      => const NoneEnhancer(),
}
```

**Imports to add:**
```dart
import '../library/auto_enhancer.dart';
import '../library/color_enhancer.dart';
```

## Data flow

```
User taps Auto toggle (review screen)
  → _mode = _EnhancerMode.auto

User taps Accept
  → widget.onAccept(_corners, AutoEnhancer())
  → CameraScreen._onAccept(image, corners, AutoEnhancer())
  → SaveController.save(image, corners: corners, enhancer: AutoEnhancer())
  → DriftDocumentRepository.createFromCapture(...)
      → scrub → warp (if cropped) → AutoEnhancer.enhance(bytes) [compute isolate]
      → auto-levels + saturation boost → JPEG quality 92 → write to disk
```

Identical flow for `ColorEnhancer`. `CameraScreen`, `SaveController`, and
`DriftDocumentRepository` need no changes.

## Global Constraints

- JPEG output, quality 92 everywhere (not PNG)
- `compute()` isolate for all CPU-intensive work — never blocks UI thread
- `img.bakeOrientation()` before any pixel processing
- OCP: existing `ImageEnhancer`, `NoneEnhancer`, `GrayscaleEnhancer`, `BwEnhancer`,
  `SaveController`, `DriftDocumentRepository`, `CameraScreen` are unmodified
- Const-constructible enhancers: `const AutoEnhancer()`, `const ColorEnhancer()`
- Error resilience: any decode/process failure → return bytes unchanged, no throw

## BDD scenarios

**Feature file:** `integration_test/g3_auto_color.feature`
**Step defs reused from G1/G2:**
- `the_review_screen_is_open_with_a_captured_image.dart`
- `the_document_is_saved_without_enhancement.dart`
- `i_tap_accept.dart` (or equivalent)

**New step defs:**
- `i_toggle_the_auto_filter.dart` — `tester.tap(find.byKey(const Key('auto-toggle')))`
- `the_document_is_saved_with_auto_enhancement.dart` — asserts `g1Repo.lastSavedEnhancer is AutoEnhancer`
- `i_toggle_the_color_filter.dart` — `tester.tap(find.byKey(const Key('color-toggle')))`
- `the_document_is_saved_with_color_enhancement.dart` — asserts `g1Repo.lastSavedEnhancer is ColorEnhancer`

```gherkin
Feature: G3 Color and Auto-Magic scan enhancement

  Scenario: Auto filter applied — document saved with auto enhancement
    Given the review screen is open with a captured image
    When I toggle the auto filter
    And I tap Accept
    Then the document is saved with auto enhancement

  Scenario: Color filter applied — document saved with color enhancement
    Given the review screen is open with a captured image
    When I toggle the color filter
    And I tap Accept
    Then the document is saved with color enhancement

  Scenario: No filter — document saved without enhancement
    Given the review screen is open with a captured image
    When I tap Accept
    Then the document is saved without enhancement
```

## Testing strategy

| Layer | What is tested |
|-------|----------------|
| Unit: `AutoEnhancer` | Low-contrast fixture → output has higher contrast (max-min spread > input spread) |
| Unit: `AutoEnhancer` | Output image is still color (R ≠ G or G ≠ B on a color fixture) |
| Unit: `AutoEnhancer` | EXIF orientation baked: `landscape_exif6.jpg` (200×100, orient=6) → 100×200 |
| Unit: `AutoEnhancer` | Corrupt bytes → input unchanged, no throw |
| Unit: `AutoEnhancer` | Uniform image (all same color) → returns valid JPEG, no crash |
| Unit: `ColorEnhancer` | Output still color (R ≠ G or G ≠ B on a color fixture) |
| Unit: `ColorEnhancer` | EXIF orientation baked |
| Unit: `ColorEnhancer` | Corrupt bytes → input unchanged, no throw |
| Unit: `NoneEnhancer` | Identity bytes — regression from G1 |
| Widget: `CaptureReviewScreen` | `Key('auto-toggle')` and `Key('color-toggle')` present in AppBar |
| Widget: `CaptureReviewScreen` | Tap Auto → `onAccept` called with `AutoEnhancer`; tooltip shows 'Auto on' |
| Widget: `CaptureReviewScreen` | Tap Color → `onAccept` called with `ColorEnhancer`; tooltip shows 'Color on' |
| Widget: `CaptureReviewScreen` | Tap grayscale then Auto → only `AutoEnhancer` (mutual exclusion) |
| Widget: `CaptureReviewScreen` | Tap Auto then Color → only `ColorEnhancer` (mutual exclusion) |
| Widget: `CaptureReviewScreen` | Tap active Auto again → `NoneEnhancer` (toggle off) |
| Widget: `CaptureReviewScreen` | Tap active Color again → `NoneEnhancer` (toggle off) |
| Widget: `CaptureReviewScreen` | Grayscale and B&W toggles still work (regression) |
| Widget: `CaptureReviewScreen` | Saving state disables accept button (regression) |
| BDD | Auto on → `AutoEnhancer` reaches repository |
| BDD | Color on → `ColorEnhancer` reaches repository |
| BDD | No toggle → `NoneEnhancer` reaches repository |
| Static | `auto_enhancer.dart` exists; `Key('auto-toggle')` present; `_autoLevels` present |
| Static | `color_enhancer.dart` exists; `Key('color-toggle')` present |

## Verify script

`scripts/verify/g3.sh` — follows `lib.sh` pattern (same as `g2.sh`):
- Static assertions: `auto_enhancer.dart` exists, `color_enhancer.dart` exists,
  `Key('auto-toggle')` in source, `Key('color-toggle')` in source,
  `_autoLevels` function present, `AutoEnhancer` implements `ImageEnhancer`,
  `ColorEnhancer` implements `ImageEnhancer`, feature file exists, generated test file exists
- OpenCV host library setup (for other tests)
- `pnpm nx run mobile:test` — all host tests pass
- `pnpm nx run mobile:analyze` — clean
- Coverage floor: 70%
- Device gate: BDD integration test (skippable with `VERIFY_SKIP_DEVICE=1`)

## Deliverable (user-testable)

Two new toggle buttons in the review screen's AppBar: Auto (magic wand icon) and
Color (palette icon). Tap Auto → the saved scan has whitened background and
boosted contrast. Tap Color → subtle contrast lift while preserving natural color.
All four enhancement modes (Grayscale, B&W, Auto, Color) are mutually exclusive.

**You can test it by:**
1. Scan a document with a colored paper/background. Tap Auto — the saved scan
   should have a much whiter background.
2. Scan a color document (receipts, forms). Tap Color — the result should be
   slightly crisper and brighter than the original.
3. Tap Auto, then tap Grayscale — only Grayscale should activate.
4. Confirm Retake, Reset, crop overlay, and G1/G2 buttons work normally (no regression).

## Acceptance criteria

- [ ] `AutoEnhancer` in `lib/features/library/auto_enhancer.dart` — *static*
- [ ] `ColorEnhancer` in `lib/features/library/color_enhancer.dart` — *static*
- [ ] `AutoEnhancer` performs per-channel auto-levels + saturation boost,
      runs off the UI thread, bakes EXIF orientation — *unit*
- [ ] `ColorEnhancer` performs contrast + brightness lift,
      runs off the UI thread, bakes EXIF orientation — *unit*
- [ ] Both enhancers: corrupt/invalid JPEG → input unchanged, no throw — *unit*
- [ ] Auto toggle (`Key('auto-toggle')`) and Color toggle (`Key('color-toggle')`)
      in review screen AppBar — *widget*
- [ ] All five modes mutually exclusive (enum); tapping one deactivates others — *widget*
- [ ] Accept with Auto on → `AutoEnhancer`; Color on → `ColorEnhancer`; off → `NoneEnhancer` — *widget*
- [ ] G1/G2 toggle behavior unchanged — *widget: regression*
- [ ] Enhancement pipeline unchanged (`CameraScreen`, `SaveController`, `DriftDocumentRepository`) — *no code changes*
- [ ] BDD: Auto on → `AutoEnhancer` reaches repository — *integration*
- [ ] BDD: Color on → `ColorEnhancer` reaches repository — *integration*
- [ ] BDD: no toggle → `NoneEnhancer` reaches repository — *integration*
- [ ] All host tests pass; analyze clean; coverage ≥ 70% — *verify script*

---

> **Definition of Done gate:** Per `00-overview-roadmap.md`, this feature is
> not done until every acceptance criterion above maps to a passing test (TDD:
> unit/widget first; BDD for user-facing behavior), the full suite is run and
> observed green, quality gates pass, and the work is reviewed and
> double-checked. "Looks right" / "should pass" is not done.
