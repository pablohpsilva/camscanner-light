# Q1 — Compress / export quality (design)

**Date:** 2026-07-02
**Status:** Approved (design)
**Sub-project:** cross-cutting (roadmap Feature 07 PDF export / Feature 10 conversion — "compress")
**Depends on:** C1/H5 (PDF generation), I1/J1 (image export), O3 (searchable text layer),
the always-on metadata scrubber, the `image` package (`^4.5.0`, pure Dart).

## Purpose

Let the user shrink the file size of what they export — the generated PDF and
single/all image exports — by choosing a **quality preset at export time**.
Phone scans are often 3000–4000 px JPEGs; a Medium/Low preset that re-encodes
and downscales cuts the shared/emailed file to a fraction of the original, while
**searchability is fully preserved** (the OCR text layer is stored separately
and is resolution-independent). `Original` keeps today's exact lossless output.

## Scope

Applies to the three explicit export actions:

- **PDF export** (`exportPdf`, the toolbar button),
- **single image export** (`exportPageAsImage`, overflow menu),
- **all-images export** (`exportAllPagesAsImages`, overflow menu).

**`print` and `protect` stay at `Original`** — printing wants fidelity, and
`protect` already shows a password dialog (chaining a second dialog is poor UX).
The seam is built so either could opt in later with one extra argument.

The stored originals/derivatives are **never** modified — compression happens
only on the copy that leaves the app. This upholds the "high-quality scan"
promise; the archive stays lossless.

## UX

- Tapping any of the three export actions first opens a **quality dialog**
  (`export-quality-dialog`) listing four options, each with a label + one-line
  description (no computed byte estimate — that would require re-encoding every
  page up front):
  - **Original** — *full quality, largest file*
  - **High** — *high quality*
  - **Medium** — *good for email*
  - **Low** — *smallest file*
- A **dialog** (not a bottom sheet) to match the app's established picker
  convention — every existing chooser (`merge_picker_dialog`, `password_dialog`,
  `rename_dialog`, the delete confirmations) is a `showDialog`; there are zero
  bottom sheets in the app.
- Choosing an option proceeds with that quality; **dismissing** the dialog
  (tap-scrim / back) cancels — no export, no spinner.
- **A progress spinner covers the compression.** `_exporting` currently wraps
  only `_exportPdf`; this feature extends it to **all three** export handlers so
  the existing spinner + disabled-actions state uniformly covers the re-encode
  time (which now matters for image export too — worst case all-images
  re-encodes every page). No new progress UI is added; the existing flag is
  reused.
- Identical on iOS and Android (Material dialog, pure Dart pipeline).

### Existing confirmations (unchanged — the picker only precedes them)

The three actions already surface distinct completions; the quality dialog is
inserted *before* each, nothing else changes:

| Action | Existing completion |
|---|---|
| PDF export (`_exportPdf`) | **navigates to `PdfPreviewScreen`** (pdfx) — no snackbar |
| single image (`_exportPageAsImage`) | `'Page saved as image'` snackbar |
| all images (`_exportAllImages`) | `'Exported N image(s)'` snackbar |

This is why the **BDD targets image export** (deterministic snackbar, no pdfx,
no share) and the **PDF-path widget test pumps rather than settles** (the
pushed pdfx preview opens a real channel that would hang `pumpAndSettle`) — see
Testing.

## Preset table (single source of truth)

| Preset     | `jpegQuality` | `maxDimension` (long edge) | Re-encode? |
|------------|---------------|----------------------------|------------|
| `original` | — (null)      | — (null)                   | no — verbatim bytes |
| `high`     | 85            | none (null)                | yes |
| `medium`   | 75            | 2200 px                    | yes |
| `low`      | 60            | 1600 px                    | yes |

Downscale **never upscales** (only shrinks when the long edge exceeds the cap;
aspect ratio preserved). These numbers live only in the `ExportQuality` enum.

## Architecture

New files under `lib/features/library/export/`:

