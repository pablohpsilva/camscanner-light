# Strict single-shot ID capture — design

**Date:** 2026-07-09
**Status:** Approved for planning
**Feature area:** `lib/features/scan/` (ID scan flow + in-document page retake)

## Problem

The ID scan feature (front side, then back side) currently hands each side to the
**native OS document scanner** (`cunning_document_scanner`, wrapping Android ML Kit /
iOS VisionKit). The user wants strict, one-photo-per-side capture: after taking a
picture, if they don't want to retake it, the flow should **automatically advance** to
the next step — no "keep snapping until Save".

### Root cause (why this isn't just a setting)

- **Android (ML Kit):** honors a page limit; the ID flow already passes `pageLimit: 1`,
  so Android is effectively one-shot with an OS review/retake screen.
- **iOS (VisionKit):** `VNDocumentCameraViewController` has **no page-limit API**. It is
  inherently multi-page — the user keeps scanning and taps "Save". Flutter cannot
  constrain it. The app's own code documents this: *"honoured on Android; iOS VisionKit
  is inherently multi-page and ignores it."*

To enforce one-shot on **both** platforms we must stop routing ID capture through the OS
scanner and capture a single photo ourselves. A self-captured photo is not auto-cropped
by the OS, so we re-add cropping using the app's **existing OpenCV edge detector**.

## Scope

**In scope**
1. New single-shot camera seam (`PhotoCamera`) backed by `image_picker`'s camera.
2. Rewrite `IdScanScreen` as a per-side capture → review (Retake/Accept) → auto-advance loop.
3. Switch the **in-document "Retake page"** path (`ScanScreen` retake branch, invoked from
   `page_viewer_screen.dart:_retakePage`) to the same single-shot camera + crop-enabled review.
4. Small non-breaking additions to `CaptureReviewScreen` (`title`, `acceptLabel`, `initialMode`).

**Out of scope**
- The home "Scan" **batch** document flow keeps using the OS multi-page scanner — multi-page
  is the correct behavior there.
- No changes to persistence (`SaveController`, `DocumentRepository`), PDF export, or the ID-card
  layout marking.

## Decisions (confirmed with user)

- **Capture UX:** capture one photo → in-app preview with **Retake / Accept** → on Accept,
  auto-advance to the next step.
