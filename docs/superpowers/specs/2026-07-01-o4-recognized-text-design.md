# O4 — Recognized Text: view, copy, export `.txt` (design)

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 2 — OCR / text extraction (Feature 08)
**Depends on:** O1 (OcrEngine DIP + per-page `ocrText`/`ocrBoxes` persistence), O2
(real `MlKitOcrEngine`, auto-run after save), O3 (searchable PDF layer)
**Feeds:** Feature 02 (content search — a later slice)

## Purpose

OCR already runs automatically after every save and caches per-page text (O2),
and that text is embedded as an invisible selectable layer in exported PDFs
(O3). But **inside the app the recognized text is invisible** — the only way to
see or use it today is to export a PDF and open it in an external viewer.

This slice fulfills Feature 08's second output — *"copy/export recognized text
(selectable text view + export as `.txt`)"* — by surfacing each page's cached
text in-app, letting the user **select/copy** it and **export it as a `.txt`
file** via the share sheet.

## Scope

**In:**
- A **Recognized-text screen** for a single page: shows the page's cached
  `ocrText` as selectable text; Copy-all and Export-`.txt` actions.
- Entry point from the **page viewer** (per-page action).
- On-demand **"Recognize text"** action for pages whose OCR hasn't completed
  yet (or found nothing) — calls the existing `runOcr` and reloads.
- A repository method to materialize the page's text as a **temporary** `.txt`
  file for sharing (no persistent accumulation, mirroring the temp-PDF pattern).

**Out (later slices):**
- Content-search index / library search (Feature 02).
- Multi-language auto-detection & packs (O5); code-aware recognition (O6).
- Editing/correcting recognized text; translation.
- Whole-document (all pages concatenated) export — this slice is **per page**,
  consistent with the existing per-page "Export as image". A document-level
  "export all text" can be a trivial follow-up.

## UX

### Entry point
The page viewer's existing **per-page popup menu** (`page-viewer-page-menu`,
which already holds Retake / Delete page / Export as image) gains a **"View
text"** item (`page-viewer-view-text`). Rationale: recognized text is per-page
(each page has its own OCR), so it belongs with the other per-page actions;
the AppBar already carries four icons + the menu, so adding a fifth icon would
crowd it. Most efficient, consistent, and identical on iOS/Android.

### Recognized-text screen (`RecognizedTextScreen`)
- **AppBar:** title `"Text"`; actions **Copy** (`recognized-text-copy`,
  `Icons.copy`) and **Share** (`recognized-text-share`, `Icons.share`).
  Both are disabled while loading or when there is no text.
- **Body — text present:** the page text in a **`SelectableText`**
  (`recognized-text-body`) inside a scroll view with comfortable padding.
  `SelectableText` gives native selection + the platform's own copy handles on
  both iOS and Android for free.
- **Body — no text yet:** a centered empty state (`recognized-text-empty`)
  reading *"No text recognized on this page yet."* plus a **"Recognize text"**
  button (`recognized-text-run`) that calls `runOcr`, then reloads the page and
  shows the result (or, if OCR genuinely found nothing, a *"No text found"*
  message). A spinner (`recognized-text-loading`) shows while recognizing; the
  loading flag is cleared in a `finally` so a failure never spins forever
  (per the async-loading-flag lesson).
- **Copy:** copies the full text to the clipboard (`Clipboard.setData`) and
  confirms with a SnackBar *"Copied"*. Nothing leaves the device.
- **Share:** asks the repository for a temp `.txt` file, then opens the system
  share sheet via `share_plus`. On failure, a SnackBar *"Couldn't export
  text"*.

## Architecture

Follows the established seams; no new dependencies.

- **`DocumentRepository.exportRecognizedText(int documentId, int position) →
  Future<File>`** (new interface method):
  - Reads the page row's cached `ocrText`.
  - Throws `DocumentExportException` when the page row is missing **or** the
    page has no recognized text (null/empty/whitespace) — the UI only calls
    this when text is present, but the contract is defensive.
  - Writes the text (UTF-8) to a **temporary** file
    (`Directory.systemTemp.createTemp('txt_export')`, filename
    `<sanitized-document-name>_page_<position>.txt`), and returns the `File`.
    Temp, not persistent — mirrors `exportPdf`'s temp-file share so the app
    doesn't accumulate `.txt` files. A `.txt` carries no metadata, so no
    scrubbing pass is required.
  - Reuses the existing filename-sanitizer helper used by `exportPdf`.