### `ExportQuality` (enum) — `export/export_quality.dart`
```dart
enum ExportQuality {
  original(jpegQuality: null, maxDimension: null,
      label: 'Original', description: 'Full quality, largest file'),
  high(jpegQuality: 85, maxDimension: null,
      label: 'High', description: 'High quality'),
  medium(jpegQuality: 75, maxDimension: 2200,
      label: 'Medium', description: 'Good for email'),
  low(jpegQuality: 60, maxDimension: 1600,
      label: 'Low', description: 'Smallest file');

  const ExportQuality(
      {required this.jpegQuality,
      required this.maxDimension,
      required this.label,
      required this.description});
  final int? jpegQuality;
  final int? maxDimension;
  final String label;
  final String description;

  bool get reencodes => jpegQuality != null;
}
```

### `ImageCompressor` (DIP seam) — `export/image_compressor.dart`
```dart
abstract interface class ImageCompressor {
  /// Returns re-encoded JPEG bytes for [quality], or the input bytes
  /// verbatim when [quality] does not re-encode (ExportQuality.original).
  Future<Uint8List> compress(Uint8List jpegBytes, ExportQuality quality);
}
```

**`ImageLibraryCompressor implements ImageCompressor`** (production, pure Dart) —
follows the **canonical re-encode sequence used everywhere else in this codebase**
(`auto_enhancer`, `bw_enhancer`, `color_enhancer`, `grayscale_enhancer`,
`perspective_warper`, `coons_warper`, `filter_picker_strip`):

1. If `!quality.reencodes` → return `jpegBytes` unchanged (no decode).
2. `decode = img.decodeImage(jpegBytes)` wrapped in try/catch — the `image`
   package **throws** on some malformed inputs (the K1 lesson), not just returns
   null. On null/throw → **fall back to `jpegBytes` verbatim** so an export never
   fails on a weird page (our inputs are our own JPEGs, so this is a crash-guard).
3. `oriented = img.bakeOrientation(decode)` — **mandatory.** `encodeJpg` strips
   EXIF (including Orientation), so pixels must be baked upright first, exactly as
   every other re-encode path does. Without this a stored original carrying a real
   Orientation tag would export rotated wrong.
4. If `maxDimension != null` **and** `max(width, height) > maxDimension`,
   downscale so the **long edge** equals `maxDimension`: pass **only** the
   long-edge dimension to `img.copyResize` (width when landscape/square, height
   when portrait) and let the package derive the other side — this preserves
   aspect exactly with no manual rounding. Use `interpolation:
   img.Interpolation.average` for a clean downscale (avoids the default
   nearest-neighbour aliasing). Never upscale — skip the resize when the long
   edge is already ≤ cap.
5. `return img.encodeJpg(resized, quality: quality.jpegQuality!)`.

### `ExportQualityDialog` — `export/export_quality_dialog.dart`
`Future<ExportQuality?> showExportQualityDialog(BuildContext context)` — a
`showDialog` (mirroring `merge_picker_dialog`) presenting the four options as
tappable tiles (label + description); returns the chosen `ExportQuality` or
`null` on dismiss. Keys: `export-quality-dialog`, `export-quality-original`,
`export-quality-high`, `export-quality-medium`, `export-quality-low`.

## Wiring into the pipeline

### `PdfBuilder.build` — `pdf/pdf_builder.dart`
- Inject `final ImageCompressor compressor` (default `const ImageLibraryCompressor()`).
- Add `ExportQuality quality = ExportQuality.original` to `build(...)` (keep the
  existing `bool compress` — that is the *PDF-structure* deflate flag, unrelated
  to image quality; documented distinctly).
- Per page: `bytes = await compressor.compress(rawBytes, quality)` →
  `image = pw.MemoryImage(bytes)` → **overlay computed from `image.width/height`
  of the (possibly downscaled) embedded image**. Because OCR boxes are normalized
  0–1 and the baked frame equals the frame `pw` already renders/aligns to, the O3
  text layer stays aligned at any resolution.

### `DocumentRepository` (interface + Drift + fake)
Add an optional `{ExportQuality quality = ExportQuality.original}` to:
- `exportPdf(int documentId, {ExportQuality quality})`
- `exportPageAsImage(int documentId, int position, {ExportQuality quality})`
- `exportAllPagesAsImages(int documentId, {ExportQuality quality})`

