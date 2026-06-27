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

## Acceptance criteria

1. User can merge, split, delete, reorder, and rotate pages of in-app PDFs.
2. User can compress and password-protect existing PDFs.
3. User can add signature, highlight, freehand, text note, and text watermark;
   annotations persist and re-edit.
4. All outputs are metadata-scrubbed; password reuses Feature 07's pipeline.
5. External-PDF import (Phase 2) sits behind a `PdfEditor` interface without
   disturbing Phase 1.
6. All logic test-first; BDD scenarios pass.
