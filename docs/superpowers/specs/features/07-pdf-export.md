# Feature 07 — PDF Generation/Export

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** Feature 06 (document = ordered pages)
**Related:** Feature 08 (OCR text layer), Feature 09 (password on existing PDFs),
Feature 10 (PDF→other formats), Feature 12 (sharing)

## Purpose

Turn a document (ordered pages) into a **PDF** — the core promise of the product.
Output is **always a PDF**, for both single-page and multi-page documents (a
single-page document produces a one-page PDF, not an image).

## Scope

**In scope**
- Generate a single- or multi-page PDF from a document.
- Searchable text layer (pluggable; populated by OCR later).
- Always-on metadata scrubbing.
- Optional password (AES-256) at export.
- Save the PDF into the library.

**Out of scope**
- Converting PDFs to images or other formats (PDF→JPG/Word/etc.) — Feature 10.
- The OCR engine itself (Feature 08). Rich sharing/printing/fax (Feature 12).
- Editing existing PDFs (Feature 09).

## Output settings (KISS)

- Each PDF page uses its scanned page's **Original aspect ratio**.
- A **single sensible quality** tuned for OCR clarity vs. file size.
- No paper-size or quality-preset menus yet (YAGNI — add later only if needed).

## Searchable text layer (cross-cutting)

- Behind a pluggable `PdfTextLayer` interface.
- **Image-only until Feature 08**; once OCR exists, its text is injected as an
  **invisible layer** over each page with no rework — searchable PDFs become the
  default "whenever possible."

## Metadata scrubbing (cross-cutting, always-on)

- Every generated PDF passes through a single shared `MetadataScrubber` (DRY).
- Removes author, creator, producer, and device/creation metadata.

## Optional password

- AES-256 PDF encryption at export; one password field.
- Clear **"no recovery if forgotten"** warning. User-managed.

## Architecture (SOLID/KISS/DRY)

- `PdfBuilder` composes pages into a PDF.
- **Scrub** and **optional encrypt** are pipeline stages (SRP/DRY) every export
  passes through.
- Generation runs **off the UI thread** for large documents.

## Testing strategy (TDD/BDD first)

- **Unit:** correct page count & order; output contains **no personal metadata**
  (assert EXIF/author/producer absent); password-protected PDF **requires the
  password to open**; with a stub OCR text layer, PDF text is selectable.
- **BDD scenarios:**
  - *Given a 3-page document, when I export to PDF, then a 3-page PDF is saved
    with pages in order.*
  - *Given any exported PDF, then it contains no GPS/device/author metadata.*
  - *Given I set a password on export, when I open the PDF, then it prompts for
    that password.*
  - *Given OCR is available (stubbed), when I export, then the PDF text is
    selectable.*

## Acceptance criteria

1. Export a single- or multi-page document to a PDF saved in the library, pages
   in order, Original aspect.
2. Every generated PDF is metadata-scrubbed (no personal metadata).
3. Optional password encrypts the PDF and is required to open it.
4. A pluggable text-layer interface exists so OCR (Feature 08) injects a
   searchable layer with no rework.
5. Generation runs off the UI thread.
6. All logic test-first; BDD scenarios pass.
