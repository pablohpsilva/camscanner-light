# Share multiple documents as a `.zip` (zip-only rebuild)

**Date:** 2026-07-06
**Status:** Approved — ready for implementation plan
**Supersedes execution of:** `finish-multi-export` branch + `2026-07-05-home-multi-export-design.md`
(that attempt bundled multi-select + combined-PDF + zip + share and collided with an
unrelated boot hang; this rebuild is zip-only and strictly additive).

## Problem

The documents/home screen (`HomeScreen`) can export/share a **single** document as a
PDF (per-row overflow menu → Share → `repo.exportPdf(id)` → `ShareChannel.share`).
There is no way to select several documents and share them together. Users want to
pick multiple documents and share them as one **`.zip`** containing one PDF per
document.

Merging into a single combined PDF is explicitly **out of scope** for this rebuild
(may return as a follow-up).

## Why the previous attempt failed (and how this design avoids it)

The prior branch appeared to fail at four layers; the real causes were narrower:

1. **Boot hang** — collateral, NOT part of zipping. It is the known opencv-2.x
   native-assets + `NativeDatabase.createInBackground` trap (still latent on master
   at `drift/app_database.dart:119`). A hung boot makes zip/share *look* broken
   because the app never runs.
   → **Mitigation:** this feature is strictly additive and never touches the DB /
     isolate / native path. An explicit gate verifies the app still boots on both
     devices before "done". If a boot hang surfaces, it is the separate known issue
     (fix = open DB on root isolate), not this feature.
2. **Zip creation "failed on-device"** — the old `SystemFileArchiver` deflate-encoded
   every PDF fully in memory. `Directory.systemTemp` was NOT the problem (the whole
   app, including the working single-PDF and multi-image shares, uses it).
   → **Mitigation:** add PDFs **stored (no compression)** — PDFs are already
     compressed (JPEG pages), so deflate wastes CPU for ~0 gain and risks jank. Reuse
     the exact `Directory.systemTemp.createTemp(...)` discipline used everywhere else.
3. **Sharing the zip failed** — `XFile(path)` was passed with **no `mimeType`**, so a
   `.zip` attaches as `application/octet-stream` and is rejected by Mail/iOS. Images
   share fine today only because they carry a known UTI.
   → **Mitigation:** extend `ShareChannel.share` with an optional `mimeType`; the zip
     caller passes `application/zip`. Multi-file share itself already works
     (`page_viewer_screen.dart:243`).
4. **Tests / build_runner churn** — the branch changed too much at once.
   → **Mitigation:** smaller surface (zip only, no choice dialog, one repo method),
     TDD/BDD first, host tests before device verification.

## Existing infrastructure (reused, not rebuilt)

- `DocumentRepository.exportPdf(id)` — single-document PDF to a temp file
  (`Directory.systemTemp.createTemp('pdf_export')`), already used by the home screen's
  per-row Share. This is the proven, working export path.
- `ShareChannel.share(List<String> paths, {subject})` — already multi-file capable;
  `page_viewer_screen.dart` multi-image share proves the mechanism works.
- `getDocumentPages(id)` / `DocumentSummary` list — home screen already renders the
  sorted document list.
- `archive` (resolved transitively via `image`) — promoted to a direct dep for zipping.

## Decisions (locked)

- **Enter selection:** long-press a document row.
- **Export behavior (no dialog — merge mode dropped):**
  - **1 selected** → share that document's single PDF directly (zipping one file is
    pointless), `subject = <document name>`.
  - **2+ selected** → one PDF per document, bundled into a single `.zip`, shared with
    `mimeType: 'application/zip'`.
