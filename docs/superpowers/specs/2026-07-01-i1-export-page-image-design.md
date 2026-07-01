# I1 Export Page as Image — Design Spec

**Date:** 2026-07-01
**Status:** Approved
**Step:** I1 — Export page as image (Feature 10 / PDF conversion, the `page → JPG` slice)
**Depends on:** B1–B3 (pages stored as JPGs), G-series (enhanced/flat images), shared metadata scrubber — all gated
**Feeds:** Feature 12 (sharing/printing the exported file)

---

## Goal

From the `PageViewerScreen`, the user can export the page they are viewing as a
standalone **JPG image file** on the device. The exported file is
**metadata-scrubbed** (privacy) and **nothing leaves the device** (pure local
file IO — no network). A confirmation is shown.

Works identically on iOS and Android: pure Dart (file IO + the existing byte-level
JPEG scrubber), no platform channels.

---

## Scope & boundary (spec-faithful)

Feature 10 covers `image → PDF`, `PDF → JPG`, a `Converter` interface, and
metadata scrubbing. **I1 is only the `export current page as image` slice.** The
other F10 slices (image→PDF, bulk PDF→JPG, a dedicated `Converter` abstraction)
are separate, not-yet-scheduled roadmap items and are **out of scope here** (YAGNI).

**Sharing / saving to the device gallery is Feature 12** and is explicitly out of
scope (there is no `share_plus`/gallery dependency, and the privacy posture keeps
this on-device). I1 mirrors the established `exportPdf` pattern: **produce the file
in app storage and confirm**; getting it out of the app is F12.

Because a page is already a JPG on disk, "export" = read the page's display image,
pass it through the scrubber (spec-mandated: "every converted file passes through
the metadata scrubber"), and write it to a distinct export path.

---

## Architecture

Four focused changes, each single-responsibility:

| Layer | Change |
|---|---|
| `DocumentFileStore` | Add `imageExportRelativeFor(docId, position)` → `documents/<id>/page_<n>_export.jpg` |
| `DocumentRepository` (interface) | Add `Future<File> exportPageAsImage(int documentId, int position)` |
| `DriftDocumentRepository` | Implement: read display image → scrub → write export file → return it |
| `FakeDocumentRepository` (test support) | Implement (record call + throw flag) |
| `PageViewerScreen` | Overflow-menu item "Export as image" → `_exportPageAsImage` handler + SnackBar |

**Why the existing `DocumentRepository` seam (not a new `Converter` interface):**
`exportPdf` already lives on `DocumentRepository` — the established DIP boundary
the widget layer depends on. Adding `exportPageAsImage` beside it is the most
consistent, efficient choice. A dedicated `Converter` interface only earns its
keep once image→PDF / bulk PDF→JPG land (separate slices); building it now would
be speculative abstraction (YAGNI). This decision is revisitable without churn:
the method can later delegate to a `Converter` behind the same repository seam.

---

## API

### `DocumentRepository` addition

```dart
/// Exports the page at [position] of [documentId] as a standalone JPG on device.
/// Reads the page's display image (the perspective-flattened derivative when
/// present, else the original capture), passes the bytes through the metadata
/// scrubber (privacy — the file is metadata-clean), writes it to
/// `documents/<id>/page_<position>_export.jpg`, and returns the file. Nothing
/// leaves the device.
///
/// Throws [DocumentExportException] when the page row/file is missing or the
/// scrub fails.
Future<File> exportPageAsImage(int documentId, int position);
```

### `FakeDocumentRepository` additions

```dart
final bool throwOnExportImage;        // new ctor param, default false
int? lastExportedImagePosition;       // recorded on success
```

Returns a `File` under `Directory.systemTemp` (no real IO), like the fake's
`exportPdf`; records the position; throws `DocumentExportException` when
`throwOnExportImage`.

### `DocumentFileStore` addition

```dart
String imageExportRelativeFor(int docId, int position) =>
    'documents/$docId/page_${position}_export.jpg';
```

---

## Drift Implementation

```
row = SELECT * FROM pages WHERE documentId=? AND position=?   (getSingleOrNull)
if row == null: throw DocumentExportException('exportImage failed: no page (id, pos)')

// Display image: flat derivative if present, else the original capture.
srcRel = row.flatRelativePath ?? row.relativeImagePath
try {
  bytes    = read _fileStore.absoluteFor(srcRel)               // may throw (file missing)
  scrubbed = _scrubber.scrub(bytes)                            // spec: pass through scrubber
  rel      = _fileStore.imageExportRelativeFor(documentId, position)
  write scrubbed to rel
  return _fileStore.absoluteFor(rel)
} catch (e) {
  throw DocumentExportException('exportImage failed: $e')
}
```

- Uses the SAME `_scrubber` field the repo already holds (injectable — tests can
  spy). The stored page image is already scrubbed at capture, so this re-scrub is
  defensive/idempotent, but it satisfies the spec's "every converted file passes
  through the metadata scrubber" and guards derivatives (the warp/flat output is
  written without an explicit scrub today).