Default `original` = current behavior → `print`/`protect` callers unchanged.

- `exportPdf` forwards `quality` to `_pdfBuilder.build`.
- `exportPageAsImage` unifies to **`compress(raw, quality) → scrub → write`**:
  at `original`, `compress` returns verbatim so the output is byte-identical to
  today; at a lower preset the re-encoded bytes carry no EXIF and `scrub` is a
  harmless idempotent privacy pass (net privacy equal-or-better, no regression).
- `exportAllPagesAsImages` passes `quality` through its per-page loop.
- Drift repo injects `final ImageCompressor _compressor`
  (default `const ImageLibraryCompressor()`); the `PdfBuilder` it uses defaults
  the same const impl, so no composition-root wiring is required.

### Page viewer — `page_viewer_screen.dart`
`_exportPdf`, `_exportPageAsImage`, `_exportAllImages` each:
1. `final q = await showExportQualityDialog(context);` (before touching `_exporting`).
2. `if (q == null || !mounted) return;` (Cancel or unmounted after the await →
   no-op; the `!mounted` guard matches the codebase convention, e.g. `_protect`).
3. Set `_exporting = true`, run the export with `quality: q`, clear `_exporting`
   in a `finally` (guarded by `mounted`). `_exportPdf` already does this;
   `_exportPageAsImage` and `_exportAllImages` **gain** the same wrap so the
   spinner + disabled-actions state covers their compression time too. (Clearing
   in `finally` avoids the perpetual-spinner trap — see the async-loading memory.)

## Data flow
```
export action ─▶ showExportQualityDialog ─▶ quality (null = cancel → no-op)
   └─ repo.exportPdf(docId, quality: q)
        └─ pdfBuilder.build(pages, quality: q)
             └─ per page: compressor.compress(bytes, q)   // decode→bake→resize→encode
                          → pw.MemoryImage → overlay(from embedded dims)
   ─▶ existing temp-file + share / snackbar path
```
(Image-export flows: `repo.exportPageAsImage/exportAllPagesAsImages(…, quality: q)`
→ `compress → scrub → write` → existing share/snackbar path.)

## Error handling
- Dialog dismissed → no-op (no export, no spinner).
- Compressor decode failure → verbatim fallback (export still succeeds).
- Existing `DocumentExportException` → existing "Couldn't export…" snackbar path,
  unchanged.

## Testing strategy (TDD/BDD first)

**Unit (host — `image` pkg is pure Dart):**
- `ImageLibraryCompressor.compress`:
  - a large real JPEG at `low` → **fewer bytes AND smaller max dimension** than
    the input;
  - at `original` → **byte-identical** to input (identity, no decode);
  - a small image (long edge < cap) at `low` → **dimensions unchanged** (no
    upscale);
  - malformed input at `low` → returns the input **verbatim** (fallback, no throw);
  - an input with a non-trivial EXIF Orientation → output has **baked pixels**
    (Orientation applied; decoding the output gives the oriented dimensions).
- `ExportQuality` preset values pinned (guards against accidental drift).
- `PdfBuilder.build`:
  - `quality: low` PDF is **smaller** than `quality: original` for a large page;
  - with `OcrPdfTextLayer` + a seeded page that has OCR boxes, the `low` PDF
    **still contains the searchable text** (grep with `compress: false`) **and**
    a representative word box maps to a **sane in-bounds position** — proves O3
    alignment survives bake+downscale.
- Repository: `exportPageAsImage(low)` file **smaller** than `original`;
  `exportPdf(low)` file **smaller** than `original`; both still valid.

**Widget (host):**
- `ExportQualityDialog`: shows four options; tapping one returns that
  `ExportQuality`; dismissing returns `null`.
- Page viewer **image export** (deterministic snackbar path): tapping
  `export-image` → dialog → **Medium** calls the fake repo's
  `exportPageAsImage(docId, pos, quality: ExportQuality.medium)` and shows
  `'Page saved as image'`; dismissing the dialog calls **nothing**. Same shape
  for `export-all-images` (`'Exported N image(s)'`).
