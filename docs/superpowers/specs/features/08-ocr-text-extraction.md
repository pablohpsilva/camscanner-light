# Feature 08 — OCR / Text Extraction

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 2 — OCR / text extraction
**Depends on:** Feature 05 (enhanced page)
**Feeds:** Feature 07 (searchable PDF text layer), Feature 02 (content search)

## Purpose

Read the text in scanned pages to: (a) make PDFs **searchable** (fulfills the
cross-cutting requirement via Feature 07's pluggable text layer), (b) let users
**copy/export** recognized text, and (c) power **library search by content**.
Target: 41+ languages including CJK.

## Engine (decision)

- **On-device only — no cloud, ever.** Documents never leave the phone.
- Tesseract-based with **downloadable language packs** (small app footprint; CJK
  packs are larger), behind an `OcrEngine` interface (DIP) — another on-device
  engine could be swapped in, but cloud is excluded by requirement.

## Processing model

- Runs **automatically in a background isolate** after a page is enhanced/saved.
- Caches **text + word bounding boxes** on the page (boxes needed for the
  invisible PDF layer). OCR output is **derived data** keyed to the page —
  re-runnable, fits the non-destructive model.

## Language handling (smart, multi-language)

- **Smart auto-detection:** a script/language detection pass (e.g. Tesseract OSD
  or a fast first pass) selects the language pack(s).
- **Multi-language documents:** detect **all** scripts/languages present and run
  a **combined** pass (e.g. `eng+jpn`), loading multiple packs as needed. A page
  may legitimately mix languages.
- **Fallback:** device locale when detection is uncertain.
- **Override:** user can select one or several languages.
- Packs **download on demand** with a small prompt.

## Content-aware handling (prose vs. code/symbols)

- **Prose:** normal recognition.
- **Code / technical / symbol-heavy:** preserve layout, whitespace/indentation,
  punctuation, and the full symbol set; **disable dictionary autocorrection**
  (so `arr[i]++`, `==`, etc. aren't "corrected" into invalid text). A heuristic
  flags code-like blocks and switches them to a layout-preserving, no-dictionary
  mode. Best-effort (code OCR is inherently hard), but never actively corrupts.

## Outputs

- Invisible **searchable text layer** for PDFs (Feature 07).
- **Copy/export** recognized text (selectable text view + export as `.txt`).
- **Content-search index** for the library (Feature 02).

## Architecture (SOLID/KISS/DRY)

- `OcrEngine` + `LanguageDetector` interfaces (DIP); all heavy work off the UI
  thread; results cached per page.

## Out of scope

- Translation; manual text correction (later); any cloud processing.

## Testing strategy (TDD/BDD first)

- **Unit:** engine returns text + boxes for fixture images; detection picks the
  right pack(s) for Latin/CJK/mixed fixtures; results cache & re-run
  deterministically; `.txt` export matches recognized text; code fixtures keep
  symbols/indentation with no dictionary correction.
- **BDD scenarios:**
  - *Given a scanned English page, when OCR completes in the background, then the
    page's PDF text is selectable and it's found by content search.*
  - *Given a Japanese page, when auto-detection runs, then it selects the Japanese
    pack (downloading if needed) and recognizes the text.*
  - *Given a page mixing English and Japanese, when OCR runs, then both languages
    are recognized in the text and PDF layer.*
  - *Given a page containing source code, when OCR runs, then symbols and
    indentation are preserved and not autocorrected into invalid text.*
  - *Given a recognized page, when I tap copy/export text, then I get the
    extracted text.*

## Acceptance criteria

1. OCR runs automatically on-device in the background after scanning.
2. Auto-detection handles single- and multi-language pages, loading packs on
   demand; user can override languages.
3. Code/symbol content is preserved (layout + symbols, no autocorrection).
4. OCR produces a searchable PDF layer, exportable text, and a content-search
   index.
5. No document data ever leaves the device.
6. All logic test-first; BDD scenarios pass.

---

> **Definition of Done gate:** Per the Definition of Done in `00-overview-roadmap.md`, this feature is **not done** until every acceptance criterion above is mapped to a passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is run and observed green, quality gates pass, and the work is reviewed and double-checked. "Looks right" / "should pass" is not done.
