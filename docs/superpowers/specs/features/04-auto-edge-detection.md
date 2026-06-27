# Feature 04 — Auto Edge Detection

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** Feature 01 (capture); feeds Feature 03 (crop) with initial corners
**Resolves:** the imaging-backend choice for Features 03/04/05

## Purpose

Automatically find the document's four corners in a captured image so the crop
screen (Feature 03) opens with corners already placed, and so auto-capture
(Feature 01) can trigger on a steady, confidently-detected document.

## Imaging backend (decision)

- **OpenCV** is the shared imaging backend ("scanning brain") for edge detection
  (04), perspective warp (03), and enhancement filters (05) — DRY.
- Accessed behind small interfaces (`EdgeDetector`, `ImageWarper`,
  `ImageEnhancer`) so the UI/feature logic never call OpenCV directly (DIP); the
  engine can be swapped later (ML model / commercial SDK) without UI changes.
- Native (C++) library: adds app size; all processing runs **off the UI thread**
  (isolate) to keep the app smooth.

## Scope

**In scope**
- Detect the document quad in a still image → corners + confidence, or none.
- Pre-fill Feature 03's crop corners from detection.
- (Stretch) live edge overlay in the camera preview.

**Out of scope**
- The perspective warp (Feature 03). Filters/enhancement (Feature 05).

## Detection pipeline

grayscale → blur → Canny edge detection → contour finding → select the largest
**convex 4-point** quad → compute a **confidence score**. Output:
`{ corners[4], confidence }` or `none`.

## Behavior (accepted)

- **None / low confidence** → crop screen opens with corners defaulted to the
  **full image**; user adjusts manually. Never blocks, never errors.
- **Auto-capture link** → fires only when confidence ≥ threshold **and** the
  frame is steady.
- **Visual cue** → detected outline turns **green** when confident, neutral
  otherwise.

## Build order

- **F1** detect on a still image → **F2** pre-fill crop corners → **F3** live
  overlay in preview (stretch; throttled — process a subset of frames to stay
  smooth).

## Testing strategy (TDD/BDD first)

- **Unit:** largest-convex-4-point selection; confidence scoring; "none found"
  on blank/low-contrast fixtures.
- **Widget:** crop pre-fills from detected corners; green cue toggles with
  confidence.
- **BDD scenarios:**
  - *Given a document on a contrasting background, when I capture it, then the
    crop screen opens with corners pre-filled near the document edges.*
  - *Given a low-contrast/cluttered photo with no clear document, when I capture
    it, then the crop screen opens on the full image with no error.*
  - *Given auto-capture is on and a steady, confidently-detected document, then a
    capture fires automatically; given low confidence, then it does not.*

## Acceptance criteria

1. Detection returns corners + confidence, or "none," for a still image.
2. High-confidence detection pre-fills the crop corners; low/none defaults to the
   full image with no error.
3. Auto-capture fires only above the confidence + stability threshold.
4. Detection runs off the UI thread; UI stays responsive.
5. Engine is accessed via the `EdgeDetector` interface (swappable).
6. All logic test-first; BDD scenarios pass.
