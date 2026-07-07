# Platform Document Scanner — Design

Date: 2026-07-07
Status: Approved (pending spec review)
Branch: `feat/platform-document-scanner`

## Problem

The custom OpenCV live/still edge detector cannot reliably isolate a white page
from a similarly-bright background. Measured on a real capture (white sheet on
light wood, warm light): the desk is in places **brighter** than the paper
(desk V≈167 vs paper 105–148), saturation overlaps, and the page border nearly
vanishes in a Canny edge map. No single classical cue (luminance / colour /
edges) separates page from desk, so the detected quad balloons past the paper
(into the desk or the backlit keyboard). This is an architectural ceiling of the
single-cue classical approach, not a tunable constant.

## Decision

Replace the custom camera + OpenCV **live and capture** detection with the OS
document scanners via the `cunning_document_scanner` plugin
(Android → Google ML Kit DocumentScanner, iOS → Apple VisionKit). These are
trained detectors that handle low-contrast scenes and return already-cropped,
perspective-corrected page images.

### Approved choices

1. **Fully replace the custom camera.** Tapping *Scan* launches the OS scanner.
   The custom camera screen, live preview/overlay, auto-capture, and the OpenCV
   **live** detection path are removed.
2. **Keep the app's filter step**, applied to the scanner output — but **one
   filter for the whole batch**: after scanning, a single review screen (no crop
   UI, since pages are already cropped) picks a filter that is applied to every
   page in the batch, then all pages are saved.
3. **Gallery import stays unchanged** — `image_picker` → the existing
   crop+filter review (which still uses the OpenCV **still** `detect()` to seed
   crop corners) → save.
4. **Plugin:** `cunning_document_scanner` (v2.5.0+), image output (not PDF).
5. **Remove now-unused deps** (`camera`, and `permission_handler` if nothing
   else uses it) after the switch, gated on a grep confirming no other users.

## Architecture

Feature-first, following the existing `ScanDependencies` composition-root
pattern (const-constructible factory typedefs; production defaults; tests inject
fakes).

### New seam: `DocumentScannerService`

```dart
abstract interface class DocumentScannerService {
  /// Launches the OS document scanner. Returns the scanned page images in
  /// order, or an empty list if the user cancelled. Never throws — all
  /// failures resolve to an empty list.
  Future<List<CapturedImage>> scan({int? pageLimit});
}
```

- Default impl `CunningDocumentScannerService` wraps
  `CunningDocumentScanner.getPictures(noOfPages: pageLimit ?? 100, ...)`,
  maps the returned file paths to `CapturedImage`, and maps null/empty/errors
  to `[]`. `pageLimit` is honoured on Android (`noOfPages`); iOS VisionKit is
  inherently multi-page and ignores it (documented plugin limitation). The
  batch flow passes `pageLimit: null` (→ 100, effectively "no practical cap");
  retake passes `pageLimit: 1`.
- Wired into `ScanDependencies` as `createDocumentScanner`.

### `ScanDependencies` changes

- **Add:** `createDocumentScanner` (default `CunningDocumentScannerService`).
- **Keep:** `createEdgeDetector` (still `OpenCvEdgeDetector`; only `detect()` is
  used, for the gallery review) and `createGalleryPicker`.
- **Remove:** `createPreviewController`, `createPermissionService` (the plugin
  manages camera permission itself).

### New scan flow: `ScanScreen` (replaces `CameraScreen`)

A thin coordinator screen (pushed by home's *Scan* action, and by the viewer's
retake action):

1. On open, show a minimal "Opening scanner…" scaffold and call
   `scannerService.scan()` (batch, no limit) — or `scan(pageLimit: 1)` in
   retake mode.
2. **Cancelled / empty** → pop back to the caller (net effect: *Scan* opened the
   OS scanner, cancel returns home).
3. **Pages returned** → push **one** `CaptureReviewScreen` in filter-only mode
   on the first page to pick a filter, then save **every** page in the batch
   with that filter: the first page creates the document, the rest append
   (reusing the existing create/append save logic). Then pop to home.
4. **Retake mode** (viewer passes an `onCapture` callback): call
   `scan(pageLimit: 1)`, take the first page, filter review, then invoke the
   existing `onCapture(image, corners, enhancer)` replace-page callback.

Navigation contracts to home (`_openScan` → refresh) and viewer (retake
`onCapture`) are preserved so those callers change minimally (only the pushed
screen type).

