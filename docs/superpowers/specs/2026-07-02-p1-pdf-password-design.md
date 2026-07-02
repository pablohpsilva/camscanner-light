# P1 — PDF password protection (design)

**Date:** 2026-07-02
**Status:** Approved (design — user chose "PDF password")
**Sub-project:** cross-cutting (roadmap: "PDF password protection (optional), AES-256")
**Depends on:** C1/H5 (PDF generation), the `syncfusion_flutter_pdf` package (pure Dart).

## Purpose

Let the user export a **password-protected (AES-256 encrypted)** PDF — a stated
cross-cutting requirement of the app. The recipient needs the password to open
it. Nothing leaves the device except the encrypted file the user shares.

## Engine decision

The `pdf` package we generate with ships only the *abstract* `PdfEncryption`
(no concrete cipher), so encryption is done by **post-processing** the generated
PDF with **`syncfusion_flutter_pdf`** (pure Dart, resolves cleanly against our
deps; its `Community` license covers this use). Hand-rolling a PDF AES-256
security handler was rejected as error-prone crypto. The encryptor sits behind a
**`PdfEncryptor` DIP seam**, so the engine is swappable and testable; because
syncfusion is pure Dart, the crypto is fully **host-testable**.

## UX

- The page viewer's per-page overflow menu (`page-viewer-page-menu`) gains a
  **"Protect with password"** item (`page-viewer-protect`), after "Print".
- Selecting it opens a **password dialog** (`password-dialog`): one obscured
  field (`password-field`), a **Protect** button (`password-confirm`, disabled
  while the field is empty), and Cancel (`password-cancel`).
- On confirm: the document's PDF is generated, encrypted with the password, and
  a **"Protected PDF ready"** snackbar shows; the encrypted file then opens the
  OS share sheet (the in-app `pdfx` preview can't open an encrypted PDF without
  the password, so protected export shares directly).
- On failure: **"Couldn't protect PDF"**. Identical on iOS/Android.

## Architecture

- **`PdfEncryptor`** (new interface, `lib/features/library/pdf/pdf_encryptor.dart`):
  ```dart
  abstract interface class PdfEncryptor {
    Future<Uint8List> encrypt(Uint8List pdfBytes, String password);
  }
  ```
- **`SyncfusionPdfEncryptor implements PdfEncryptor`**: loads the PDF
  (`sf.PdfDocument(inputBytes: pdfBytes)`), sets `security.userPassword =
  password` and `security.algorithm = PdfEncryptionAlgorithm.aesx256Bit`, clears
  `documentInformation` (author/creator/producer/title/subject/keywords) for
  metadata hygiene, `save()`s, disposes, returns the encrypted bytes. Pure Dart.
- **`DocumentRepository.exportProtectedPdf(int documentId, String password) →
  Future<File>`** (new interface method): builds the PDF bytes via the existing
  `_pdfBuilder` (searchable text layer included), encrypts via an injected
  `PdfEncryptor`, writes them to a **temporary** file named
  `<sanitized-name>.pdf` (same temp-file discipline as `exportPdf`), returns it.
  Throws `DocumentExportException` on no-pages / build / encrypt / IO failure.
- **`DriftDocumentRepository`** gains an injected `PdfEncryptor encryptor`
  (default `const SyncfusionPdfEncryptor()`); `LibraryDependencies`' production
  factory keeps the default.
- **Page viewer** gains `_protect()`: shows the dialog, and on a non-empty
  password calls `exportProtectedPdf`, shows the snackbar, then shares the file
  (share errors swallowed quietly so a host test's missing share plugin doesn't
  surface as a failure).
- **`PasswordDialog`** (new widget) + `showPasswordDialog(context) →
  Future<String?>`.

## Data flow

```
menu "Protect with password" ─▶ showPasswordDialog → password
   └─ repo.exportProtectedPdf(docId, password)
        ├─ _pdfBuilder.build(pages)              → PDF bytes (searchable)
        └─ encryptor.encrypt(bytes, password)    → AES-256 encrypted bytes → temp .pdf
   ─▶ "Protected PDF ready" snackbar ─▶ OS share sheet
```

## Error handling

- Empty/cancelled password → no-op (no export).
- Build/encrypt/IO failure → `DocumentExportException` → "Couldn't protect PDF".

## Testing strategy (TDD/BDD first)

**Unit (host — syncfusion is pure Dart):**
- `SyncfusionPdfEncryptor.encrypt(bytes, 'secret')`: the output contains the
  `/Encrypt` marker (a plain unencrypted PDF does NOT); reopening the output with
  `sf.PdfDocument(inputBytes: out, password: 'secret')` succeeds; the input
  (unencrypted `pdf`-package output) does not contain `/Encrypt`.
- `exportProtectedPdf`: against a `NativeDatabase.memory()` repo with a seeded
  page (real JPEG) + the real `SyncfusionPdfEncryptor`, produces a temp `.pdf`
  whose bytes contain `/Encrypt`; a document with no pages throws
  `DocumentExportException`.

**Widget (host):**
- `PasswordDialog`: Protect is disabled until text is entered; entering a
  password and tapping Protect returns it; Cancel returns null.
- Page viewer "Protect with password" → dialog → entering a password calls the
  fake repo's `exportProtectedPdf(docId, password)` and shows "Protected PDF
  ready". (Share is fire-and-forget; the assertion is the repo call + snackbar.)

**BDD (on-device Samsung):** scan flow —
- *Given the app launched, when I scan and accept a page, open the document,
  Protect with password, and enter a password, then I see the protected-PDF
  confirmation.*
(The share sheet is not tapped; the confirmation snackbar is asserted.)

**On-device deterministic:** seed a 1-page doc, `exportProtectedPdf`, assert the
bytes contain `/Encrypt` (encryption works on-device).

## Cross-platform

`syncfusion_flutter_pdf` is pure Dart; the dialog + share are standard Flutter.
No platform channels, no per-OS branching.

## Definition of Done

- `PdfEncryptor` + `SyncfusionPdfEncryptor`, `exportProtectedPdf` (interface +
  Drift + fake), `PasswordDialog`, viewer wiring — TDD-covered.
- `syncfusion_flutter_pdf` added; `flutter pub get` resolves; builds on-device.
- `.feature` BDD generated + green on-device; deterministic device test green.
- `flutter analyze` clean; host suite green; `scripts/verify/p1.sh` passes on
  device; plans index updated.
