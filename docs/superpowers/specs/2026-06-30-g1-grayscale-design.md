# G1 Grayscale Filter — Implementation Design

**Date:** 2026-06-30
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** E2 (perspective flatten, `ImageWarper`/`PerspectiveWarper`), F2 (`ScanDependencies`)
**Feeds:** G2 (B&W), G3 (Color/Auto), G4 (filter picker UI)
**Step in roadmap:** G1 — grayscale filter (first of G. Enhancement series)

## Purpose

Let users apply a grayscale filter to their scanned page before saving. Adds an
`ImageEnhancer` DIP interface and a `GrayscaleEnhancer` strategy — the clean
seam that G2 (B&W), G3 (Color/Auto), and G4 (picker UI) extend without
modifying existing code. A toggle in the review screen's AppBar gives immediate
user control. The filter is baked into the saved JPEG at accept time; non-destructive
re-selection (re-deriving from the flat cache) is deferred to G4 when the full
picker and DB storage arrive together.

## Scope

**In scope:**
- `ImageEnhancer` interface + `NoneEnhancer` (pass-through)
- `GrayscaleEnhancer` using the `image` package (already a dep), run in a `compute()` isolate
- Grayscale on/off toggle button in `CaptureReviewScreen`'s AppBar actions
- Threading the chosen enhancer through `onAccept` → `SaveController` → `DocumentRepository` → `DriftDocumentRepository`
- Enhancement applied whether or not the image was cropped (full-frame or warped)

**Out of scope:**
- DB column for enhancement mode (G4)
- Non-destructive re-selection after save (G4)
- Live grayscale preview in the review screen (G4)
- B&W, Color, Auto/Magic filters (G2, G3)
- Filter picker UI (G4)

## Architecture

### New: `lib/features/library/image_enhancer.dart`

DIP boundary for image enhancement, parallel to `ImageWarper`:

```dart
abstract interface class ImageEnhancer {
  /// Returns enhanced JPEG bytes. Never throws — on any error returns [bytes] unchanged.
  Future<Uint8List> enhance(Uint8List bytes);
}

/// Pass-through: returns bytes unchanged. Used when no filter is selected.
class NoneEnhancer implements ImageEnhancer {
  const NoneEnhancer();
  @override
  Future<Uint8List> enhance(Uint8List bytes) async => bytes;
}
```

### New: `lib/features/library/grayscale_enhancer.dart`

Strategy for grayscale conversion. Uses `image` 4.9.1 (already a dep via
`PerspectiveWarper`). Runs in a `compute()` isolate — never blocks the UI thread.
Always bakes EXIF orientation before converting, so the stored JPEG is always
upright (the EXIF scrubber keeps the Orientation tag; `img.encodeJpg` strips
EXIF, so orientation must be baked first):

```dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'image_enhancer.dart';

class GrayscaleEnhancer implements ImageEnhancer {
  const GrayscaleEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_grayscaleFn, bytes);
}

Uint8List _grayscaleFn(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final oriented = img.bakeOrientation(decoded);  // positional arg — same API as PerspectiveWarper
  img.grayscale(oriented);                        // positional arg, mutates in place
  return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
}
```

`img.grayscale(src)` uses luminance-weighted conversion (`getLuminanceRgb`) and
mutates `src` in place, returning it. Quality 92 matches `PerspectiveWarper`.

Each future filter (G2 B&W, G3 Color/Auto) is a new class — `ImageEnhancer`
and `GrayscaleEnhancer` are never modified (OCP).

## Modified components

### `lib/features/scan/capture_review_screen.dart`

**`onAccept` type change** — carries both corners and the chosen enhancer:

```dart
// Before:
final ValueChanged<CropCorners> onAccept;

// After:
final void Function(CropCorners corners, ImageEnhancer enhancer) onAccept;
```

**New state field:**
```dart
bool _grayscale = false;
```

**New AppBar action** — a toggle icon button:
```dart
AppBar(
  title: const Text('Review'),
  actions: [
    IconButton(
      key: const Key('grayscale-toggle'),
      icon: Icon(_grayscale ? Icons.filter_b_and_w : Icons.filter_b_and_w_outlined),
      tooltip: _grayscale ? 'Grayscale on' : 'Grayscale off',
      onPressed: () => setState(() => _grayscale = !_grayscale),
    ),
  ],
)
```

**Accept wires the chosen enhancer:**
```dart
FilledButton.icon(
  key: const Key('review-accept'),
  onPressed: widget.saving
      ? null
      : () => widget.onAccept(
            _corners,
            _grayscale ? const GrayscaleEnhancer() : const NoneEnhancer(),
          ),
  ...
)
```

