# Auto Filter — Region-Level Photo Protection

**Date:** 2026-07-02
**Status:** Approved (brainstorming), pending spec review
**Feature area:** `apps/mobile` scan/library image enhancement
**Builds on:** `2026-07-02-auto-photo-protection-design.md` (per-pixel background-brightness gate, merged)

## Problem

The merged `Auto` filter gates flat-field shadow removal on per-pixel background
brightness: pixels whose local background estimate `B` is below `_kPaperFloor`
(95) are left uncorrected. This protects *uniformly*-dark regions (filled
headers, dark blocks) but NOT real photographs. Runtime verification confirmed:
a photo's mid-tones/highlights sit *above* the floor, so they are treated as
"shadowed paper" and pushed to white — a bright patch inside a dark block blew
out to 255 with a soft halo. Per-pixel brightness cannot distinguish "bright
paper" from "a bright area inside a photo"; only *where the region is* can.

## Goal

Make the gate operate at **region** level: detect the large non-paper region
and preserve the WHOLE region — highlights included — as captured, while paper
shadow removal stays unchanged and text documents keep zero regression.

"Preserve as captured": a detected photo region is left essentially untouched
(natural tones, no flat-field). If a shadow also fell across the photo itself,
that shadow stays on the photo but not on the surrounding paper.

Constraints (inherited):
- Stays inside `Auto` — no new tile, enum, or UI change.
- Pure-Dart (`image` package), inside the existing `compute` isolate.
- `ImageEnhancer.enhance` never throws — return input bytes on any failure.
- No bare magic numbers — named, documented consts.

## Key idea

The per-pixel paper-ness weight `correctionWeight(B)` already goes low over a
photo — it just has *bright holes* at the photo's highlights. A morphological
**opening** (min-filter then max-filter) on that weight map erases bright spots
surrounded by low weight, so the whole photo becomes one solid low-weight
region. Paper survives opening unchanged; thin dark ink never enters the map
(the max-filter in `_estimateBackground` already erases it, so paper-ness ≈ 1
over text). The opening runs on the cheap 48px proxy, so it is nearly free.

## Design

The structural change: instead of calling `correctionWeight(b)` per
full-resolution pixel inside `_divideByBackground`, build a feathered per-pixel
**alpha map** up front and thread it into the divide.

Data flow (all on the proxy until the final upscale):
1. `_estimateBackground` produces the small dilated + blurred background proxy.
   Expose that proxy background (`bgProxy`) before it is upscaled.
2. **Paper-ness map:** `weightProxy[i] = correctionWeight(bgProxy_luminance[i])`
   — 1 for paper, 0 for dark content, ramp between. Encoded as a grayscale
   proxy image with channel value `= round(weight * 255)`.
3. **Morphological opening:** `_minFilter(map, _kOpenRadius)` then
   `_maxFilter(map, _kOpenRadius)`. Erases bright holes (highlights) inside
   low-weight photo regions; leaves large paper regions intact.
4. **Feather:** `img.gaussianBlur(map, radius: _kMaskFeather)` — smooths mask
   edges so there is no seam at photo borders.
5. **Upscale:** `copyResize` the mask to full resolution (bilinear) → `alphaMap`
   (grayscale; read channel / 255 as alpha).
6. **Gated divide:** `_divideByBackground(src, bg, alphaMap)` — per pixel:
   `alpha = alphaMap(x,y).r / 255`; keep the `b <= 0` guard; same blend
   `scale = 1 + alpha * (255 / b - 1)`. `alpha ~ 0` inside photos → pixel
   preserved as captured (highlights included); `alpha ~ 1` on paper → full
   shadow removal.

### New units (each testable in isolation)
- `_minFilter(img.Image src, int radius) -> img.Image` — mirror of the existing
  `_maxFilter` (min over a (2r+1)^2 window; reads/writes `.r` on a grayscale).
- `@visibleForTesting img.Image buildCorrectionMask(img.Image bgProxy)` — steps
  2-4 (weight map -> opening -> feather); returns the small mask. Upscale (step
  5) happens at the call site, reusing `copyResize`.
- `correctionWeight` — unchanged signature and tests; now seeds the map.

### Named constants (no magic numbers)

| Constant | Purpose | Initial value |
|---|---|---|
| `_kOpenRadius` | Morphological opening radius on the proxy weight map — the max highlight-hole size (in proxy px) absorbed into a photo region | 2 |
| `_kMaskFeather` | Gaussian feather radius on the mask — edge softness / anti-seam | 2 |

Values tuned on-device against real photos (a photo with a large bright sky may
need a larger `_kOpenRadius`).

### Unchanged
`_estimateBackground` (aside from exposing `bgProxy`), `_autoLevels`, the
`compute`/never-throws wrapper, the public `AutoEnhancer` API, and the two gate
consts `_kPaperFloor` / `_kGateBand`.

## Files & structure

Same tight surface:
- **Modify** `apps/mobile/lib/features/library/auto_enhancer.dart` — add
  `_minFilter`, `buildCorrectionMask`, `_kOpenRadius`, `_kMaskFeather`; expose
  `bgProxy` from the background step; thread `alphaMap` into `_divideByBackground`.
- **Modify** `apps/mobile/test/features/library/auto_color_enhancer_test.dart`.
- **Modify** `apps/mobile/integration_test/g3_auto_color.feature` +
  its Then step; regenerate the integration test via build_runner.

## Testing — TDD and BDD first

### TDD (unit)
- **`buildCorrectionMask` — hole erasure:** a small proxy that is dark (photo)
  with a single bright hole in the middle → assert the hole's mask value is
  pulled DOWN to the surrounding dark level (opening erased it).
- **`buildCorrectionMask` — no false positives:** an all-bright (paper) proxy →
  assert the mask stays ~255 (weight ~1) everywhere (text/paper untouched).
- **`_minFilter`:** a bright field with one dark pixel → the dark spreads over
  the window (min); a small dark field with one bright pixel → bright is erased.
- **The bug, fixed (behavioral, through `enhance`):** a large dark block WITH a
  bright mid-tone patch inside, on shadowed paper. Assert: the interior bright
  patch stays un-blown (luminance below a content threshold), the solid-dark
  part stays dark, AND surrounding paper still flattens to near-white. This is
  the load-bearing proof the region gate fixes what the per-pixel gate could not.
- **No regression:** the existing text/shadow-gradient test and the solid-dark-
  block preservation test pass unchanged; `correctionWeight` unit tests unchanged.

### BDD (on device)
- Extend the photo scenario's Then step so the synthetic image includes a bright
  patch inside the dark block, asserting it is not blown out. Regenerate via
  build_runner. Runs on device/sim only.

### On-device verification
Re-run the two-image harness (text doc + a *rich* photo with highlights) plus a
real captured photo on RZCY51D0T1K + iOS sim: confirm the photo looks natural
(highlights preserved, no halo) and text docs still de-shadow. Tune
`_kOpenRadius` / `_kMaskFeather` only if the device disagrees.

## Out of scope (YAGNI)

- Local-variance / connected-component detection (approach A covers the failure).
- Evening-out shadows that fall across the photo itself (preserve-as-captured).
- Any change to `bw`, `grayscale`, `color`, `none`, the enum, or the UI.
