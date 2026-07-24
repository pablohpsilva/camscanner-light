# Auto filter — local adaptive contrast (color-preserving)

Date: 2026-07-24
Status: Approved design, ready for implementation plan
Target release: 1.1.3 (or the next build after)

## Problem

The "Auto" (Scanned document) filter is the default enhancement applied to every
saved page. On a photo taken against a **bright-white background**, text becomes
faint or vanishes — "impossible to read." Reported from device testing.

### Root cause

`autoEnhanceOriented` (`auto_enhancer.dart`) runs two stages:

1. **Stage 1 — per-channel flat-field** (`_flatten`): estimates local paper white
   (max-filter dilation + blur on a 512px proxy) and divides each channel by it.
   Removes shadow gradient + warm colour cast. **This stage is fine.**
2. **Stage 2 — global white-point stretch** (`_whitePointStretch` via the shared
   `whitePointLut3Table`): builds one per-channel histogram over the *whole* image,
   picks a white point at the 99th percentile, and pulls everything above
   `0.55 × whitePoint` (≈140) toward 255.

On a bright scene the whole histogram sits high, so Stage 2 pushes light/faded
text (values above ~140) into the white page. Contrast is judged **globally**, so
a region's text is measured against the entire image rather than its neighborhood.
There is no local contrast, so faded text on bright paper has nothing to make it
pop.

## Goal

Replace Stage 2 with a **local, color-preserving adaptive contrast** step so text
is legible regardless of background brightness, while colour documents and photos
still look natural (Auto runs on everything by default). Keep the native/Dart dual
implementation within the existing `np2` parity gate.

Non-goal: binarization (black-on-white) — rejected, would destroy colour content.
Non-goal: replacing Stage 1. Non-goal: a new user-facing filter mode.

## Design

### Pipeline (new Stage 2 only)

Stage 1 (`_flatten`) is unchanged. After it, the buffer is a flattened colour
image (white page, coloured ink). New Stage 2 = **local luminance contrast stretch
with colour preserved**:

1. **Luminance proxy.** Compute `Y = 0.299R + 0.587G + 0.114B` and downscale to a
   proxy (same proxy discipline as Stage 1: long side `kAutoProxyLongSide` = 512,
   `Interpolation.average` on Dart / `INTER_AREA` on native).
2. **Two smoothed reference fields** on the proxy:
   - **local white** `W` = windowed **max** of `Y` (local paper white),
   - **local black** `B` = windowed **min** of `Y` (local ink),
   each over radius `kAutoLocalWindowRadius`, then Gaussian-blurred with radius
   `kAutoLocalBlurRadius`. (Dart: separable max/min loops mirroring the existing
   `_maxFilter`; native: `cv.dilate` / `cv.erode` + `cv.gaussianBlur`.)
3. **Per full-res pixel**, bilinearly sample `B` and `W` from the proxy fields
   (identical bilinear sampling to `_flatten`), then:
   - `span = W − B`.
   - **Blank/low-contrast guard:** if `span < kAutoLocalMinSpan` the region has no
     real ink — leave the pixel unchanged (prevents amplifying sensor noise into
     speckle on blank paper).
   - else `Y' = clamp((Y − B) · 255 / span, 0, 255)` (local linear stretch), then
     **strength blend** so clean images aren't over-cooked:
     `Yout = Y + kAutoLocalStrength · (Y' − Y)`.
   - **Colour preserved:** `scale = Yout / Y` (guard `Y > 0`); `R,G,B *= scale`,
     clamp to `[0,255]`. When `Y ≈ 0`, write `Yout` to all three channels (grey).

Why this fixes the bug: each region is stretched against **its own** local black
and white, so faded text on a bright desk darkens and pops while the page stays
white. Bright background no longer drags the whole tone curve upward.

### New constants (in `auto_enhancer.dart`, shared by native via `show`)

| Constant | Purpose | Starting value (tune) |
|---|---|---|
| `kAutoLocalWindowRadius` | max/min window radius on the proxy | 16 |
| `kAutoLocalBlurRadius` | smoothing of the B/W fields | 24 |
| `kAutoLocalMinSpan` | below this local span → leave region untouched | 40 |
| `kAutoLocalStrength` | blend of stretched vs original luma (0..1) | 0.8 |

Values are starting points; tuned against repo fixtures + the synthetic
bright-white fixture (below). Final values recorded in the code comments with the
reasoning, matching the style of the existing `kAuto*` doc-comments.

### Parity strategy

Follow the **existing** flat-field pattern, which is already NOT byte-identical but
stays within the gate:

- Shared pure math is minimal here (the per-pixel formula), so the formula is
  written **identically** in both files, documented as "keep in sync," exactly as
  the flat-field divide already is.
- Native path (`native_enhancers.dart::autoFlatField`) builds the B/W fields with
  `cv.erode`/`cv.dilate` + `cv.gaussianBlur` on the luma Mat, then does the stretch
  with Mat arithmetic (`subtract`, `divide`, `max`, per-pixel multiply of the
  colour Mat by the `Yout/Y` ratio Mat). Dart path uses mirrored byte loops.