No live preview — the toggle state is visible via the button icon; the user sees
the grayscale result after the document is saved and opened.

### `lib/features/scan/camera_screen.dart`

`_onAccept` grows an `ImageEnhancer` parameter and threads it to `SaveController`:

```dart
Future<void> _onAccept(
    CapturedImage image, CropCorners corners, ImageEnhancer enhancer) async {
  final doc = await _saveController.save(image, corners: corners, enhancer: enhancer);
  ...
}
```

The `onAccept` lambda in `navigator.push`:
```dart
onAccept: (corners, enhancer) => _onAccept(image, corners, enhancer),
```

### `lib/features/library/save_controller.dart`

`save()` gains an `enhancer` parameter (defaults to `NoneEnhancer` so all existing
callers compile without change):

```dart
Future<Document?> save(
  CapturedImage image, {
  CropCorners corners = CropCorners.fullFrame,
  ImageEnhancer enhancer = const NoneEnhancer(),
}) async {
  ...
  final doc = await _repository.createFromCapture(image,
      corners: corners, enhancer: enhancer);
  ...
}
```

### `lib/features/library/document_repository.dart`

Interface gains optional `enhancer` parameter:

```dart
Future<Document> createFromCapture(
  CapturedImage capture, {
  CropCorners? corners,
  ImageEnhancer? enhancer,
});
```

### `lib/features/library/drift/drift_document_repository.dart`

Enhancement is applied **after the warp**, baked into the bytes written to disk:

```dart
// After the warp block:
Uint8List? flatBytes = flat; // null when corners == fullFrame
Uint8List originalBytes = scrubbed;

if (enhancer != null) {
  if (flatBytes != null) {
    // Cropped path: enhance the flat (orientation already baked by warper).
    try { flatBytes = await enhancer.enhance(flatBytes); } catch (_) {}
  } else {
    // Full-frame path: enhance the original (bakeOrientation runs inside GrayscaleEnhancer).
    try { originalBytes = await enhancer.enhance(originalBytes); } catch (_) {}
  }
}
```

When enhancement fails it falls through silently (same policy as warp failure) —
the save proceeds with unenhanced bytes.

`LibraryDependencies` is unchanged — the enhancer is a per-call parameter, not a
constructor dependency of `DriftDocumentRepository`.

### `test/support/fake_library.dart`

`FakeDocumentRepository.createFromCapture` gains `ImageEnhancer? enhancer` and
records it for test assertions:

```dart
ImageEnhancer? lastSavedEnhancer;

@override
Future<Document> createFromCapture(CapturedImage capture,
    {CropCorners? corners, ImageEnhancer? enhancer}) async {
  createCalls++;
  lastSavedCorners = corners;
  lastSavedEnhancer = enhancer;
  ...
}
```

All existing `CaptureReviewScreen` tests that pass `onAccept: (corners) => ...`
must be updated to `onAccept: (corners, enhancer) => ...` (mechanical fix).

## Data flow

```
User taps grayscale toggle (review screen)
  → _grayscale = true/false

User taps Accept
  → widget.onAccept(_corners, GrayscaleEnhancer() | NoneEnhancer())
  → CameraScreen._onAccept(image, corners, enhancer)
  → SaveController.save(image, corners: corners, enhancer: enhancer)
  → DriftDocumentRepository.createFromCapture(image, corners: corners, enhancer: enhancer)
    → scrub raw bytes → warp (if corners != fullFrame)
    → enhancer.enhance(flatBytes ?? scrubbed) [compute isolate]
    → write enhanced bytes to disk
    → insert document + page rows
```

## BDD scenarios

**Feature file:** `integration_test/g1_grayscale.feature`
**Generated test:** `integration_test/g1_grayscale_test.dart` (build_runner)
**Step defs:** `test/step/`

```gherkin
Feature: G1 grayscale scan enhancement

  Scenario: Grayscale filter applied — document saved with enhancement
    Given the review screen is open with a captured image
    When I toggle the grayscale filter
    And I accept the review
    Then the document is saved with grayscale enhancement

  Scenario: No filter — document saved without enhancement
    Given the review screen is open with a captured image
    When I accept the review without toggling grayscale
    Then the document is saved without enhancement
```

