# N1 — Print a document (design)

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 6 — Sharing, printing & fax (Feature 12, "printing")
**Depends on:** C1/H5 (PDF export), the `printing` package.

## Purpose

Let the user send a document to a printer (or the OS "print / save as PDF /
AirPrint" sheet) from the page viewer. Reuses the existing searchable,
metadata-scrubbed PDF pipeline — printing is just a new destination for the same
PDF bytes.

## Approach & testability

The OS print UI is native and cannot be driven by an automated test, so printing
goes through a **`DocumentPrinter` seam (DIP)**. Production uses
`SystemDocumentPrinter` (the `printing` package's `Printing.layoutPdf`); tests
and the on-device BDD inject a **no-op fake printer** via the composition root,
so the flow is fully exercised (real PDF build + wiring) without a blocking
native dialog. The seam takes a **`File`** (not bytes) so the fake never has to
read anything.

`printing` is the standard sibling of the `pdf` package we already use — the
obvious, well-maintained way to print in Flutter; no heavier dependency needed.

## UX

- The page viewer's per-page overflow menu (`page-viewer-page-menu`) gains a
  **"Print"** item (`page-viewer-print`), after "Export all as images".
- Selecting it builds the document's PDF and opens the OS print sheet, then
  shows a **"Sent to printer"** snackbar. On failure: **"Couldn't print"**.
- Works on iOS (AirPrint / UIPrintInteractionController) and Android (Android
  print framework) — both handled by `printing`.

## Architecture

- **`DocumentPrinter`** (new interface, `lib/features/library/document_printer.dart`):
  ```dart
  abstract interface class DocumentPrinter {
    Future<void> printPdf(File pdf, {required String name});
  }
  ```
- **`SystemDocumentPrinter implements DocumentPrinter`** (production):
  `Printing.layoutPdf(name: name, onLayout: (_) async => pdf.readAsBytes())`.
- **`LibraryDependencies`** gains `final DocumentPrinter printer` (default
  `const SystemDocumentPrinter()`) — the composition-root seam.
- **`HomeScreen`** passes `widget.libraryDependencies.printer` to the
  `PageViewerScreen` it constructs.
- **`PageViewerScreen`** gains `final DocumentPrinter printer` (default
  `const SystemDocumentPrinter()` for direct-construction tests) + `_print()`:
  `exportPdf(documentId)` → the temp PDF `File` → `printer.printPdf(file, name:
  _name)` → "Sent to printer" snackbar; "Couldn't print" on any failure, with
  `mounted` guards.
- **Test support:** a `FakeDocumentPrinter` (records the file/name, no-op);
  `tempLibraryDependencies()` injects it so the shared BDD launch never invokes
  the real printer.

## Data flow

```
menu "Print" ─▶ _print()
   ├─ repo.exportPdf(documentId)  → temp PDF File (searchable, scrubbed)
   └─ printer.printPdf(file, name)  → OS print sheet (prod) / no-op (tests)
 ─▶ "Sent to printer" snackbar
```

## Error handling

- `exportPdf` failure (e.g. a missing page file) or a printer error → caught →
  "Couldn't print" snackbar; the viewer stays put.

## Testing strategy (TDD/BDD first)

**Widget (host):** `PageViewerScreen` given a fake repo + a `FakeDocumentPrinter`
→ tapping "Print" calls `printPdf` with the exported file + the document name and
shows "Sent to printer"; a repo whose `exportPdf` throws shows "Couldn't print".
(No native plugin is touched — the fake printer no-ops.)

**BDD (on-device Samsung):** the standard scan flow (with the no-op fake printer
injected by `tempLibraryDependencies`) —
- *Given the app launched, when I scan and accept a page, open the document, and
  Print, then I see the print confirmation.*
This exercises the real PDF build on-device; only the terminal native sheet is
faked.

**On-device deterministic:** seed a 1-page doc, `exportPdf`, assert the bytes
start with `%PDF` (reconfirms the pipeline on-device).

## Cross-platform

`printing` handles the platform print sheet on iOS and Android. The seam +
Material menu are pure Dart. No per-OS branching in our code.

## Definition of Done

- `DocumentPrinter` + `SystemDocumentPrinter`, `LibraryDependencies.printer`,
  `HomeScreen` threading, `PageViewerScreen` "Print" action — widget-tested via
  the fake printer.
- `printing` added to `pubspec.yaml`; `flutter pub get` resolves; the app builds
  on-device.
- `.feature` BDD generated + green on-device; deterministic device test green.
- `flutter analyze` clean; host suite green; `scripts/verify/n1.sh` passes on
  device; plans index updated.