- Page viewer **PDF export** (pdfx navigation path): tapping `page-viewer-export`
  → dialog → **Medium**, then `pump()` (NOT `pumpAndSettle` — the pushed
  `PdfPreviewScreen` opens the real pdfx channel and would hang settle; mirrors
  `page_viewer_screen_test.dart:150`), asserting the fake recorded
  `exportPdf(docId, quality: ExportQuality.medium)` and `PdfPreviewScreen` is
  present. Dismissing the dialog calls nothing and does not navigate.
- No `Image.file` host hang (non-loadable page paths).

**BDD (on-device Samsung RZCY51D0T1K) — image export path:** reuses the existing
`i_export_the_page_as_an_image` and `i_see_the_image_export_confirmation` step
defs, with one new step for the quality choice —
- *Given the app launched, when I scan and accept a page, open the document,
  export the page as an image, and choose the Medium export quality, then I see
  the image export confirmation.*
  Uses the **real** repository, so real compression (bake + downscale + encode)
  runs on-device; the `'Page saved as image'` snackbar is asserted (no share, no
  pdfx). The chosen-quality *value* is asserted by the host widget test above,
  not the BDD.

**On-device deterministic:** seed a 1-page doc whose image is large; assert
`exportPdf(quality: low)` bytes `<` `exportPdf(quality: original)` bytes
(compression works on-device).

## Cross-platform

`image` package + `showDialog` are pure Dart / standard Flutter. No
platform channels, no per-OS branching.

## Deliverable (user-testable)

Open any multi-page document, tap **Export** (PDF), pick **Low** in the dialog,
and share/save — the resulting PDF is markedly smaller than the same document
exported at **Original**, opens correctly (right orientation), and its text is
still selectable/searchable. The same picker appears for "Export as image" and
"Export all as images".

## Acceptance criteria

- [ ] `ExportQuality` enum with the four presets and exact preset values *(unit)*
- [ ] `ImageCompressor` seam + `ImageLibraryCompressor` following
      decode→bakeOrientation→copyResize→encodeJpg *(unit)*
- [ ] `original` returns verbatim bytes (identity) *(unit)*
- [ ] downscale never upscales; aspect preserved *(unit)*
- [ ] malformed input falls back to verbatim (no throw) *(unit)*
- [ ] baked orientation on re-encode *(unit)*
- [ ] `PdfBuilder.build(quality)` — `low` smaller than `original` *(unit)*
- [ ] O3 searchable text preserved + a box stays in-bounds after bake+downscale *(unit)*
- [ ] `exportPdf` / `exportPageAsImage` / `exportAllPagesAsImages` honor `quality`
      (interface + Drift + fake); default `original` unchanged *(unit)*
- [ ] image-export path is `compress → scrub → write` *(unit)*
- [ ] `ExportQualityDialog` returns the choice / null on dismiss *(widget)*
- [ ] image-export actions: dialog → quality passed through + snackbar; dismiss =
      no-op *(widget)*
- [ ] PDF-export action: dialog → quality passed through + `PdfPreviewScreen`,
      asserted with `pump()` (not settle); dismiss = no-op *(widget)*
- [ ] all three export handlers wrap the call in `_exporting` (spinner covers
      compression; cleared in `finally`) *(widget)*
- [ ] BDD scan → export page as image → choose Medium → image export
      confirmation, green on-device *(BDD)*
- [ ] on-device deterministic: `low` PDF bytes < `original` PDF bytes *(device)*
- [ ] `flutter analyze` clean; host suite green; `scripts/verify/q1.sh` passes
      under the independent verifier; plans index updated.

## Definition of Done

Per `../specs/00-overview-roadmap.md` Definition of Done and
`../VERIFICATION.md`: every acceptance criterion above closed by a passing,
double-checked test; `scripts/verify/q1.sh` exits 0 under an independent
adversarial verifier from a clean state; `.feature` BDD generated + green
on-device; deterministic device test green; `flutter analyze` clean;
`00-plans-index.md` updated.