- **Gate:** `np2_native_auto_parity_test.dart` asserts `mean < 2.0`. Today's
  measured mean is ~0.151, so there is headroom. Target: keep `mean < 2.0`. If the
  local min/max sampling difference pushes it higher, **report the measured number
  and decide explicitly** — never silently relax the threshold. If a small bump is
  justified, change the constant in the test with a comment stating the measured
  value and why.

### Files touched

- `lib/features/library/auto_enhancer.dart` — remove the `_whitePointStretch` call
  from `autoEnhanceOriented`; add `_localContrast` (luma proxy, B/W fields, per-
  pixel stretch); add the four constants.
- `lib/features/library/native_enhancers.dart` — replace the `whitePointLut3`
  stretch in `autoFlatField` with the mirrored local-contrast Mat pipeline; import
  the new constants via `show`.
- `lib/features/library/white_point_lut.dart` — **keep** only if still referenced
  by another mode; grep first. Auto no longer uses it. If nothing else references
  it, delete `white_point_lut.dart` and its test; otherwise leave untouched.
- `test/features/library/auto_color_enhancer_test.dart` — update expectations that
  assumed the global stretch; add new local-contrast tests.
- `integration_test/g3_auto_color.feature` (+ generated `_test.dart` + steps) — new
  BDD scenario for faded text on a bright background.
- `integration_test/np2_native_auto_parity_test.dart` — unchanged threshold unless
  measurement forces a documented bump.

## Testing (TDD + BDD, both platforms — non-negotiable)

### Host unit tests (`flutter test`, pure-Dart path, no libdartcv)

Write these **first** (red), then implement:

1. **Core fix:** synthetic 120×40 image, uniform bright background (Y≈245) with a
   *faded* text block (Y≈170). After enhance, `text.luminance` drops well below the
   background and the text/background contrast ratio increases materially
   (e.g. text < 120, background > 220).
2. **Blank-region guard:** uniform near-white patch with only sensor-like noise
   (±3) → output std stays low (no speckle amplification); mean stays near-white.
3. **Colour preservation:** a saturated coloured region keeps its hue — R/G/B
   ordering preserved and chroma not collapsed (reuse the existing "not grayscale"
   assertion style).
4. **Regression — existing behaviours still hold:** shadow flattening (bg near-
   white, variance low), warm-cast neutralization, contrast reaches near-255 on
   bright paper, uniform image no-op, tiny (8×8) image no crash, corrupt-input
   passthrough, EXIF baking, timeout fallback. Adjust only the assertions that were
   coupled to the *global* stretch, and only as much as the new algorithm requires.

### BDD (`.feature` + generated widget test + shared steps)

Add to `g3_auto_color.feature`:

```gherkin
Scenario: Auto filter keeps faded text readable on a bright background
  Given the review screen is open with a captured image
  When I toggle the auto filter
  And I tap Accept
  Then the auto enhancer keeps the faded text readable
```

New step `the_auto_enhancer_keeps_the_faded_text_readable.dart` in `test/step/`
asserting the saved page's text/background contrast increased. Regenerate with
`build_runner`.

### Device / integration (real Android AND real iOS)

- `np2_native_auto_parity_test.dart` — native ≈ Dart within the gate; **print and
  record** the measured mean on each platform.
- A device integration test feeding the synthetic bright-bg + faded-text fixture
  through `NativePageProcessor` and asserting the text/background contrast
  increased on-device.
- Run the full host suite + the g3/np1/np2/np3/e2/e5 integration tests on both a
  real Android device and a real iOS device. Record exact commands + green output.

## Known gaps (named, not hidden)

- **No real bright-white repro photo.** Tuning + verification use a *synthetic*
  bright-bg/faded-text fixture. Final confirmation on the user's actual failing
  photo remains an open gap until one is provided.
- **Parity headroom is empirical.** If local field sampling exceeds the `np2`
  gate, the measured number is surfaced for an explicit decision.

## Decomposition into parallel subagent tasks

The scalar per-pixel formula is the shared contract. Fix it first; it unblocks the
Dart and native implementations to proceed in parallel.

- **T0 (blocking, tiny):** finalize the local-stretch formula + constants and write
  it as a short reference (doc-comment + the exact expression). Unblocks T1–T3.
- **T1 (parallel):** host unit tests for the Dart path (red first) — the core fix,
  guard, colour, and regression tests.
- **T2 (parallel):** Dart implementation in `auto_enhancer.dart` (make T1 green).
- **T3 (parallel):** native mirror in `native_enhancers.dart` using the identical
  formula.
- **T4 (parallel):** BDD `.feature` + step + `build_runner` regen.
- **T5 (parallel, independent):** generate/commit the synthetic bright-bg fixture
  and a tiny helper to build it (used by T1 and the device test).
- **T6 (after T2+T3):** `np2` parity check + device integration on both platforms;
  record measurements.
- **T7 (after T2):** grep for `white_point_lut` references; delete the file + test
  if Auto was its only consumer, else leave it.

Each task keeps the TDD+BDD, both-platforms, verify-then-claim bar.