- No network, no isolate needed (scrub is a fast byte-level pass; the file is a
  single already-encoded JPG). Runs on the platform thread; acceptable for one
  image (unlike PDF build which uses the pdf package). If profiling ever shows
  jank on huge images, moving the scrub to `compute()` is a drop-in follow-up —
  not needed now.

---

## `PageViewerScreen` UX

Add a third item to the existing page overflow menu (`page-viewer-page-menu`,
which already has Retake / Delete page), acting on the current page
(`_pages![_current]`):

```dart
PopupMenuItem<String>(
  value: 'export-image',
  key: Key('page-viewer-export-image'),
  child: Text('Export as image'),
),
```

`onSelected` gains `if (v == 'export-image') unawaited(_exportPageAsImage());`.

Handler:

```dart
Future<void> _exportPageAsImage() async {
  final pages = _pages;
  if (pages == null || pages.isEmpty) return;
  final page = pages[_current];
  try {
    await widget.repository.exportPageAsImage(widget.documentId, page.position);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Page saved as image')),
    );
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't export image")),
    );
  }
}
```

Consistent with the viewer's existing SnackBar confirmations (rename/delete). No
new screen: the page image is already visible in the viewer, so a separate image
preview would be redundant (unlike PDF, which needs `PdfPreviewScreen`).

---

## Error Handling

| Failure | Behavior |
|---|---|
| Page row / source file missing | `DocumentExportException` → SnackBar "Couldn't export image" |
| Scrub fails (`MetadataScrubException`) | wrapped in `DocumentExportException` → SnackBar |
| Export write fails (IO) | wrapped in `DocumentExportException` → SnackBar |

The viewer stays put on failure (no navigation), matching the other viewer actions.

---

## Testing (acceptance-criteria mapping)

Spec-10 criteria relevant to I1: *export a page as a JPG on-device · all exported
files metadata-scrubbed, nothing leaves the device.*

**Unit — `DriftDocumentRepository`** (`export_page_image_test.dart`, real
`NativeDatabase.memory()`):
- Exports a page → a JPG file exists at `documents/<id>/page_1_export.jpg`, valid
  JPEG header (`FFD8`).
- **Metadata-scrubbed:** seed a page whose on-disk image is the EXIF-laden fixture
  (`test/fixtures/exif_sample.jpg`, written directly), export it, and assert the
  exported bytes contain **no** EXIF APP1 marker (`Exif\0\0` absent) — proving the
  export passes through the scrubber. (Mirror the existing `JpegExifScrubber` test's
  marker assertion.)
- Uses the **flat** image when `flatRelativePath` is set (export a page with a flat
  → exported bytes equal `scrub(flat file)`), else the original.
- Missing page (`position` absent) → throws `DocumentExportException`.
- No network: pure local IO by construction (documented; no network client exists
  in the path).

**Widget — `PageViewerScreen`** (`FakeDocumentRepository`):
- Overflow menu exposes "Export as image".
- Selecting it calls `exportPageAsImage(documentId, currentPosition)` (fake records
  `lastExportedImagePosition`), then shows the "Page saved as image" SnackBar.
- `throwOnExportImage` → shows "Couldn't export image" SnackBar; viewer stays.

**BDD — `i1_export_image.feature`** → generated on-device test + step defs:
- *Given a saved document open in the viewer, when I export the page as an image,
  then I see the "Page saved as image" confirmation.*
  (Reuses the launch → scan → capture → open flow; new steps
  `i_export_the_page_as_an_image` and `i_see_the_image_export_confirmation`.)

**Verify harness — `scripts/verify/i1.sh`** (mirrors `h5.sh`): static asserts
(`exportPageAsImage` in interface + drift, `imageExportRelativeFor` in file store,
menu item + handler in viewer, feature + generated test), host suite green, analyze
clean, on-device BDD.

---

## Out of Scope (YAGNI)

- Sharing / save-to-gallery / print (Feature 12).
- Bulk "export all pages as images", image→PDF, PDF→JPG rendering, a dedicated
  `Converter` interface (other F10 slices, not scheduled).
- PNG or format choice — JPG only (documents are JPGs; matches the stored format).
- A separate image-preview screen (the page is already shown in the viewer).
