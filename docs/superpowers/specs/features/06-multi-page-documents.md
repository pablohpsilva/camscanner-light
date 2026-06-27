# Feature 06 — Multi-page Documents

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** Features 01/03/05 (a page); shares the document model with Feature 02
**Feeds:** Feature 07 (multi-page PDF export)

## Purpose

Promote a document from a single page to an ordered collection of pages, where
capture, crop, and enhancement compose into a real multi-page document.

## Model

- **Document = ordered list of pages + metadata** (name, created/modified date).
- **Page = original + corners + mode + enhancement settings** (defined in
  Features 03/05).
- This model is shared with **Feature 02 (document library)**, which manages the
  list of documents; Feature 06 manages pages **within** a document.

## Operations (thumbnail strip/grid)

| Operation | Behavior |
|---|---|
| **Add pages** | During capture (Single appends 1, Batch appends many) **and** re-open the camera from an existing document to append more pages later |
| **Reorder** | Drag pages in the thumbnail grid |
| **Delete page** | Remove a page (with confirm) |
| **Retake / replace** | Re-capture a page in place |
| **Insert** | Add a new page at a chosen position |

- **Last-page rule:** deleting the final page deletes the whole document (with a
  clear confirm).
- **Adding pages later:** supported on existing documents.

## Architecture (SOLID/KISS/DRY)

- A `Document` aggregate with pure operations (add/remove/reorder/insert return
  new state) — trivially unit-testable (SRP, KISS).
- Thumbnails are derived from the enhancement cache (DRY — no separate render
  path).

## Out of scope

- Multi-page **PDF** generation (Feature 07 / step H5 — this feature produces the
  ordered page list). OCR (08).

## Testing strategy (TDD/BDD first)

- **Unit:** add/reorder/insert/delete preserve order & integrity; deleting the
  last page triggers document deletion.
- **Widget:** thumbnail grid drag-reorder; retake replaces in place; confirm
  dialogs.
- **BDD scenarios:**
  - *Given a 2-page document, when I drag page 2 above page 1, then the order
    swaps and persists.*
  - *Given an existing document, when I add pages via Batch, then they append in
    capture order.*
  - *Given a 1-page document, when I delete that page and confirm, then the whole
    document is removed.*

## Deliverable (user-testable)

A **multi-page document** with a thumbnail grid to add, reorder, delete, retake,
and insert pages. **You can test it by** building a 3-page document,
drag-reordering pages (order persists), returning later to append more via Batch,
retaking a page in place, and deleting the final page (the document is removed
after confirm).

## Acceptance criteria (each closed only by a passing test)

- [ ] A document holds an ordered list of pages with metadata — *unit*
- [ ] Add (at creation and later), reorder, delete, retake, and insert pages — *unit: ops · widget: drag-reorder*
- [ ] Deleting the final page deletes the document after confirmation — *unit + BDD*
- [ ] Page operations preserve order and integrity — *unit*

---

> **Definition of Done gate:** Per the Definition of Done in `00-overview-roadmap.md`, this feature is **not done** until every acceptance criterion above is mapped to a passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is run and observed green, quality gates pass, and the work is reviewed and double-checked. "Looks right" / "should pass" is not done.
