# Feature 09 — PDF Editing

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 3 — PDF editing
**Depends on:** Feature 07 (PDF generation, scrub/encrypt pipeline)
**Reuses:** Feature 07 metadata scrubber + optional password (DRY)

## Purpose

Edit PDFs directly: merge, split, delete pages, reorder, rotate, compress, sign,
watermark, password-protect, and annotate.

## Source scope (phased)

- **Phase 1 — our own PDFs:** edit PDFs created in-app; we still hold the rich
  page model, so edits are clean and high quality.
- **Phase 2 — external import:** import external PDFs from in-app storage or the
  **device Files picker** (system document picker). **Not** from email.

## Operations (build order A -> B -> C)

- **A · Organize:** merge, split, delete pages, reorder, rotate.
- **B · Protect/optimize:** password-protect existing PDFs (reuses Feature 07's
  encrypt pipeline), compress (a few quality levels).
- **C · Markup:** signature (draw + save a reusable signature, place/resize),
  highlight, freehand draw, text note, text watermark.
  - Shapes and preset stamps are **deferred** (KISS).

## Non-destructive & DRY

- Organize ops apply to our document/page model and re-export.
- Markup is stored as **annotation objects per page** (re-editable).
- Every output passes through the shared **metadata scrubber** and optional
  **password** from Feature 07.

## Engine (SOLID/KISS/DRY)

- Phase 1 builds on the existing generation pipeline + a PDF render/markup layer.
- Editing arbitrary **external** PDFs (Phase 2) may need a heavier/commercial
  engine — decided when we reach Phase 2, behind a `PdfEditor` interface (DIP) so
  Phase 1 is undisturbed.

## Out of scope

- Conversion to other formats (Feature 10); email import; OCR (Feature 08).

## Testing strategy (TDD/BDD first)

- **Unit:** merge/split page counts; delete/reorder/rotate correctness; compress
  reduces size within a quality bound; password required to open; annotations
  persist & re-edit; output is metadata-scrubbed.
- **BDD scenarios:**
  - *Given two in-app PDFs, when I merge them, then one PDF contains all pages in
    order.*
  - *Given a PDF, when I add a signature and save, then the signature appears at
    the placed position and the file is scrubbed.*
  - *Given a PDF, when I password-protect it, then opening it requires the
    password.*
  - *Given a PDF, when I rotate a page and re-export, then that page's orientation
    is changed.*

## Deliverable (user-testable)

**PDF editing** on in-app PDFs across three groups — organize
(merge/split/delete/reorder/rotate), protect (password/compress), and markup
(signature/highlight/freehand/note/watermark). **You can test it by** merging two
PDFs (one combined PDF, pages in order), adding a signature (placed correctly,
file scrubbed), password-protecting one (prompts on open), and rotating a page
(orientation changes after re-export).

## Acceptance criteria (each closed only by a passing test)

- [ ] Merge, split, delete, reorder, and rotate pages of in-app PDFs — *unit: page counts/order · BDD: merge*
- [ ] Compress and password-protect existing PDFs — *unit: size bound · BDD: open requires password*
- [ ] Add signature, highlight, freehand, note, watermark; annotations persist & re-edit — *unit/widget · BDD: signature*
- [ ] All outputs metadata-scrubbed; password reuses Feature 07's pipeline — *unit*
- [ ] External-PDF import (Phase 2) behind a `PdfEditor` interface, Phase 1 undisturbed — *unit: interface*

---

> **Definition of Done gate:** Per the Definition of Done in `00-overview-roadmap.md`, this feature is **not done** until every acceptance criterion above is mapped to a passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is run and observed green, quality gates pass, and the work is reviewed and double-checked. "Looks right" / "should pass" is not done.