- **Ordering:** documents follow the currently displayed (sorted) list order.
- **Zip runs on the main isolate**, store (no compression). No `compute()` isolate
  (unnecessary; avoids the app's native-assets/isolate trap; `archive` is pure Dart).
- **Repo shape:** a single new method `exportSeparatePdfs(List<int>)` delegating to the
  existing `exportPdf`. No `exportCombinedPdf` (out of scope).
- **Share fix:** add optional `mimeType` to `ShareChannel.share` (backward compatible).

## Design

### 1. Selection mode — `_HomeScreenState`

- New state: `Set<int> _selectedIds`; derived `bool get _selectionMode => _selectedIds.isNotEmpty`.
- **Long-press** a row → add its id (enters mode). **Tap** in selection mode toggles the
  row; opening the document is suppressed while selecting.
- Normal app bar → **contextual app bar** when `_selectionMode`:
  - leading close (✕, `Key('selection-close')`) → clears `_selectedIds`.
  - title = `"$N selected"`.
  - action **Export** (`Icons.ios_share`, `Key('selection-export')`) → `_exportSelected()`.
- Entering search exits selection first (mutually exclusive modes).
- Selection is cleared on: close button, and after a **successful** export.

### 2. `DocumentsListView`

New optional params (backward compatible — omitted params preserve today's behavior and
existing tests):
- `Set<int> selectedIds` (default `const {}`)
- `bool selectionMode` (default `false`)
- `ValueChanged<DocumentSummary>? onToggleSelect`
- `ValueChanged<DocumentSummary>? onLongPress`

Per row:
- `onLongPress` wired to the `ListTile`.
- When `selectionMode`: `onTap` routes to `onToggleSelect` (not `onOpen`); the row shows
  a checkbox (`Key('document-check-<id>')`, checked when `selectedIds.contains(id)`); the
  overflow menu is hidden.
- When not selecting: unchanged (thumbnail, tap-to-open, overflow menu).

### 3. Repository method (`DocumentRepository` + `DriftDocumentRepository`)

```dart
/// Exports each document in [documentIds] as its own PDF (delegating to
/// exportPdf per id), returning the temp files in list order. Throws
/// [DocumentExportException] when [documentIds] is empty or any export fails.
Future<List<File>> exportSeparatePdfs(List<int> documentIds);
```

- Implementation: `for (id in ids) files.add(await exportPdf(id));` — reuses the working
  temp discipline. Empty `documentIds` → `DocumentExportException`.

### 4. `FileArchiver` — new injectable (mirrors the `ShareChannel` pattern)

`lib/features/library/file_archiver.dart`:

```dart
abstract interface class FileArchiver {
  /// Zips [files] into a single temp `.zip` named [archiveName] and returns it.
  /// [entryNames] gives the in-zip filename per file (same length/order as
  /// [files]); colliding names are de-duplicated with a numeric suffix.
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames});
}
```

- `SystemFileArchiver` (the only file importing `archive`): read each file's bytes, add
  an `ArchiveFile` **with no compression (store)**, `ZipEncoder().encodeBytes(archive)`,
  write to a temp `.zip` in `Directory.systemTemp.createTemp('zip_export')`.
- Entry names: sanitized `<docName>.pdf`, de-duplicated on collision (`" (2)"`, `" (3)"`, …).
- Added to `LibraryDependencies` (default `const SystemFileArchiver()`); `HomeScreen`
  passes `widget.libraryDependencies.archiver` into the handler. Faked in tests.
- Promote `archive` to a direct dependency in `pubspec.yaml`, pinned to the version
  already resolved transitively (no version bump).

### 5. `ShareChannel` — add optional `mimeType`

```dart
Future<void> share(List<String> filePaths, {String? subject, String? mimeType});
```

- `SystemShareChannel` applies `mimeType` to every `XFile` it creates. `null` preserves
  today's behavior (all existing callers unchanged).
- The zip caller passes `mimeType: 'application/zip'`.

### 6. Home-screen orchestration — `_exportSelected()`

Guarded by the existing `_sharing` flag (prevents double-tap re-entry).

- **1 selected:** `exportPdf(id)` → `share([pdf.path], subject: name)`.
- **2+ selected:** `exportSeparatePdfs(ids)` → build `entryNames` from the selected
  documents' names → `archiver.zip(files, archiveName: 'documents.zip', entryNames: …)`
  → `share([zip.path], mimeType: 'application/zip')`.
- Ordering: currently displayed (sorted) list order.
- Any exception → existing `"Couldn't share"` snackbar (`ScaffoldMessenger`).
- On success: clear `_selectedIds` (exits selection mode).

### Error handling & edge cases

- Empty `documentIds` → `DocumentExportException` → snackbar.
- A document with no pages: `exportPdf` already handles this (empty documents don't occur
  in practice — deleting a document's last page deletes the document).
- Double-tap Export while an export is in flight → ignored via `_sharing`.
- Zip entry-name collisions (two docs same name) → de-duplicated with a numeric suffix.
- Everything stays on-device / in temp; nothing is written to the backed-up store.

## Testing (TDD/BDD — written FIRST, red before green)

**TDD host tests (`flutter test`), each written before its implementation:**
- `test/features/library/export_separate_pdfs_test.dart` — one file per id in list order;
  empty input throws `DocumentExportException`; outputs are temp `.pdf` files.
- `test/features/library/file_archiver_test.dart` — `SystemFileArchiver` zips N files;
  correct entry names; collision de-dup; output is a temp `.zip`; entries round-trip
  (decode) to the original bytes; verifies **stored (no compression)**.
- **`mimeType` plumbing at the call site** is verified on host via `FakeShareChannel`
  (asserts the home orchestration passes `application/zip`). Forwarding inside
  `SystemShareChannel` → `SharePlus`/`XFile` is a **native** concern (`SharePlus` is a
  platform channel, so it can't run under plain `flutter test`) and is verified
  on-device, consistent with the app's host/device split.
- `test/features/library/home_multi_export_test.dart` (widget):
  - long-press enters selection; title shows `"N selected"`; close clears it.
  - tap toggles a checkbox; opening is suppressed while selecting.
  - 1 selected → Export exports one PDF and shares it (`subject = name`, no zip).
  - 2+ selected → Export calls `exportSeparatePdfs(ids)`, then `archiver.zip(...)`, then
    `share([zip], mimeType: 'application/zip')`.
  - double-tap Export launches only one export (`_sharing` guard).
  - a failing export/zip/share shows `"Couldn't share"`.
  - selection cleared after a successful export.
- Fakes (`test/support/fake_library.dart`): extend `FakeDocumentRepository` with
  `exportSeparatePdfs` (recording ids); add `FakeFileArchiver` (recording call, returning
  a stub `.zip`); `FakeShareChannel` records `mimeType`.

**BDD (`.feature` + generated `*_test.dart` + `test/step/`):**
- `test/features/library/share_documents_zip.feature`:
  - Scenario: select two documents and share as a zip → the share sheet receives one
    `.zip` (asserted via the fake share channel recording a single `application/zip` path).
  - Scenario: select a single document and share → the share sheet receives one PDF (no
    zip, no dialog).
  - Regenerate with `build_runner`; steps in `test/step/` shared with the widget layer.

**Device verification (required by CLAUDE.md — the layer that actually failed before):**
- `integration_test/share_documents_zip_device_test.dart` — on a real **Android** device
  AND a real **iOS** device: seed 2 documents, enter selection, Export, and assert a real
  `.zip` file is produced on disk with the expected entries (the OS share sheet itself
  can't be asserted by automation, so the test verifies the produced artifact; the share
  invocation is confirmed by a manual/BDD-fake check). Runs with `-d <device-id>`.
- **Boot gate:** confirm the app cold-launches successfully on both devices after the
  change (guards the latent `createInBackground` hang). State the exact commands + green
  results before claiming done.

## Out of scope (YAGNI)

- **Merge into one combined PDF** and the export-choice dialog (possible follow-up).
- Export quality picker for multi-select (uses the current home-screen default, matching
  today's single-doc Share).
- Zipping raw page images instead of PDFs; password-protected / fax / link-share of the
  bundle.
- Fixing the latent `createInBackground` boot hang (tracked separately; this feature only
  must not make it worse and must verify boot).
