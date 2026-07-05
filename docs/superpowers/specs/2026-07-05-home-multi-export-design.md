# Multi-select export from the documents (home) screen

**Date:** 2026-07-05
**Status:** Approved — ready for implementation plan

## Problem

The documents/home screen (`HomeScreen`) can export/share a **single** document as a
PDF (per-row overflow menu → Share → `repo.exportPdf(id)` → `ShareChannel.share`).
There is no way to select several documents at once and export them together. Users
want to pick one or more documents from the list and export them as PDF — either
**merged into one PDF** or as **separate PDFs bundled in a zip**.

## Existing infrastructure (reused, not rebuilt)

- `PdfBuilder.build(List<PageImage>)` — composes *any* list of pages into one PDF.
  A merged PDF across documents is just the concatenation of their page lists.
- `DocumentRepository.exportPdf(id)` — single-document PDF to a temp file (already
  used by the home screen's per-row Share).
- `ShareChannel.share(List<String> paths, {subject})` — already multi-file capable;
  `PageViewerScreen._exportAllImages` already shares a list of files.
- `archive` 4.0.9 is present transitively (via `image`); promoted to a direct dep
  for zipping.
- `getDocumentPages(id)` — pages with absolute paths, position order.

Nothing about the native/plugin layer blocks this; only a UI selection layer, a
choice dialog, two repo methods, and a zip helper are missing.

## Decisions (locked)

- **Enter selection:** long-press a document row.
- **"Separate files" means:** one PDF per document, bundled into a single `.zip`
  (zip is the *only* separate option — no loose multi-file share).
- **Choice prompt:** shown only when **2+** documents are selected. A single
  selection exports one PDF directly (no dialog).
- **Repo shape:** Approach B — symmetric `exportCombinedPdf` and
  `exportSeparatePdfs` methods on the repository interface.

## Design

### 1. Selection mode — `_HomeScreenState`

- New state: `Set<int> _selectedIds`; derived `bool get _selectionMode => _selectedIds.isNotEmpty`.
- **Long-press** a row → add its id (enters mode). **Tap** in selection mode toggles
  the row; opening the document is suppressed while selecting.
- The normal app bar is replaced by a **contextual app bar** when `_selectionMode`:
  - leading close (✕, `Key('selection-close')`) → clears `_selectedIds`.
  - title = `"$N selected"`.
  - action **Export** (`Icons.ios_share`, `Key('selection-export')`) → `_exportSelected()`.
- Entering search exits selection first (mutually exclusive modes).
- Selection is cleared on: close button, and after a **successful** export.

### 2. `DocumentsListView`

New optional params (backward compatible — omitted params preserve today's behavior
and existing tests):
- `Set<int> selectedIds` (default `const {}`)
- `bool selectionMode` (default `false`)
- `ValueChanged<DocumentSummary>? onToggleSelect`
- `ValueChanged<DocumentSummary>? onLongPress`

Per row:
- `onLongPress` wired to the `ListTile`.
- When `selectionMode`: `onTap` routes to `onToggleSelect` (not `onOpen`); the row
  shows a checkbox state (`Key('document-check-<id>')`, checked when
  `selectedIds.contains(id)`); the overflow menu is hidden.
- When not selecting: unchanged (thumbnail, tap-to-open, overflow menu).

### 3. Export-choice dialog

`showExportChoiceDialog(BuildContext) -> Future<MultiExportChoice?>` (mirrors
`showRenameDialog`/`showExportQualityDialog`), in
`lib/features/library/widgets/export_choice_dialog.dart`.

```dart
enum MultiExportChoice { merged, separateZip }
```

- **"Merge into one PDF"** (`Key('export-choice-merged')`) → `merged`.
- **"Separate PDFs (.zip)"** (`Key('export-choice-zip')`) → `separateZip`.
- Dismiss → `null` (no export).
- Shown only for 2+ selected.

### 4. Repository methods (`DocumentRepository` + `DriftDocumentRepository`)

```dart
/// Builds ONE PDF containing every page of every document in [documentIds]
/// (documents in list order; pages in position order) and returns it as a temp
/// file (same temp discipline as exportPdf). Throws [DocumentExportException]
/// when [documentIds] is empty or the combined result has no pages.
Future<File> exportCombinedPdf(List<int> documentIds);

/// Exports each document in [documentIds] as its own PDF (delegating to
/// exportPdf per id), returning the temp files in list order. Throws
/// [DocumentExportException] when [documentIds] is empty or any export fails.
Future<List<File>> exportSeparatePdfs(List<int> documentIds);
```

- `exportCombinedPdf`: gather `getDocumentPages(id)` for each id, concatenate, pass
  to the injected `pdfBuilder.build(...)`, write bytes to a temp file named from a
  generic base (e.g. `documents.pdf`). Reuses the same temp-dir + write helper as
  `exportPdf`.
- `exportSeparatePdfs`: `for (id in ids) files.add(await exportPdf(id));`.

### 5. `FileArchiver` — new injectable (matches `ShareChannel` pattern)

`lib/features/library/file_archiver.dart`:

```dart
abstract interface class FileArchiver {
  /// Zips [files] into a single temp .zip named [archiveName] and returns it.
  /// [entryNames] gives the in-zip filename per file (same length/order as
  /// [files]); the archiver de-duplicates collisions by suffixing " (2)", etc.
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames});
}
```

- `SystemFileArchiver` (the only file importing `archive`): reads each file, adds an
  `ArchiveFile`, `ZipEncoder().encode(archive)`, writes to a temp `.zip`.
- Entry names: sanitized `<docName>.pdf`, de-duplicated on collision.
- Added to `LibraryDependencies` (default `const SystemFileArchiver()`); `HomeScreen`
  passes `widget.libraryDependencies.archiver` into the handler. Faked in tests.
- Promote `archive: ^4.0.9` to a direct dependency in `pubspec.yaml`.

### 6. Home-screen orchestration — `_exportSelected()`

Guarded by the existing `_sharing` flag (prevents double-tap re-entry).

- **1 selected:** `exportPdf(id)` → `share([pdf.path], subject: name)`.
- **2+ selected:** `showExportChoiceDialog`; on `null` return.
  - **merged:** `exportCombinedPdf(ids)` → `share([pdf.path], subject: "$N documents")`.
  - **separateZip:** `exportSeparatePdfs(ids)` → build `entryNames` from the selected
    documents' names → `archiver.zip(files, archiveName: 'documents.zip', entryNames: …)`
    → `share([zip.path])`.
- Ordering: documents follow the **currently displayed** (sorted) list order.
- Any exception → existing `"Couldn't share"` snackbar (`ScaffoldMessenger`).
- On success: clear `_selectedIds` (exits selection mode).

### Error handling & edge cases

- Empty `documentIds` or a combined result with zero pages →
  `DocumentExportException` → snackbar.
- A document with no pages inside a combined export: contributes no pages; only an
  all-empty combined result throws. (In practice deleting a document's last page
  deletes the document, so empty documents effectively don't occur.)
- Double-tap Export while an export is in flight → ignored via `_sharing`.
- Zip entry-name collisions (two docs same name) → de-duplicated with a numeric
  suffix.
- Everything stays on-device / in temp; nothing is written to the backed-up store.

## Testing (TDD/BDD)

- `test/features/library/export_combined_pdf_test.dart` — page count & order across
  multiple docs; empty input and no-pages throw; output is a temp `.pdf`.
- `test/features/library/export_separate_pdfs_test.dart` — one file per id in order;
  empty input throws; temp files.
- `test/features/library/file_archiver_test.dart` — `SystemFileArchiver` zips N
  files, correct entry names, collision de-dup, output is a temp `.zip`, entries
  round-trip (decode) to the original bytes.
- `test/features/library/home_multi_export_test.dart`:
  - long-press enters selection; title shows `"N selected"`; close clears it.
  - tap toggles a checkbox; opening is suppressed while selecting.
  - 1 selected → Export exports one PDF and shares it (no dialog).
  - 2+ selected → Export shows the choice dialog.
  - merged path → calls `exportCombinedPdf(ids)` then `share([pdf])`.
  - zip path → calls `exportSeparatePdfs(ids)`, then `archiver.zip(...)`, then
    `share([zip])`.
  - double-tap Export launches only one export.
  - a failing export/zip/share shows `"Couldn't share"`.
  - selection cleared after a successful export.
- Fakes: extend `FakeDocumentRepository` with `exportCombinedPdf` /
  `exportSeparatePdfs` (recording ids); add `FakeFileArchiver` (recording call +
  returning a stub `.zip` file) in `test/support/fake_library.dart`.

## Out of scope (YAGNI)

- Export quality picker for the multi-select flow (uses `ExportQuality.original`,
  matching the current home-screen single-doc Share). Can be added later.
- Merging into a *persisted* document (that's the existing `mergeInto`); this feature
  only produces transient export artifacts.
- Password-protected combined PDF, fax/link-share of the bundle.
