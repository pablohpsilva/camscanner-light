# Feature 03 — Manual Crop & Perspective

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** Feature 01 (capture)
**Feeds:** Feature 05 (enhancement); consumed by Feature 04 (auto edge detection
supplies initial corners)
**Open dependency:** imaging engine choice — decided in Feature 04

## Purpose

Given a captured image, let the user confirm/adjust the document's four corners,
then warp the image so the document appears perfectly flat and head-on — like a
real scan, not an angled photo.

## Scope

**In scope**
- Crop/adjust screen with draggable corners and connecting edges.
- Perspective transform (homography) → flattened document image.
- Non-destructive page model and re-edit.

**Out of scope**
- Automatic corner detection (Feature 04 — this feature only *consumes* corner
  positions). Filters/enhancement (Feature 05).

## Crop UI (accepted)

- 4 draggable corner handles + lines connecting them, constrained within image
  bounds.
- **Magnifier loupe** pops up near the dragged corner for finger-precise
  placement.
- **"Use full image / no crop"** option for frame-filling material (e.g.
  whiteboards).
- **Convex-quad enforcement** — crossed/inverted shapes are prevented/clamped.

## Non-destructive page model (accepted)

- A page is defined by **original captured image + 4 corner coordinates + capture
  mode**.
- The flattened image is a **derived cache** for display/PDF.
- Re-editing reloads the original with saved corners — zero cumulative quality
  loss; enables future re-processing (re-run OCR/filters). Build step E3.
- Cost accepted: ~2× image storage per page (originals may be compressed).

## Flatten output sizing (phased)

1. **#1 Edge-length sizing (baseline):** output width = longer of top/bottom
   edges; height = longer of left/right edges. Simple, robust.
2. **#2 Geometry-corrected aspect (refinement):** estimate the document's true
   aspect ratio from the perspective quad (foreshortening compensation).
3. **#3 Optional paper-size snap toggle (last, off by default):** fit the
   flattened result to nearest A4/Letter/etc.

Implement #1 first; advance to #2/#3 as quality requires.

## Architecture (SOLID/KISS/DRY)

- The warp is a **pure function**: `(image, corners) -> flattened image`, behind
  an `ImageWarper` interface (DIP) — UI depends on the interface, not the concrete
  CV library.
- Runs **off the UI thread** (background isolate) for responsiveness.
- Page model (source + transform) is independent of rendering/caching (SRP).

## Testing strategy (TDD/BDD first)

- **Unit:** homography math; #1 edge-length output sizing; convex-quad
  validation; non-destructive re-derivation (same source+corners ⇒ identical
  output).
- **Widget:** corner dragging within bounds; magnifier appears; "no crop" path;
  invalid-quad prevention.
- **BDD scenarios:**
  - *Given a captured image with default corners, when I drag a corner and
    confirm, then the page is flattened to a head-on rectangle using those
    corners.*
  - *Given a flattened page, when I re-open crop and adjust a corner, then the
    page re-derives from the original with no cumulative quality loss.*
  - *Given a near-full-frame photo, when I choose "use full image", then the
    whole image is kept without warping.*
  - *Given I drag a corner past another to cross the quad, then the adjustment is
    prevented/clamped to a valid shape.*

## Deliverable (user-testable)

A **crop/adjust screen**: drag the 4 corners (with a magnifier) and confirm to
get a flattened, head-on page. **You can test it by** capturing an angled
document, adjusting the corners and confirming a flat result; re-opening crop and
re-adjusting with no quality loss; and using "use full image" on a frame-filling
photo.

## Acceptance criteria (each closed only by a passing test)

- [ ] Adjust 4 corners (magnifier) and confirm → flattened head-on page (sizing #1) — *BDD: drag+confirm · unit: homography + edge-length sizing*
- [ ] "Use full image" bypasses warping — *BDD*
- [ ] Invalid (non-convex) quads are prevented — *unit: convex validation · widget*
- [ ] Re-edit reloads original + saved corners with no cumulative loss — *unit: re-derivation is identical*
- [ ] Warp runs off the UI thread; UI stays responsive — *unit/perf*

---

> **Definition of Done gate:** Per the Definition of Done in `00-overview-roadmap.md`, this feature is **not done** until every acceptance criterion above is mapped to a passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is run and observed green, quality gates pass, and the work is reviewed and double-checked. "Looks right" / "should pass" is not done.