Step definitions (new files in `test/step/`):
- `the_review_screen_is_open_with_a_captured_image.dart` — pumps `CameraScreen` with `FakeDocumentRepository`; shutter fires; review screen appears
- `i_toggle_the_grayscale_filter.dart` — `tester.tap(find.byKey(Key('grayscale-toggle')))`
- `i_accept_the_review.dart` — `tester.tap(find.byKey(Key('review-accept')))`
- `i_accept_the_review_without_toggling_grayscale.dart` — direct tap on accept, no toggle
- `the_document_is_saved_with_grayscale_enhancement.dart` — asserts `fakeRepo.lastSavedEnhancer is GrayscaleEnhancer`
- `the_document_is_saved_without_enhancement.dart` — asserts `fakeRepo.lastSavedEnhancer is NoneEnhancer || fakeRepo.lastSavedEnhancer == null`

## Testing strategy

| Layer | What is tested |
|-------|----------------|
| Unit: `GrayscaleEnhancer` | Output pixels satisfy R == G == B (luminance-weighted); `NoneEnhancer` returns the same bytes reference |
| Unit: `GrayscaleEnhancer` | Null-safe decode: invalid bytes return input unchanged, no throw |
| Unit: `GrayscaleEnhancer` | Orientation is baked: a known rotated JPEG produces an upright grayscale result |
| Widget: `CaptureReviewScreen` | Grayscale toggle button present; tapping toggles icon state |
| Widget: `CaptureReviewScreen` | Accept with toggle on → `onAccept` called with `GrayscaleEnhancer` |
| Widget: `CaptureReviewScreen` | Accept with toggle off → `onAccept` called with `NoneEnhancer` |
| Widget: `CaptureReviewScreen` | Saving state disables accept button (regression) |
| Widget: `CameraScreen` | Save flow threads `GrayscaleEnhancer` to `FakeDocumentRepository` after toggle |
| BDD | Both scenarios above |
| Static | `ImageEnhancer` file exists; `GrayscaleEnhancer` file exists; `Key('grayscale-toggle')` present |

## Verify script

`scripts/verify/g1.sh` — follows `lib.sh` pattern:
- Static assertions (file presence, key, interface, `bakeOrientation` call in enhancer)
- OpenCV host library setup (shared test suite includes OpenCV-backed scan tests)
- `pnpm nx run mobile:test` — all host tests pass
- `pnpm nx run mobile:analyze` — clean
- Coverage floor: 70%
- Device gate: BDD integration test (skippable with `VERIFY_SKIP_DEVICE=1`)

## Deliverable (user-testable)

A grayscale toggle button in the review screen's AppBar. Tap it to turn on
grayscale, then Accept — the saved document page is grayscale.

**You can test it by:**
1. Scan a document with color content. On the review screen, tap the filter
   icon in the top-right to enable grayscale (icon fills). Tap Accept — the
   saved page should be grayscale when viewed in the library.
2. Repeat without tapping the toggle — the saved page keeps its original colors.
3. Confirm the crop overlay, Retake, and Reset buttons work normally (no regression).

## Acceptance criteria

- [ ] `ImageEnhancer` interface and `NoneEnhancer` exist in `lib/features/library/image_enhancer.dart` — *static*
- [ ] `GrayscaleEnhancer` converts pixels to luminance-weighted grayscale, runs off the UI thread, bakes EXIF orientation — *unit*
- [ ] Invalid/corrupt JPEG bytes return input unchanged, no throw — *unit*
- [ ] Grayscale toggle button (`Key('grayscale-toggle')`) appears in review screen AppBar — *widget*
- [ ] Accept with toggle on passes `GrayscaleEnhancer` to `onAccept`; off passes `NoneEnhancer` — *widget*
- [ ] Enhancement is applied in `DriftDocumentRepository` after the warp, for both cropped and full-frame captures — *unit: `drift_document_repository_test`*
- [ ] Enhancement failure is silent — save proceeds with unenhanced bytes — *unit*
- [ ] Existing tests unbroken: review screen Retake/Reset/crop workflow unchanged — *widget: regression*
- [ ] BDD: grayscale on → `GrayscaleEnhancer` reaches repository — *integration*
- [ ] BDD: grayscale off → `NoneEnhancer` reaches repository — *integration*
- [ ] All host tests pass; analyze clean; coverage ≥ 70% — *verify script*

---

> **Definition of Done gate:** Per `00-overview-roadmap.md`, this feature is
> not done until every acceptance criterion above maps to a passing test (TDD:
> unit/widget first; BDD for user-facing behavior), the full suite is run and
> observed green, quality gates pass, and the work is reviewed and
> double-checked. "Looks right" / "should pass" is not done.
