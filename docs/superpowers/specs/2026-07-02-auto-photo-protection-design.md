# Auto Filter — Photo Protection (background-brightness gate)

**Date:** 2026-07-02
**Status:** Approved (brainstorming), pending spec review
**Feature area:** `apps/mobile` scan/library image enhancement
**Builds on:** `2026-07-02-auto-shadow-removal-design.md` (flat-field shadow removal, merged)

## Problem

The merged `Auto` filter flattens shadows by dividing every pixel by the local
paper-background estimate `B(x,y)`. On-device-style verification confirmed a real
limitation: a **large solid-dark region** (an embedded photo, a filled header,
a dark block) makes `B` saturate to that region's own darkness, so the gain
`255/B` explodes and the region blows out to a glowing near-white blob with a
dark halo rim. Measured: a dark block at luminance 38 became 251 after `enhance`.

## Goal

Make `Auto` **protect genuinely-dark content** (photos/blocks) from blow-out
while keeping full shadow removal on paper. When a region is genuinely dark
(could be a photo OR a very deep shadow over blank paper), err toward treating
it as content and leaving it natural — accept that an unusually deep shadow over
*blank* paper may be left slightly darker rather than pushed fully white.

Constraints (inherited):
- Stays inside `Auto` — no new tile, enum, or UI change.
- Pure-Dart (`image` package), inside the existing `compute` isolate.
- `ImageEnhancer.enhance` never throws — return input bytes on any failure.
- No bare magic numbers — named, documented consts.

## Discriminator

The background estimate `B` already separates the two cases:
- **Shadowed paper:** the max-filter erases ink and finds nearby paper, so `B`
  stays fairly bright even under strong shadow (typically ≥ ~110).
- **Real dark content:** a large dark block has no bright paper nearby for the
  max-filter to grab, so `B` is genuinely dark (~40).

So gating the correction on `B`'s brightness protects photos without any
separate detection pass (no connected-component labeling needed — YAGNI).

## Design — background-brightness-gated flat-field

The only algorithm change is in `_divideByBackground`. Today it divides every
pixel unconditionally. New behavior, per pixel with local background luminance
`b` (read from the grayscale `bg` image, same as today):

1. Compute a correction weight `alpha` from `b`:
   - `b <= _kPaperFloor`            -> `alpha = 0.0` (definitely dark content — keep original)
   - `b >= _kPaperFloor + _kGateBand` -> `alpha = 1.0` (definitely paper — full correction)
   - between                        -> linear ramp `(b - _kPaperFloor) / _kGateBand`
2. Per channel, blend original with the full flat-field result:
   `out = in + alpha * (in * 255 / b - in)`
   - `alpha = 0` -> `out = in` (photo pixel untouched)
   - `alpha = 1` -> `out = in * 255 / b` (full shadow removal, unchanged from today)
3. Clamp each channel to `[0, 255]`. Keep the existing `b <= 0` guard (skip).

The final global `_autoLevels` still runs; it only applies a linear histogram
stretch (1% tail clip), so it will not blow out a preserved dark region.

### Named constants (no magic numbers)

| Constant | Purpose | Initial value |
|---|---|---|
| `_kPaperFloor` | Background luminance at/below which a region is treated as dark content and left uncorrected | 95 |
| `_kGateBand` | Width of the smooth transition above the floor (avoids edge seams / halos) | 25 |

"Protect photos" is encoded by choosing a floor high enough that a genuine photo
(`B ~ 40`) is fully preserved while shadowed paper (`B >= ~110`) is fully
corrected. Final values tuned on-device against real photos.

### Why this also removes the halo

At a block edge, `B` ramps from paper-bright to block-dark across the blur
width, so `alpha` ramps `1 -> 0` across the same span. The interior (`alpha = 0`)
never whitens, and the smooth band means no hard seam.

## Files & structure

Same tight surface as the shadow work:
- **Modify** `apps/mobile/lib/features/library/auto_enhancer.dart` —
  `_divideByBackground` gains the `alpha` gate; add `_kPaperFloor`, `_kGateBand`.
  Everything else (`_estimateBackground`, `_maxFilter`, `_autoLevels`, the
  `compute`/never-throws wrapper, public `AutoEnhancer`) unchanged.
- **Modify** `apps/mobile/test/features/library/auto_color_enhancer_test.dart` —
  add photo-preservation test; keep the shadow-gradient test as the
  no-regression guard.
- **Modify** `apps/mobile/integration_test/g3_auto_color.feature` — add the
  photo-preservation scenario.
- **Create** `apps/mobile/test/step/the_auto_enhancer_preserves_the_photo.dart`.
- **Regenerate** `apps/mobile/integration_test/g3_auto_color_test.dart` via
  build_runner.

## Testing — TDD and BDD first

### TDD (unit) — `auto_color_enhancer_test.dart`

- **Photo preservation (new proof):** page with a large dark block (~solid,
  luminance ~40) plus a shadow gradient. After `enhance`, assert:
  (a) block-interior luminance stays dark (`< 100`) — NOT blown out;
  (b) a paper-background sample away from the block is still near-white (`> 220`)
  — shadow removal on paper did not regress.
- **No regression on thin text:** the existing Task-1 shadow-gradient test passes
  unchanged (thin ink's background estimate is bright paper, so `alpha = 1` and
  text-on-shadowed-paper still flattens). This guards that the gate does not fire
  on normal documents.
- Existing corrupt / EXIF-orientation / uniform / tiny-frame tests stay green.

### BDD (behavior, on device)

- New scenario in `g3_auto_color.feature`:
  *"Auto preserves an embedded photo in a shadowed capture."*
- New Then step `the_auto_enhancer_preserves_the_photo.dart`: reads
  `g1Repo.lastSavedEnhancer` (the UI-selected enhancer), runs it on a
  dark-block synthetic image, asserts the block interior stays dark
  (not whitened). Mirrors the existing shadow BDD step.
- Regenerate the integration test via build_runner. Runs on device/sim only
  (host suite skips `integration_test`).

### On-device verification

Re-run the two verification images (text document + embedded-photo probe) on
device RZCY51D0T1K and the iOS sim after tuning `_kPaperFloor` / `_kGateBand`:
confirm the photo block is preserved (no blow-out/halo) AND the text-document
shadow removal is unchanged.

## Out of scope (YAGNI)

- Connected-component / explicit region masking.
- Global gain-cap approach (does not actually protect photo mid-tones).
- Any change to `bw`, `grayscale`, `color`, `none`, the enum, or the UI.
