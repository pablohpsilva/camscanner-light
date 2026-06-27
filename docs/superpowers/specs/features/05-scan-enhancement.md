# Feature 05 — Scan Enhancement (Filters)

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** Feature 03 (flattened page), OpenCV backend (Feature 04)
**Feeds:** Feature 06 (multi-page), Feature 07 (PDF export)

## Purpose

After flattening, make the page look like a clean scan: apply a filter, remove
the paper's background/shadows, fix brightness/contrast, sharpen. Turns "photo of
paper" into "crisp document."

## Scope

**In scope**
- A small set of filters applied to the flattened page.
- A filter picker with live thumbnail previews.
- Non-destructive enhancement settings on the page model.

**Out of scope**
- Crop/flatten/angle correction (03/04), OCR (08), multi-page (06).

## Filters

| Filter | What it does |
|---|---|
| **Original / None** | Flattened image, no enhancement |
| **Auto / Magic** (default) | One-tap best result: background removal + contrast + white balance |
| **Color** | Color document — whiten background, boost contrast/saturation |
| **Grayscale** | Grayscale with contrast boost |
| **Black & White** | Adaptive threshold — crisp text/line docs, smallest files |

- **Auto/Magic is the default** applied to a newly flattened page.

## Manual adjustments (deferred)

- Brightness / contrast (+ optional sharpness) sliders, layered on any filter.
- **Deferred** to a follow-on step after the core filters work (KISS).

## Non-destructive model

- The chosen filter is a **stored parameter**; the enhanced image is derived from
  the flattened cache.
- A page = **original + corners + mode + enhancement settings**. Re-selectable
  any time with no cumulative quality loss.

## Architecture (SOLID/KISS/DRY)

- OpenCV behind an `ImageEnhancer` interface (DIP); runs **off the UI thread**.
- Each filter is a small, single-purpose strategy (SRP/OCP) — new filters add
  without modifying existing ones.

## Build order

Grayscale → Black & White → Color/Auto → filter picker UI → (later) manual
sliders.

## Testing strategy (TDD/BDD first)

- **Unit:** each filter transform on fixture images (deterministic output);
  non-destructive re-derivation (same input + filter ⇒ identical result);
  default = Auto/Magic.
- **Widget:** picker shows previews; selecting a filter updates the page; choice
  persists.
- **BDD scenarios:**
  - *Given a flattened page, when I select Black & White, then the page renders as
    a crisp thresholded document and the choice is saved.*
  - *Given a page with a filter applied, when I switch to Grayscale, then it
    re-derives from the flattened cache with no cumulative loss.*
  - *Given a newly flattened page, then Auto/Magic is applied by default.*

## Acceptance criteria

1. User can apply Original, Auto/Magic, Color, Grayscale, and B&W to a page.
2. Auto/Magic is applied by default to a newly flattened page.
3. Filter choice is stored and re-derives non-destructively.
4. Picker shows live previews; enhancement runs off the UI thread.
5. New filters can be added without modifying existing filter code.
6. All logic test-first; BDD scenarios pass.

---

> **Definition of Done gate:** Per the Definition of Done in `00-overview-roadmap.md`, this feature is **not done** until every acceptance criterion above is mapped to a passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is run and observed green, quality gates pass, and the work is reviewed and double-checked. "Looks right" / "should pass" is not done.
