# I2 Gallery Import — Design Spec

**Date:** 2026-07-01
**Step:** I2 — Gallery import (Feature 01 / document scanning — the "import an existing photo" slice)
**Status:** Approved
**Depends on:** A2/A3 (camera + review), B1 (save), E-series (crop), G-series (filters), H1 (add page) — all gated
**Feeds:** completes Sub-project 1.

---

## Goal

Instead of capturing with the camera, the user can **import an existing photo from
the device gallery** and run it through the **same** review pipeline — auto-crop
prefill, manual crop, filter, accept → save. The imported page becomes a document
(or, when a scan session already has pages, appends to it), exactly like a captured
page.

Works on iOS and Android via the official `image_picker` plugin. Privacy posture is
unchanged: the picked photo is a local file; nothing leaves the device.

---

## Approach & boundary

The `CameraScreen` already owns the whole review-and-save pipeline (edge detector,
`SaveController`, `_onAccept` create/append). Gallery import **reuses that pipeline
verbatim** — a picked image is just a `CapturedImage(path)`, indistinguishable from
a captured one downstream. So I2 adds:

1. A **`GalleryPicker`** interface (DIP) with an `image_picker`-backed implementation
   and a fake — injected through `ScanDependencies`, mirroring the camera services.
2. An **import button** on the `CameraScreen` app bar that picks a photo and routes
   it into the existing review flow.

**Entry point decision (efficient + best UX):** the import button lives on the
**Scan/camera screen**, not the Home screen. This reuses the entire tested pipeline
with **zero duplication** — the review + create/append logic already lives here, and
placing a Home-level entry would require re-wiring that pipeline from Home. Import-in-
the-capture-screen is the established pattern in Adobe Scan / Microsoft Lens /
CamScanner. A Home-level shortcut can be added later without rework (it would just
launch this screen). Rejected: duplicating the review/save flow at Home (DRY
violation); a Home button that auto-opens the picker on a camera screen the user
didn't want (awkward on cancel).

---

## Architecture

| Layer | Change |
|---|---|
| `pubspec.yaml` | Add `image_picker` dependency |
| `ios/Runner/Info.plist` | Add `NSPhotoLibraryUsageDescription` (iOS photo-access rationale) |
| `gallery_picker.dart` (new) | `GalleryPicker` interface + `ImagePickerGalleryPicker` impl |
| `ScanDependencies` | Add `createGalleryPicker` factory (default = `ImagePickerGalleryPicker.new`) |
| `fake_scan.dart` (test support) | `FakeGalleryPicker`; wire into `grantedScanDependencies` (default fake) |
| `CameraScreen` | Hold `_galleryPicker`; extract `_reviewAndSave(image)` from `_onShutter`; add `_onImport`; add import app-bar button |

---

## Components

### `GalleryPicker` (new file `apps/mobile/lib/features/scan/gallery_picker.dart`)

```dart
import 'captured_image.dart';

/// Picks a single image from the device gallery. Injectable (DIP) so widget/BDD
/// tests use a fake instead of the platform picker.
abstract interface class GalleryPicker {
  /// Returns the picked image as a [CapturedImage], or null if the user cancelled.
  Future<CapturedImage?> pick();
}
```

```dart
import 'package:image_picker/image_picker.dart';
// ...
/// Production picker backed by image_picker. Reads a local photo; nothing leaves
/// the device.
class ImagePickerGalleryPicker implements GalleryPicker {
  const ImagePickerGalleryPicker();
  @override
  Future<CapturedImage?> pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    return x == null ? null : CapturedImage(x.path);
  }
}
```

