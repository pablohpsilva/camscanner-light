# R1 — Share a document (design)

**Date:** 2026-07-02
**Status:** Approved (design)
**Sub-project:** 6 — Sharing, printing & fax (Feature 12, "sharing")
**Depends on:** C1/H5 (PDF export), I1 (image export), O4 (.txt export), the
`share_plus` package (already a dependency).

## Purpose

Formalize document **sharing** behind a single `ShareChannel` interface (the OCP
extension point Feature 12 names), consolidate the three ad-hoc share call sites
onto it, and add a **Share** action to the documents list so a user can share a
document's PDF straight from the library. Reuses the existing metadata-scrubbed
export pipeline — sharing is just a new destination for already-scrubbed bytes.

## Problem being fixed

Today three screens each call `SharePlus.instance.share(ShareParams(...))`
directly and independently:

- `pdf_preview_screen.dart` — shares the PDF
- `page_viewer_screen.dart` — shares a page image and the PDF
- `recognized_text_screen.dart` — shares the recognized-text `.txt`

There is no shared abstraction, no seam for tests, and no extension point for the
deferred link-share/fax channels. This step introduces the interface, routes all
sites through it, and adds the missing library-list surface — without changing
what any existing button does.

## Approach & testability

The OS share sheet is native and cannot be driven by an automated test, so
sharing goes through a **`ShareChannel` seam (DIP)** — mirroring the existing
`DocumentPrinter` seam from N1. Production uses `SystemShareChannel` (wrapping
`SharePlus.instance.share`); tests and the on-device BDD inject a **recording
fake channel** via the composition root, so the flow is fully exercised (real PDF
build + wiring) without a blocking native sheet.

The interface is **path-based** (`List<String> filePaths`) so `share_plus`'s
`XFile`/`ShareParams` types stay entirely inside `SystemShareChannel` — the
abstraction has zero framework leakage, and a future `LinkShareChannel` slots in
without touching any caller.

`share_plus` is already the dependency the current call sites use — no new
dependency is introduced.

## Architecture

- **`ShareChannel`** (new interface, `lib/features/library/share_channel.dart`):
  ```dart
  abstract interface class ShareChannel {
    Future<void> share(List<String> filePaths, {String? subject});
  }
  ```
- **`SystemShareChannel implements ShareChannel`** (production,
  `lib/features/library/system_share_channel.dart`):
  `SharePlus.instance.share(ShareParams(files: filePaths.map(XFile.new).toList(),
  subject: subject))`. The **only** file that imports `share_plus`.
- **`LibraryDependencies`** gains `final ShareChannel share` (default
  `const SystemShareChannel()`) — the composition-root seam, exactly parallel to
  `printer`.
- **`HomeScreen`** passes `widget.libraryDependencies.share` to the
  `PageViewerScreen`, `PdfPreviewScreen`, and `RecognizedTextScreen` it
  constructs, and uses it directly for the library-list Share action.
- Each screen gains `final ShareChannel share` (default
  `const SystemShareChannel()` for direct-construction tests) and calls
  `share.share([...], subject: ...)` where it previously called `SharePlus`
  directly — behavior unchanged.
- **Test support:** a `FakeShareChannel` (records `filePaths` + `subject`, no-op);
  `tempLibraryDependencies()` injects it so the shared BDD launch never invokes
  the real share sheet.

## New surface — Share from the documents list

- `documents_list_view.dart`'s existing overflow `PopupMenuButton`
  (`document-menu-<id>`, currently just "Rename") gains a **"Share"** item
  (`document-share-<id>`), wired via a new `ValueChanged<DocumentSummary>?
  onShare` callback (same shape as `onRename`).
- `HomeScreen` handles `onShare`: `repository.exportPdf(docId)` → the temp PDF
  `File` → `share.share([file.path], subject: name)`. Sharing the document's
  **PDF** is the library-list default (single, obvious action — KISS).
- On failure (e.g. a missing page file during export): a **"Couldn't share"**
  snackbar; the list stays put.

