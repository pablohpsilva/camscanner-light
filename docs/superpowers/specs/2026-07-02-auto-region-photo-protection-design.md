# Auto Filter — Region-Level Photo Protection (multi-cue detection)

**Date:** 2026-07-02
**Status:** Approved (brainstorming), pending spec review
**Feature area:** `apps/mobile` scan/library image enhancement
**Builds on:** `2026-07-02-auto-photo-protection-design.md` (per-pixel background-brightness gate, merged)

> **Design history:** an earlier draft of this spec used a morphological
> *opening on the brightness-derived paper-ness map*. Plan self-review found it
> only absorbs small highlight *specks*; a photo with a large bright region
> (sky, pale sub-area) still washes out, because brightness alone cannot
> separate "bright paper" from "a bright area inside a photo". This spec
> replaces that with multi-cue detection.

## Problem

The merged `Auto` filter gates flat-field shadow removal on per-pixel
background brightness, protecting only *uniformly-dark* regions. Real
photographs still wash out: their mid-tones/highlights read as "bright paper"
and get divided toward white (verified: a bright patch inside a dark block blew
to 255 with a halo). Brightness is not a sufficient signal — a photo must be
detected by **what it is** (color / detail / darkness), not how bright it is.

## Goal

Detect photo regions by multiple content cues and preserve the WHOLE region —
bright, dark, smooth, or textured — as captured, while paper shadow removal
stays unchanged.

**Two product decisions (locked):**
- *Preserve as captured:* a detected photo region is left essentially untouched
  (no flat-field). A shadow across the photo itself stays on the photo.
- *Favor text de-shadowing:* when detection is uncertain, treat the region as
  paper and de-shadow it. Never sacrifice shadow removal on text (the primary
  content). Only *clearly*-photo regions are preserved; thresholds are set high
  and thin/sparse detections (text-edge speckle) are discarded.

Constraints (inherited):
- Inside `Auto` only — no new tile, enum, or UI change.
- Pure-Dart (`image` package), inside the existing `compute` isolate.
- `ImageEnhancer.enhance` never throws — return input bytes on any failure.
- No bare magic numbers — named, documented consts.

## Architecture

All detection runs on the existing 48px background proxy (cheap). The pipeline
produces a per-pixel correction `alphaMap` (photo→0, paper→1) that gates the
existing flat-field divide. The background step must expose the **pre-grayscale
color proxy** (for chroma) alongside the grayscale background.

### Stage 1 — per-pixel photo cues (on the color proxy)

- **Chroma** `= max(R,G,B) − min(R,G,B)`. Paper/black-text are near-neutral
  (≈0); most photos carry color. Catches bright colorful photo areas.
- **Local texture** `= local std-dev of luminance` over a 3×3 proxy window.
  Continuous-tone detail is textured; flat paper isn't. Catches grayscale photos.
- **Darkness** `= correctionWeight(B) ≈ 0` (existing paper-ness). Catches solid
  dark blocks.

A proxy pixel is a **photo seed** iff
`chroma > _kChromaThresh` OR `texture > _kTextureThresh` OR `correctionWeight(B) <= 0`.
Thresholds are conservative (high) so faint paper texture/color does not trip.

### Stage 2 — seed → clean region mask (morphology on the proxy)

1. **Opening** (`_minFilter` then `_maxFilter`, radius `_kSpeckleRadius`) on the
   binary seed — removes thin/sparse detections (text-edge speckle) while a
   filled photo body survives. This enforces the "favor text" bias.
2. **Closing** (`_maxFilter` then `_minFilter`, radius `_kConsolidateRadius`)
   then **fill-holes** (`_fillHoles`) — merges surviving seed into solid regions
   and absorbs *enclosed* smooth/bright sub-areas into the photo region (fixes
   the large-bright-region problem).
3. **Feather** (`img.gaussianBlur`, radius `_kMaskFeather`) — seam-free edges.
4. **Invert to correction weight + upscale.** Photo region → alpha 0; elsewhere
   → alpha 1. Upscale (`copyResize`, linear) to full resolution → `alphaMap`.

### Stage 3 — gated divide (unchanged formula)

`_divideByBackground(src, bg, alphaMap)`: per pixel `alpha = alphaMap.r/255`;
`b<=0` guard; `scale = 1 + alpha*(255/b − 1)`. alpha≈0 → preserved; alpha≈1 →
full shadow removal.