- **`runOcr`** already exists on the interface (O1) — reused for the on-demand
  empty-state action; no change.
- **`RecognizedTextScreen`** (new widget): a `StatefulWidget` given
  `documentId`, `position`, `name`, an optional `initialText` seed, and the
  `repository`. It is **authoritative from the repository**: on init it loads
  `repository.getDocumentPages(documentId)`, finds the page by `position`, and
  renders that row's `ocrText`. The `initialText` seed (the value the page
  viewer already holds) renders instantly to avoid a spinner flash, but the
  init-load is the source of truth — this keeps the screen correct even when
  the caller's cached text is stale (e.g. after a prior on-demand `runOcr`).
  "Recognize text" calls `repository.runOcr(documentId, position)` then re-runs
  the same load, so freshly-cached text appears. Sharing is
  `SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject:
  name))`. The load/recognize loading flag is cleared in a `finally`.
- **Page viewer** wires the new menu item to push `RecognizedTextScreen` for
  the current page, passing `pg.ocrText` as `initialText`.

## Data flow

```
page saved ──(O2 auto)──▶ ocrText cached on page row
page viewer ──"View text"──▶ RecognizedTextScreen(initialText: pg.ocrText)
   ├─ text present ─▶ SelectableText ─▶ Copy (clipboard) | Share (repo temp .txt ─▶ share_plus)
   └─ empty ─▶ "Recognize text" ─▶ repo.runOcr ─▶ repo.getDocumentPages ─▶ update text
```

## Error handling

- `exportRecognizedText`: missing row / empty text / IO failure →
  `DocumentExportException`; the screen shows a SnackBar and stays put.
- On-demand `runOcr` failure (e.g. engine error): caught; loading flag cleared
  in `finally`; SnackBar *"Couldn't recognize text"*; screen stays usable.
- Share sheet dismissed by the user: not an error (share_plus resolves
  normally); no message.

## Testing strategy (TDD/BDD first)

**Unit (host `flutter test`):**
- `exportRecognizedText` writes a temp `.txt` whose contents equal the page's
  cached `ocrText`, with a sanitized `<name>_page_<n>.txt` filename, in the
  system temp dir (not under the documents dir).
- `exportRecognizedText` throws `DocumentExportException` when the page has no
  text, and when the page row does not exist.
- Uses a `NativeDatabase.memory()` Drift repo with a page whose `ocrText` is
  seeded (no OCR engine needed — text is read straight from the row).

**Widget (host `flutter test`):**
- Given `initialText`, `RecognizedTextScreen` shows a `SelectableText` with that
  text; Copy and Share actions are enabled.
- Copy places the text on the clipboard (assert via the mock clipboard channel)
  and shows the "Copied" SnackBar.
- Given empty `initialText`, the empty state + "Recognize text" button show;
  tapping it calls a fake repository's `runOcr` then `getDocumentPages` and the
  body updates to the returned text.
- The screen uses **no `Image.file`** (text only), so host widget tests don't
  hit the real-file decode hang.

**BDD (`.feature` → on-device):**
- *Given a scanned page with recognized text, when I open "View text", then I
  see the recognized text and can copy it and export it as a `.txt` file.*
- Authored as `apps/mobile/integration_test/o4_recognized_text.feature`,
  generated to `_test.dart`, step defs in `apps/mobile/test/step/`.

**On-device (Samsung RZCY51D0T1K + iOS where available):**
- Integration test: seed a page + `runOcr` with the real `MlKitOcrEngine`, open
  the screen, assert the recognized text renders and the temp `.txt` is
  produced.

## Cross-platform

`SelectableText`, `Clipboard`, `share_plus`, and `Directory.systemTemp` are all
first-class on iOS and Android. No platform channels or per-OS branching.

## Definition of Done

- `exportRecognizedText` on the interface + Drift impl, TDD-covered.
- `RecognizedTextScreen` + page-viewer wiring, widget-tested.
- `.feature` BDD generated and green on-device.
- `flutter analyze` clean; host suite green; `scripts/verify/o4.sh` passes
  under the independent verifier; plans index updated.