## Data flow (library-list Share)

```
list menu "Share" ─▶ onShare(summary)
   ├─ repo.exportPdf(docId)         → temp PDF File (searchable, scrubbed)
   └─ share.share([file.path], subject: name)  → OS share sheet (prod)
                                                / recorded no-op (tests)
```

## Metadata-scrub guarantee (trust upstream + assert)

Every file handed to the channel is already scrubbed by the export pipeline:
`exportPdf` scrubs PDF metadata, image export scrubs EXIF, and a `.txt` carries
no metadata. The `ShareChannel` does **not** re-scrub (DRY — no double pass);
instead a test proves the file that reaches `share()` is metadata-free. Adding an
un-scrubbed caller in the future is caught by that test, not by runtime cost on
every share.

## Print stays separate

N1 print is already built & gated through the `DocumentPrinter` seam. Print opens
the OS print dialog — it is not a "share a file to another app" channel — so it
stays as its own seam rather than being folded under `ShareChannel`. This avoids
re-architecting a gated feature for no functional gain and keeps each seam
single-purpose (SRP).

## Fax / link-share (deferred, documented)

`ShareChannel` (OCP) is the extension point for a future on-device-agnostic
**link-share** channel — it slots in as another implementation with existing
channels undisturbed, satisfying Feature 12's interface criterion. **Fax** is a
distinct outbound mode (not a file share to an installed app); it is noted as a
future separate `FaxProvider` interface and is **not** built now (YAGNI). Neither
is implemented in R1.

## Error handling

- `exportPdf` failure on the library-list path → caught → "Couldn't share"
  snackbar; nothing else changes.
- The three existing screens keep their current behavior (fire-and-forget share);
  only the call target changes from `SharePlus.instance` to the injected channel.

## Testing strategy (TDD/BDD first)

**Unit:**
- `SystemShareChannel` implements `ShareChannel` (interface-exists test — also
  covers the "link-share/fax sit behind an interface" acceptance criterion).
- The file `exportPdf` produces (and that the library-list Share hands to the
  channel) is metadata-scrubbed — EXIF/PDF-metadata-free.

**Widget (host):**
- `DocumentsListView` renders a "Share" menu item when `onShare` is provided;
  selecting it fires `onShare` with the correct summary.
- `HomeScreen` given a fake repo + `FakeShareChannel`: selecting Share on a tile
  calls `share.share` with the exported PDF path + the document name; a repo whose
  `exportPdf` throws shows "Couldn't share".
- `PdfPreviewScreen`, `PageViewerScreen`, `RecognizedTextScreen` given a
  `FakeShareChannel`: tapping their Share control calls `share.share` with the
  expected file path + subject (behavior-preserved refactor).

**BDD (on-device Samsung):** the standard scan flow (with the recording
`FakeShareChannel` injected by `tempLibraryDependencies`) —
- *Given the app launched, when I scan and accept a page, then return to the
  library and Share the document, then the share channel is invoked with that
  document's PDF.*
This exercises the real PDF build on-device; only the terminal native sheet is
faked.

**On-device deterministic:** seed a 1-page doc, run the library-list Share path
with the fake channel, assert the recorded file starts with `%PDF` (reconfirms
the export→share wiring on-device).

## Cross-platform

`share_plus` handles the platform share sheet on iOS and Android. The seam +
Material menu item are pure Dart. No per-OS branching in our code.

## Definition of Done

- `ShareChannel` + `SystemShareChannel`; `LibraryDependencies.share`;
  `HomeScreen` threading; the three screens refactored onto the channel;
  `DocumentsListView` "Share" item + `HomeScreen` library-list Share handler —
  all widget-tested via `FakeShareChannel`.
- No new dependency (reuses `share_plus`); `flutter analyze` clean; host suite
  green.
- `.feature` BDD generated + green on-device; deterministic device test green.
- `scripts/verify/r1.sh` passes under the independent adversarial verifier from a
  clean state; plans index + roadmap Feature 12 row updated.
