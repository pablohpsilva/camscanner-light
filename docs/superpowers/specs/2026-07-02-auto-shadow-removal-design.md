# Auto Filter Shadow Removal — Design

**Date:** 2026-07-02
**Status:** Approved (brainstorming), pending spec review
**Feature area:** `apps/mobile` scan/library image enhancement

## Problem

Photos captured by holding a phone over a document frequently carry a **shadow
gradient** (the hand/phone occludes ambient light). The current `Auto` filter
uses a *single global* histogram stretch (`_autoLevels`) plus a saturation bump.
A global adjustment cannot fix uneven illumination: brightening the shadowed
corner blows out the lit corner and vice-versa. Shadows survive.

## Goal

Upgrade the existing **`Auto`** filter (the default) so it removes shadows and
produces a **clean white-paper** look: uniform bright-white background, shadow
gradient gone, text/ink crisp and dark, ink/stamp color preserved.

Constraints:
- No new filter tile, enum value, or UI change. Only `Auto`'s internals change.
- Pure-Dart (`image` package), running inside the existing `compute` isolate —
  identical result on iOS and Android, host-testable, matches the other four
  enhancers. No OpenCV (breaks host-test story per project memory).
- Honor the `ImageEnhancer` contract: **never throws**; on any failure return
  the input bytes unchanged.

## Algorithm — flat-field / background division

Estimate how bright the **paper background** is at every point, then divide it
out so every region normalizes to the same white. The shadow gradient — being a
low-frequency background brightness variation — is removed.

Inside `_autoFn` (top-level, isolate-sendable):

1. `img.decodeImage` + `img.bakeOrientation` (unchanged from current enhancers).
2. **Estimate background illumination map `B(x,y)`** — `_estimateBackground`:
   - Downscale to a tiny proxy (longest side `_kBackgroundProxyPx ≈ 48`). This
     is the performance trick: a huge blur on the full frame becomes a cheap op
     on a thumbnail. If the frame is already smaller than the proxy, skip the
     downscale (graceful degradation for tiny/test images).
   - On the proxy: grayscale **dilation** (max filter, radius `_kDilateRadius`)
     to erase dark ink so only paper brightness remains, then a **Gaussian blur**
     (`_kBlurRadius`) to smooth it into the illumination gradient (incl. shadow).
   - Upscale `B` back to full resolution (bilinear).
3. **Divide (flat-field)** — `_divideByBackground`, in place, per channel:
   `out_c = clamp(in_c * 255 / B(x,y), 0, 255)`. Shadowed paper (low `B`) is
   boosted to white; ink (far darker than local `B`) stays dark. Channels scale
   proportionally, so ink/stamp hue is preserved. Guard `B == 0`.
4. **White-point + contrast finish** — reuse existing `_autoLevels` / `_histClip`
   to push the paper fully to 255 and crisp the text.
5. `img.encodeJpg(quality: 92)`.
6. Wrap in `try/catch` → return input `bytes` on any failure.

### Named constants (no magic numbers)

| Constant | Purpose | Initial value |
|---|---|---|
| `_kBackgroundProxyPx` | Longest side of the downscaled background proxy | 48 |
| `_kDilateRadius` | Max-filter radius on the proxy (erases text) | 1 |
| `_kBlurRadius` | Gaussian blur radius on the proxy (smooths illumination) | 3 |

Values are starting points; final tuning happens against real shadowed photos
during on-device verification.

## Files & structure

Minimal surface. Everything except `_autoFn`'s algorithm stays as-is:

- **`apps/mobile/lib/features/library/auto_enhancer.dart`** — replace the body
  of top-level `_autoFn`. `AutoEnhancer` (const, `implements ImageEnhancer`,
  `compute`-based) unchanged. Add isolate-sendable top-level helpers
  `_estimateBackground`, `_divideByBackground`; keep/reuse `_autoLevels`,
  `_histClip`. One self-contained file, matching the `bw_enhancer.dart` +
  `_otsuThreshold` convention.
- **Unchanged:** `enhancer_mode.dart`, `filter_picker_strip.dart`,
  `capture_review_screen.dart` mapping, thumbnails.

## Testing — TDD and BDD first

Write tests before implementation.

### BDD (behavior, end-to-end)

Extend the G3 enhancement feature with a shadow scenario. The behavioral
guarantee is that an Auto-enhanced capture of a shadowed page is saved with a
**substantially flattened / brightened background**.

- New scenario (feature + generated integration test + step files):
  *"Auto filter flattens shadows — shadowed capture saved with uniform background."*
- Uses a shadowed-page fixture. Assertion in the `..._is_saved_...` step reads
  back the saved bytes and checks background-brightness variance collapsed vs.
  the source.
- Runs on device/sim (host suite skips `integration_test`, per project memory).

### TDD (unit, pixel-level proof) — `auto_color_enhancer_test.dart`

- **Core shadow test:** synthesize a white page + dark text rectangles + a strong
  linear brightness gradient (simulated shadow). After `enhance`, assert:
  (a) background-brightness **variance** across the frame collapses;
  (b) previously-shadowed-corner background pixels are near-white (> 220);
  (c) text pixels stay dark (contrast preserved).
- **Graceful degradation:** frame smaller than `_kBackgroundProxyPx` → no crash,
  returns a valid JPEG (covers existing 4×4 tests).
- **Keep/adjust existing:** contrast-stretch (`maxR > 220`), color-preservation
  (R≠G), corrupt→unchanged, EXIF-orientation bake, uniform-image no-crash. Run
  them; update only assertions that legitimately change under the new algorithm.

### On-device verification

Host suite cannot judge visual quality. Final sign-off requires a real shadowed
photo processed with `Auto` on device **RZCY51D0T1K** (Android) and the iOS
simulator, confirming: shadow gone, background white, text crisp, color intact —
and constants (`_kDilateRadius`, `_kBlurRadius`) tuned if needed.

## Out of scope (YAGNI)

- New filter tiles / adaptive photo-vs-text detection.
- Changes to `bw`, `grayscale`, `color`, `none`.
- OpenCV-backed processing.