> **Testability note:** `ImagePickerGalleryPicker` is a thin adapter over the
> platform picker; it cannot be driven by automated tests (the native gallery UI
> is out of Flutter's reach). Its two lines (null→null, XFile→CapturedImage) are
> verified by inspection; the **flow** is tested through the `GalleryPicker`
> interface with a fake. This matches how the camera preview controller is
> handled (`PluginCameraPreviewController` vs `FakeCameraPreviewController`).

### `ScanDependencies` addition

```dart
typedef GalleryPickerFactory = GalleryPicker Function();
GalleryPicker _defaultGalleryPicker() => const ImagePickerGalleryPicker();
// in the class:
final GalleryPickerFactory createGalleryPicker;
// in the const ctor:
this.createGalleryPicker = _defaultGalleryPicker,
```

### `FakeGalleryPicker` (test support, `fake_scan.dart`)

```dart
class FakeGalleryPicker implements GalleryPicker {
  final bool cancel;          // true => pick() returns null (user cancelled)
  const FakeGalleryPicker({this.cancel = false});
  @override
  Future<CapturedImage?> pick() async {
    if (cancel) return null;
    // Write bundled bytes to a temp file so the review + save pipeline has a real
    // file to read (mirrors FakeCameraPreviewController.capture()).
    final dir = await Directory.systemTemp.createTemp('fake_gallery');
    final file = File('${dir.path}/import.jpg')..writeAsBytesSync(kFakeJpegBytes);
    return CapturedImage(file.path);
  }
}
```

`grantedScanDependencies()` gains `createGalleryPicker: () => const FakeGalleryPicker()`
so every scan BDD (and the I2 BDD) runs with a hermetic picker. (Other scenarios
never tap import, so this is inert for them.)

### `CameraScreen` changes

- `late final GalleryPicker _galleryPicker;` initialised in `initState` from
  `widget.dependencies.createGalleryPicker()`.
- **Extract** the review-push block from `_onShutter` into
  `Future<void> _reviewAndSave(CapturedImage image)` (the `navigator.push(
  CaptureReviewScreen(... onAccept: _onAccept ...))`). `_onShutter` calls it after a
  successful capture (DRY — identical downstream behavior).
- **`_onImport`:**
  ```dart
  Future<void> _onImport() async {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    final image = await _galleryPicker.pick();
    if (!mounted) return;
    if (image == null) {
      // Cancelled — resume live sampling, stay on the camera.
      if (_controller.status == ScanStatus.ready) _startSampleTimer();
      return;
    }
    await _reviewAndSave(image);
    if (mounted && _controller.status == ScanStatus.ready) _startSampleTimer();
  }
  ```
- **App-bar import button** — always present (even before the first capture), so the
  actions list is:
  ```dart
  actions: [
    IconButton(
      key: const Key('camera-import'),
      icon: const Icon(Icons.photo_library_outlined),
      tooltip: 'Import from gallery',
      onPressed: _onImport,
    ),
    if (_pageCount > 0)
      IconButton(key: const Key('camera-done'), icon: const Icon(Icons.check),
          tooltip: 'Done scanning', onPressed: _onDone),
  ],
  ```
  (Replaces the current `_pageCount > 0 ? [done] : null`.)

The imported image flows through `CaptureReviewScreen` → `_onAccept`, which creates a
new document (first page) or appends (subsequent). No new save logic.

---

## Data flow

```
tap camera-import
  → _galleryPicker.pick()            (image_picker → gallery UI → XFile, or null)
      → null  → resume sampling, stay on camera
      → image → _reviewAndSave(image)
                  → push CaptureReviewScreen (auto-crop prefill, crop, filter)
                      → onAccept → _onAccept → SaveController.save/addPage
                          → scrubbed JPEG persisted as a document page
```

---

## Error handling

| Failure | Behavior |
|---|---|
| User cancels the picker | `pick()` → null → no-op; live sampling resumes; no error shown |
| `image_picker` throws (rare platform error) | `_onImport` wraps `pick()` in try/catch → SnackBar `Couldn't import photo` → resume sampling |
| Save fails after accept | existing `_onAccept` path → `Couldn't save document. Try again.` SnackBar |

(Add the try/catch around `pick()` in `_onImport`; the table above governs.)

---

## Testing (acceptance-criteria mapping)

I2 acceptance: *import a photo from the gallery and produce a document through the
same review/save pipeline; cancelling is a graceful no-op; on-device end-to-end.*

**Widget — `CameraScreen`** (`camera_screen_i2_test.dart`, fake deps):
- The app bar shows the import button (`camera-import`) even at `_pageCount == 0`.
- Tapping import with a `FakeGalleryPicker` (returns a file) → `CaptureReviewScreen`
  appears (`review-accept` present).
- Tapping import then Accept → a document is saved (fake repo `createCalls == 1`).
- Import with `FakeGalleryPicker(cancel: true)` → stays on the camera (no review
  screen pushed; `createCalls == 0`).
- Import that throws (a throwing fake picker) → `Couldn't import photo` SnackBar,
  stays on camera.

**BDD — `i2_gallery_import.feature`** → generated on-device test:
- *Given the app is launched…, when I tap the Scan button, and I import a photo from
  the gallery, and I tap Accept, and I tap Done, then I see a saved document on the
  home.* New step `i_import_a_photo_from_the_gallery` (tap `camera-import`); reuses
  `i_tap_accept`, `i_tap_done`, `i_see_a_saved_document_on_the_home`. The BDD runs
  with the **fake** picker (via `grantedScanDependencies`) — the real native picker
  is untestable by automation; the fake supplies a real temp file so the whole
  review→save→home flow is exercised on device.

**Verify harness — `scripts/verify/i2.sh`** (mirrors `i1.sh`): static asserts
(`GalleryPicker` + `ImagePickerGalleryPicker` in `gallery_picker.dart`,
`createGalleryPicker` in `ScanDependencies`, `camera-import` + `_onImport` in
`CameraScreen`, `image_picker` in `pubspec.yaml`, feature + generated test), host
suite green, analyze clean, on-device BDD.

---

## Platform config

- **iOS:** `ios/Runner/Info.plist` gains `NSPhotoLibraryUsageDescription` = a short
  rationale (e.g. "Import a document photo from your library."). Required or iOS
  crashes on `pickImage`.
- **Android:** `image_picker` 1.x uses the system **Photo Picker**, which needs no
  runtime storage permission or manifest change. No `android/build.gradle.kts` edit.
- The dependency addition regenerates `pubspec.lock` (committed). `ios/Podfile.lock`
  is only touched by an iOS pod install (not run here) — it is NOT modified or staged
  by this work; the Android on-device verification is authoritative for this repo's
  device.

---

## Out of Scope (YAGNI)

- Multi-select import (pick several photos at once) — one photo per import.
- Importing PDFs or non-image files.
- A Home-screen import shortcut (can be added later; reuses this screen).
- Editing the picked file's format — it flows through the same scrub/save as a capture.
