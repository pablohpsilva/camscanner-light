# CamScanner-light — Overview & Roadmap

**Date:** 2026-06-27
**Status:** Living document

## Product

CamScanner-light is a document-scanning and document-management product. Its
promise: turn a phone into a scanner for high-quality, **searchable** PDFs, with
OCR, conversion, PDF editing, sync, and sharing. Target platforms: **iOS,
Android, and Web** (mobile-first; Web later).

## Architecture

- **Monorepo:** Nx with `@nxrocks/nx-flutter`. Flutter app at `apps/mobile`.
  Future `apps/web`, `apps/api`, and `libs/` are anticipated by the layout.
- **Mobile stack:** Flutter (iOS + Android first).
- See `2026-06-27-step-0-monorepo-foundation-design.md` for the foundation.

## Engineering rules (non-negotiable)

- **TDD/BDD first, always** — tests/specs before implementation.
- **SOLID, KISS, DRY** for every feature, class, component, and function.
- Small, single-purpose, well-bounded units with clear interfaces.

## Definition of Done (binding)

This is the contract for every feature, build step, class, component, and
function. **Nothing is "done", merged, or called complete until ALL of the
following hold and have been verified — not assumed:**

1. **Acceptance criteria ↔ tests (traceability):** every acceptance criterion in
   the feature's spec maps to at least one automated test (TDD: unit/widget) and,
   where it describes user-facing behavior, a **BDD scenario** (Given/When/Then).
   No criterion is verified by inspection alone — each must have a test that
   proves it.
2. **Tests written first:** tests and BDD scenarios are authored **before**
   implementation; red → green → refactor.
3. **All tests pass — observed:** the full relevant suite (unit, widget, BDD) is
   run and seen green. "Should pass" / "looks right" is **not** done.
4. **Every acceptance criterion checked off** against its passing test(s).
5. **Reviewed and double-checked:** code review **plus** an independent
   verification pass — commands run, output shown, nothing regressed. Evidence
   before any "done" claim.
6. **Quality gates clean:** `analyze`/lint pass; SOLID/KISS/DRY upheld.

If any of 1–6 is unmet, the work is **not done**. Each feature's "Acceptance
criteria" section is the checklist; each item is closed only by a passing,
double-checked test. This gate is referenced by every feature spec.

**Required spec format (every design doc):** each spec MUST contain a
**`Deliverable (user-testable)`** section — a concrete artifact the user can
exercise plus *how* to test it by hand — and an **`Acceptance criteria`** section
written as a **checkbox checklist**, where each item is phrased to be verifiable
and tagged with the test(s) that close it (e.g. *unit*, *widget*, *BDD*). A
checkbox is ticked only when its named test passes and the result is
double-checked. Step 0 and all 12 feature specs follow this format.

## Cross-cutting requirements

- **Searchable PDFs whenever possible:** every capture mode should ultimately
  produce a PDF with an invisible OCR text layer over the image, so documents
  are selectable/searchable. OCR arrives in Feature 08; PDF export (Feature 07)
  is designed with a **pluggable text layer** so searchable PDFs become the
  default with no rework. This raises the bar on capture quality.
- **Metadata scrubbing (security/privacy), always-on:** every file we write —
  exported/captured images and generated PDFs — must have personal/identifying
  metadata stripped. Images: remove EXIF (GPS, device make/model/serial,
  timestamps, software tags). PDFs: remove author, creator, producer, and
  device/creation metadata. Implemented as a single shared, testable metadata
  scrubber (DRY) that every export path passes through. Designed in Feature 07.
- **PDF password protection (optional):** users can encrypt a generated PDF with
  a password (standard PDF encryption, AES-256). Offered at export (Feature 07)
  and on existing PDFs (Feature 09). User-managed — no recovery if forgotten.

## Decomposition (sub-projects)

0. **Foundation** — monorepo + app scaffold *(Step 0, approved)*
1. **Core scan pipeline (MVP)** — Features 01–07 below
2. **OCR / text extraction** — Feature 08
3. **PDF editing** — Feature 09
4. **PDF conversion (server-side)** — Feature 10
5. **Accounts & cloud sync** — Feature 11
6. **Sharing, printing & fax** — Feature 12

Each sub-project / feature gets its own design doc, then plan, then build.

## Feature design docs

| # | Feature | Doc | Status |
|---|---------|-----|--------|
| 01 | Document scanning (capture) | `features/01-document-scanning.md` | Approved |
| 02 | Document library & management | `features/02-document-library.md` | Approved |
| 03 | Manual crop & perspective (corners + flatten) | `features/03-manual-crop-perspective.md` | Approved |
| 04 | Auto edge detection | `features/04-auto-edge-detection.md` | Approved |
| 05 | Scan enhancement (filters) | `features/05-scan-enhancement.md` | Approved |
| 06 | Multi-page documents | `features/06-multi-page-documents.md` | Approved |
| 07 | PDF export | `features/07-pdf-export.md` | Approved |
| 08 | OCR / text extraction | `features/08-ocr-text-extraction.md` | Approved |
| 09 | PDF editing | `features/09-pdf-editing.md` | Approved |
| 10 | PDF conversion | `features/10-pdf-conversion.md` | Approved |
| 11 | Accounts & cloud sync | `features/11-accounts-cloud-sync.md` | Deferred |
| 12 | Sharing, printing & fax | `features/12-sharing-printing-fax.md` | Approved |

## Atomic build roadmap (Sub-project 1)

Dependency-ordered build steps; each ends in something observable in the app.

- **A. Foundation shell:** A1 scaffold + empty Documents list & Scan button ·
  A2 camera preview · A3 capture photo to review screen
- **B. Persistence:** B1 save photo + document record · B2 list reads storage ·
  B3 page viewer
- **C. PDF:** C1 single-page PDF · C2 in-app PDF preview *(= walking skeleton)*
- **D. Library mgmt:** D1 rename · D2 delete · D3 sort
- **E. Manual crop:** E1 corner overlay · E2 perspective flatten · E3 re-edit
- **F. Auto edge detection:** F1 contour detection · F2 pre-fill corners ·
  F3 live overlay (stretch)
- **G. Enhancement:** G1 grayscale · G2 B&W · G3 color/auto · G4 picker UI
- **H. Multi-page:** H1 add pages · H2 thumbnail strip · H3 reorder ·
  H4 delete/retake · H5 multi-page PDF
- **I. Export & import:** I1 export image · I2 gallery import

## Flow (end-to-end, core pipeline)

capture (01) → auto-detect corners (04) → manual corner tweak (03) →
perspective-flatten (03) → enhancement (05) → page added to document (06) →
PDF export (07, searchable once 08 lands).
