# Store Listing Screenshots — Design Spec

**Date:** 2026-07-08
**Branch:** `feat/store-screenshots`
**Goal:** Produce an appealing, on-brand collection of App Store / Play Store
listing screenshots (the images a user swipes through when downloading the app)
for four device classes: iOS iPhone, iOS iPad, Android phone, Android tablet.

## Deliverable

**24 images** = 4 device classes × 6 screens. Each is a polished *framed +
caption + gradient* marketing image at exact store dimensions.

| Device class   | Store canvas (px) | Capture device                       |
|----------------|-------------------|--------------------------------------|
| iOS iPhone 6.9"| 1320 × 2868       | `iPhone 17 Pro Max` simulator        |
| iOS iPad 13"   | 2048 × 2732       | `iPad Pro 13-inch (M4)` simulator     |
| Android phone  | 1080 × 2400       | `Medium_Phone_API_35` emulator        |
| Android tablet | 1600 × 2560       | AVD created from `android-35` image   |

The iPad sim renders at 2064 × 2752 natively; Stage B scales/letterboxes the raw
capture to fit the 2048 × 2732 canvas. Android canvases are the marketing frame
size; raw captures are the emulator's native resolution, scaled to fit.

## The 6 core screens + draft captions

1. **Scan** — *"Crisp scans in one tap"* — edge-detection review screen
2. **Library** — *"Your documents, organized"* — Documents list
3. **Filters** — *"Auto-enhance every page"* — Auto / Color / Grayscale picker
4. **PDF export** — *"Export polished PDFs"* — PDF preview
5. **Search** — *"Find any word, instantly"* — full-text search results
6. **Privacy** — *"100% private — nothing leaves your device"* — share/privacy

Caption copy is a starting point and may be edited without changing the pipeline.

## Pipeline (two stages)

### Stage A — capture raw native screenshots
- Reuse the existing deterministic seed (ACME Invoice + Q2 Report fixtures) so
  every device shows identical, clean content — no debug banners, no green
  edge-detection dots left on screen.
- An `integration_test` driver navigates to each of the 6 states and calls
  `IntegrationTestWidgetsFlutterBinding.takeScreenshot()`, producing
  pixel-accurate device-resolution PNGs.
- Run once per sim/emulator with `-d <device-id>`.
- Output → `store/raw/<class>/<screen>.png`.

Follows the project's existing seed + `integration_test` + `simctl`/`adb`
harness pattern. OpenCV/ML Kit run on the iPad Pro M4 sim and iOS 18.3 sim
(verified previously); Android emulator likewise.

### Stage B — compose the marketing image
- One HTML/CSS template rendered by a **headless browser (Playwright)** at the
  exact canvas size, then screenshotted.
- Template draws: on-brand gradient background (indigo → `#2E7DFF`), a bold
  caption, and the raw screenshot inside a CSS device bezel with a soft shadow.
- Parameterized by `{caption, screenshot, deviceStyle, canvasSize}`; a small
  `build.mjs` loops over all 24 permutations.
- Output → `store/final/<class>/<screen>.png`.

**Why HTML/Playwright over Pillow or a design tool:** CSS gives crisp text, real
gradients/shadows and clean bezels for free; the whole set regenerates instantly
from one template after any copy/color tweak. Pillow needs hand-built frame
assets and manual text layout; a design tool won't parameterize across 4 sizes.

## Brand palette (from marketing site + app theme)

- Accent: `#2E7DFF`, accent-dark: `#1E5FD6`
- Ink: `#1A2238`
- App seed: `Colors.indigo` (Material 3)
- Product name: **ScannerCam Light**
- Font: system UI stack (`-apple-system, Roboto, …`)

## Output layout

```
store/
  raw/{ios-iphone,ios-ipad,android-phone,android-tablet}/*.png
  final/{ios-iphone,ios-ipad,android-phone,android-tablet}/*.png
  template/frame.html + build.mjs
  README.md   # how to regenerate
```

## Verification (definition of done)

- All 24 finals exist at exactly the target dimensions (assert via `sips`).
- Visually inspect ≥1 screen per device class (read the PNG): caption legible,
  correct bezel, no debug artifacts.
- Raw captures come from real sims/emulators, not upscaled fakes. Any device
  class that will not boot in this environment is named as an explicit gap, not
  silently substituted.

## Risks / gaps

- Building + booting 4 sims/emulators is the slow part (minutes each). If a
  device class cannot boot, deliver the others and flag the gap explicitly.
- Android tablet AVD must be created (`avdmanager`) from the installed
  `android-35 google_apis_playstore/arm64-v8a` image.
- These are marketing assets, not app code, so the TDD/BDD gate does not apply
  in the usual sense; verification is dimensional + visual inspection.