### New units (each isolated / testable)

- `_luminanceStdDev(img.Image proxy, int x, int y) -> double` — 3×3 std-dev; or a
  whole-image `_textureMap`.
- `_chroma(img.Pixel) -> int` (or inline in the seed builder).
- `_minFilter(img.Image, int) -> img.Image` — erosion (mirror of `_maxFilter`).
- `_fillHoles(img.Image mask) -> img.Image` — flood-fill background from the
  border; unreached background pixels are enclosed holes → set to foreground.
- `@visibleForTesting img.Image buildCorrectionMask(img.Image proxyColor)` — the
  whole Stage 1+2 pipeline; returns a grayscale mask (channel = alpha*255) at
  proxy resolution. Upscale happens at the call site.
- `_backgroundProxy` returns the grayscale background proxy; `_autoFn` also
  keeps the color proxy to pass to `buildCorrectionMask`.

### Named constants (no magic numbers)

| Constant | Purpose | Initial value |
|---|---|---|
| `_kChromaThresh` | Min chroma (0–255) for a pixel to seed as photo | 25 |
| `_kTextureThresh` | Min local std-dev for a pixel to seed as photo | 18 |
| `_kSpeckleRadius` | Opening radius that removes text-edge speckle (proxy px) | 1 |
| `_kConsolidateRadius` | Closing radius that merges the photo region (proxy px) | 2 |
| `_kMaskFeather` | Mask feather radius (anti-seam) | 2 |

Values tuned on-device. `correctionWeight`, `_kPaperFloor`/`_kGateBand`,
`_maxFilter`, `_autoLevels`, and the public `AutoEnhancer` API are unchanged.

## Residual limitation (honest)

A photo region that is *entirely* smooth, neutral-gray, bright, and not enclosed
by any detected content is locally indistinguishable from paper and will still
be flattened. This is degenerate (a blank gray card) and, given the "favor text"
bias, is the correct failure direction.

## Files & structure

Same tight surface (one production file):
- **Modify** `apps/mobile/lib/features/library/auto_enhancer.dart` — add the cue
  helpers, `_minFilter`, `_fillHoles`, `buildCorrectionMask`, the 5 consts;
  expose the color proxy from the background step; thread `alphaMap` into
  `_divideByBackground`; update `_autoFn`.
- **Modify** `apps/mobile/test/features/library/auto_color_enhancer_test.dart`.
- **Modify** `apps/mobile/integration_test/g3_auto_color.feature` (or just its
  Then step) + regenerate `g3_auto_color_test.dart` via build_runner.

## Testing — TDD and BDD first

### TDD (unit — each cue/stage in isolation via @visibleForTesting seams)
- **Chroma cue:** saturated color patch on neutral paper → patch seeds, paper not.
- **Texture cue:** noisy grayscale patch on flat paper → patch seeds, paper not.
- **Text rejected (bias proof):** sparse thin dark strokes on bright paper →
  after opening the mask stays alpha≈1 everywhere → text still de-shadows.
- **Fill-holes:** a ring of seed with an enclosed hole → hole becomes photo.
- **`buildCorrectionMask` end-to-end:** dark body + bright interior patch +
  colorful corner → whole region alpha≈0; surrounding paper alpha≈1.

### TDD (behavioral — through `enhance`)
- **Grayscale detailed photo** on shadowed paper → preserved (interior bright
  areas not blown), paper still flattened.
- **Bright colorful photo** region → preserved (chroma-caught, not whitened).
- **No regression:** existing shadow-gradient (text) test and solid-dark-block
  test still green (unweakened); a text-heavy shadowed region still de-shadows.

### BDD (device only)
- Extend the photo Then step to a colorful + textured block with a bright patch,
  asserting preservation; regenerate via build_runner.

### On-device verification
Re-run the harness on RZCY51D0T1K + iOS sim with four inputs: text page (must
de-shadow), dark photo, bright/colorful photo, and a text-dense page (must NOT
false-positive). Tune the five thresholds only if the device disagrees.

## Out of scope (YAGNI)

- ML / learned segmentation.
- Evening-out shadows that fall across the photo itself (preserve-as-captured).
- Any change to `bw`, `grayscale`, `color`, `none`, the enum, or the UI.