### `CaptureReviewScreen`: filter-only mode

Add `bool enableCrop` (default `true`).

- `enableCrop: true` (gallery import) — unchanged: run `detect()`, show the crop
  overlay + filter strip.
- `enableCrop: false` (scanner batch) — skip `detect()`, hide the crop overlay,
  use full-frame corners, show only the filter strip + accept/retake. The chosen
  enhancer is returned to the coordinator to apply to the whole batch.

### Save / OCR / PDF / library — unchanged

Each scanner page → `CapturedImage(path)` + full-frame corners + the batch
enhancer → existing `SaveController.save`/`addPage` → repository (already handles
the full-frame + enhancer case: applies the enhancer, stores the derivative).
OCR (ML Kit) and PDF/library flows are untouched.

## Removals (dead code after the switch)

Confined to `lib/features/scan/` and its tests; dependency grep confirmed each is
reachable only through the camera flow:

- `camera_screen.dart`, `scan_controller.dart`
- `camera_preview_controller.dart`, `camera_preview_controller_impl.dart`
- `camera_permission_service.dart`, `camera_permission_service_impl.dart`
- `widgets/camera_preview_view.dart`, `widgets/live_quad_overlay.dart`
- `auto_capture_controller.dart`
- `frame_reducer.dart`, `gray_frame.dart`, `camera_frame.dart`
- `detectFrame()` from `edge_detector.dart` + `opencv_edge_detector.dart`
  (`_segmentGrayFrame`, live path). `detect()` (still) is kept.
- Corresponding host tests and integration/`.feature` tests: live overlay (f3),
  auto-capture, camera permission (a2). Kept: still-`detect()` tests, review,
  save (b1), OCR, library, gallery import (i2), grayscale/colour filter (g1/g3).
- `pubspec.yaml`: remove `camera`, and `permission_handler` if unused elsewhere
  (grep-gated).

## Platform configuration

- **iOS:** deployment target 15.5 already ≥ 13; `NSCameraUsageDescription`
  already present. Optionally add `CFBundleAllowMixedLocalizations` for the
  localized scanner UI (nice-to-have, not required).
- **Android:** minSdk inherits Flutter's default (≥ 21, already required by ML
  Kit OCR). Add the plugin dep; verify the build resolves the ML Kit
  DocumentScanner artifact. No manifest change expected (the scanner runs in a
  Play-services-hosted activity).

## Testing

TDD/BDD per CLAUDE.md.

- **Host (widget) tests** with a **fake** `DocumentScannerService` injected via
  `ScanDependencies`:
  - cancel/empty → `ScanScreen` pops without creating a document;
  - N pages → one filter review → N pages saved (first creates the document,
    rest append), correct page count;
  - retake mode → single page → `onCapture` invoked with the review's enhancer;
  - `CaptureReviewScreen(enableCrop: false)` → no crop overlay, filter strip
    present, accept returns full-frame corners + chosen enhancer.
- **Device tests (real Android AND real iOS)** — the native scanner UI is not
  host-testable. Verify end-to-end: launch, live auto-detect, crop adjust,
  multi-page, cancel, and that saved pages land in the library with OCR. This is
  a **required, named** device-verification gap that must be closed before the
  change is "done" (not silently skipped).
- **BDD:** add/adjust `.feature`s for the new flow (scan → filter → save; cancel
  returns home; multi-page batch). Remove obsolete live-overlay / auto-capture /
  permission features.
- **Lint/format:** `flutter analyze` zero-warning bar; match existing file style
  (avoid blanket `dart format`, which drifts against the repo's formatter
  version).

## Out of scope

- On-device ML/U-Net custom detector.
- Changing OCR, PDF export, or library storage.
- Routing gallery import through the scanner (kept on `image_picker`).
- Per-page filter selection within a batch (one filter per batch by decision).

## Risks / open items

- **Plugin cancel semantics:** confirm `getPictures()` returns null vs `[]` vs
  throws on cancel; the wrapper normalizes all three to `[]`.
- **iOS pre-enhanced output:** VisionKit applies its own scan filter to returned
  images; our filter runs on top. Acceptable; verify legibility on device.
- **Android permission/manifest:** confirm on-device that no explicit `CAMERA`
  manifest permission or `permission_handler` app-dep is needed once the custom
  flow is gone (gates the dep removal).
- **Dep removal safety:** only remove `camera`/`permission_handler` after grep +
  a clean build on both platforms.
</content>
</invoke>