- **Cropping:** auto-crop via the existing `EdgeDetector`; fall back to full frame when
  detection fails (mirrors `CaptureReviewScreen`'s current detect-or-fullFrame behavior).
- **Both platforms:** identical self-capture flow on Android and iOS.
- **ID filter default:** `None` (matches today's raw ID output), but the Auto/Color/Grayscale/None
  filter strip remains available in the preview.
- **In-document retake:** also switched to single-shot (broader than ID alone, by user request).

## Design

### 1. `PhotoCamera` seam — `lib/features/scan/photo_camera.dart`

Mirrors the existing `GalleryPicker` (`gallery_picker.dart`): a DIP boundary so widget/BDD
tests inject a fake instead of the native camera UI.

```dart
abstract interface class PhotoCamera {
  /// Captures a single photo from the device camera. Returns the photo as a
  /// [CapturedImage], or null if the user cancelled. Never throws.
  Future<CapturedImage?> capture();
}

class ImagePickerPhotoCamera implements PhotoCamera {
  const ImagePickerPhotoCamera();
  @override
  Future<CapturedImage?> capture() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera);
    return x == null ? null : CapturedImage(x.path);
  }
}
```

Wire a `PhotoCameraFactory` + `createPhotoCamera` (default `ImagePickerPhotoCamera`) into
`ScanDependencies`, exactly like `createGalleryPicker`. Const-constructible.

`ImagePickerPhotoCamera` is a thin adapter over native UI → not host-testable (same
documented limitation as `ImagePickerGalleryPicker`); the flow is tested through the
`PhotoCamera` interface with a fake.

### 2. `CaptureReviewScreen` — three optional, non-breaking params

Add to the widget (all defaulted so existing callers are untouched):

- `String title = 'Review'` → ID flow passes `'Front of ID'` / `'Back of ID'`.
- `String acceptLabel = 'Accept'` → ID flow passes `'Use'` (or `'Next'`).
- `EnhancerMode initialMode = EnhancerMode.auto` → ID flow passes `EnhancerMode.none`;
  replaces the hard-coded `_mode = EnhancerMode.auto` initializer.

No other changes — the screen already supports `enableCrop: true` + `edgeDetector` (auto-detect
+ crop overlay) and returns `(corners, enhancer)` via `onAccept`.

### 3. `IdScanScreen` rewrite — per-side capture→review loop

State: a `_camera` (from `dependencies.createPhotoCamera()`), a `_detector`
(`dependencies.createEdgeDetector()`), the `SaveController`, and a `_Step`
(`front` / `back` / `saving`) for the status label.

Per-side helper (pseudocode):

```dart
/// Captures one side: single photo → review. Returns the accepted result,
/// or null if the user cancelled (camera-cancel or system-back on review).
Future<_SideResult?> _captureSide(String title) async {
  while (true) {
    final photo = await _camera.capture();
    if (photo == null) return null;                 // cancelled camera → abort ID
    final outcome = await _review(photo, title);    // pushes CaptureReviewScreen
    switch (outcome) {
      case _Accepted(:final corners, :final enhancer):
        return _SideResult(photo, corners, enhancer);
      case _Retake():
        continue;                                    // re-capture the same side
      case null:                                     // system back → abort ID
        return null;
    }
  }
}
```

`_review` pushes `CaptureReviewScreen(image: photo, enableCrop: true,
edgeDetector: _detector, initialMode: EnhancerMode.none, title: title,
acceptLabel: 'Use', onRetake: () => pop(_Retake()), onAccept: (c, e) => pop(_Accepted(c, e)))`
and awaits the popped outcome (null when the user presses the AppBar back).

Main flow (mirrors today's `_run`, save logic unchanged):

```dart
final front = await _captureSide('Front of ID');
if (front == null) { navigator.pop(); return; }
final back = await _captureSide('Back of ID');
if (back == null) { navigator.pop(); return; }
setState(() => _step = _Step.saving);
final doc = await _saveController.save(front.image,
    corners: front.corners, enhancer: front.enhancer);
// ... existing null-handling + snackbars unchanged ...
final pos = await _saveController.addPage(back.image, doc.id,
    corners: back.corners, enhancer: back.enhancer);
// ... existing null-handling unchanged ...
await widget.repository.markAsIdCard(doc.id);   // best-effort, as today
navigator.pop();
```

Net behavior: exactly one photo per side, auto-cropped, one tap (Accept) advances, Retake
re-captures — identical on Android and iOS.

### 4. `ScanScreen` retake branch → single-shot

In `ScanScreen._run`, the `retake` branch (`widget.onCapture != null`) currently calls
`_scanner.scan(pageLimit: 1)` then a filter-only review (`enableCrop: false`, `fullFrame`).
Change it to:

1. `final photo = await _camera.capture();` (new `PhotoCamera` from deps). `null` → pop.
2. Review with `enableCrop: true` + `edgeDetector` (so the retaken page is cropped) + filters.
3. `await widget.onCapture!(photo, corners, enhancer)` with the reviewed corners/enhancer
   (instead of `fullFrame`).

The **non-retake** branch (batch scan) is untouched — still the OS scanner.

## Data flow

`PhotoCamera.capture()` → `CapturedImage(path)` → `CaptureReviewScreen` (decode size, run
`EdgeDetector.detect(bytes)` → corners+confidence, user may adjust/retake, pick filter) →
`onAccept(corners, enhancer)` → `SaveController.save` / `.addPage` / `replacePage` (existing
warp+enhance persistence pipeline).

## Error handling

- Camera cancelled (`null`) → abort that flow, pop, no partial document.
- Edge detection fails/throws → `CaptureReviewScreen` already falls back to `fullFrame`
  (blue highlight); the user can still crop manually or accept full-frame.
- Save/addPage failure → existing snackbars + pop paths preserved verbatim.
- `markAsIdCard` failure → non-fatal (doc saved with default layout), as today.

## Testing (TDD + BDD, both platforms — per CLAUDE.md)

### Host (TDD widget tests) — write failing first
`test/features/scan/id_scan_screen_test.dart` (updated) with injected fakes
(`FakePhotoCamera` returning front then back, fake `EdgeDetector`, `FakeDocumentRepository`):
- **Happy path:** accept front, accept back → `createCalls == 1`, `addPageCalls == 1`,
  `markIdCardCalls == 1`, and **`camera.captureCount == 2`** (exactly one photo per side).
- **Retake:** front review returns Retake once, then Accept → `camera.captureCount == 3`,
  and only the retaken front is saved (still 1 create / 1 addPage).
- **Cancel front:** camera returns null → no create/addPage, screen pops.
- **initialMode:** ID review starts in `None`.

New `test/support/fake_scan.dart` addition: `FakePhotoCamera` (sequential single shots +
`captureCount`).

`ScanScreen` retake test (`test/features/scan/scan_screen_*_test.dart`): retake branch now
calls the camera (not the scanner) and passes reviewed (non-fullFrame) corners to `onCapture`.

### BDD
`integration_test/id_scan.feature` (updated):
- Existing scenario re-backed by a **fake camera** (not fake scanner):
  *"Scanning front and back saves a 2-page ID document."*
- New scenario: *"Retaking the front then saving keeps two pages."*
- Regenerate `id_scan_test.dart` + steps via `build_runner`. Update the step
  `the_app_is_launched_with_a_fake_id_scanner...` → a fake-camera equivalent.

### Device (named gap, not silent)
The native camera UI cannot be driven by `integration_test` (same inherent limit as
`ImagePickerGalleryPicker`). Therefore:
- Seam + flow proven host-side with fakes (above).
- **Manual on-device verification on a real Android device AND a real iOS device:** one photo
  per side, preview shows auto-cropped card, Accept advances, Retake re-captures, 2-page ID
  saved and marked as ID card; in-document page retake likewise single-shot. Exact commands +
  observations reported before claiming done.

## Non-goals / risks

- Camera permission strings already present (`ios/Runner/Info.plist:NSCameraUsageDescription`,
  Android `CAMERA`) — no manifest change.
- `DocumentScannerService` and `cunning_document_scanner` remain (batch scan). The ID flow's
  old `FakeSequentialDocumentScannerService` usage is replaced by `FakePhotoCamera`.
- Risk: edge detection on a hand-held ID photo may be less reliable than VisionKit's crop.
  Mitigated by the manual crop overlay + full-frame fallback already in `CaptureReviewScreen`.
