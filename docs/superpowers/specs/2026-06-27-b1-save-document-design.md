# B1 — Save Photo + Document Record (design)

**Date:** 2026-06-27
**Status:** Design — awaiting user review
**Sub-project:** 1 — Core scan pipeline
**Build step:** B1 (first persistence step)
**Governed by:** Feature 01 (Document Scanning), Feature 02 (Document Library & Management)
**Depends on:** A3 (capture → review screen)
**Feeds:** B2 (list reads storage), B3 (page viewer), D (rename/delete/sort)

## Purpose

Turn **Accept** on the review screen from a throwaway navigation into a real
save: persist the captured JPEG (with identifying metadata stripped) to
permanent on-device storage, create a `Document` (one `Page`) record in a local
database, and surface it on the Documents home as a basic list. This is the
first step where a capture survives leaving the review screen.

## Scope

**In scope**
- A `DocumentRepository` (interface) + a Drift/SQLite-backed implementation.
- A pure-Dart image metadata scrubber (lossless EXIF strip, Orientation kept).
- A `SaveController` (idle → saving → error) driving the Accept action.
- Wiring Accept → save → home; the home reads storage and renders a **basic
  text list** (name + date), replacing the empty state when documents exist.

**Out of scope (later build steps)**
- Thumbnails, page count, sort, search, cold-start-restart proof → **B2**.
- Page viewer (open a document) → **B3**.
- Rename / delete (with confirm) → **D1 / D2**; sort → **D3**.
- Non-destructive page fields (corners, mode, enhancement) → **E / F / G**.
- Shared metadata scrubber + PDF metadata stripping → **Feature 07**.
- Multi-page / append-to-existing → **H**.

## Decisions (confirmed with product owner)

1. **Home scope:** minimal list now (name + date, reads storage on return); rich
   thumbnails / page count / restart proof deferred to B2.
2. **Storage:** Drift/SQLite for metadata; JPEG files on the app documents dir.
3. **EXIF:** strip in B1 (first permanent write) — **lossless** strip that
   **preserves the Orientation tag** so saved scans display upright.

## Data model & storage

### Records
- **`Document`** = `{ id: int, name: String, createdAt: DateTime (UTC),
  modifiedAt: DateTime (UTC) }`.
- **`Page`** = `{ id: int, documentId: int, position: int,
  relativeImagePath: String }`.
- One capture → one `Document` with one `Page` at `position = 1`.
- Autoincrement int ids (no uuid dependency).

### Drift schema
- Tables `Documents` and `Pages` (FK `Pages.documentId → Documents.id`).
- DB file opened at a **runtime-derived absolute path** each launch
  (`<appSupportOrDocumentsDir>/camscanner.sqlite`) via
  `NativeDatabase.createInBackground` (from `sqlite3_flutter_libs`).

### Files on disk
- Layout: `<appDocumentsDir>/documents/<docId>/page_1.jpg`.
- **The DB stores the RELATIVE path** (`documents/<docId>/page_1.jpg`), resolved
  against the *current* app documents dir at read time. **Rationale:** on iOS the
  app container's absolute path contains a GUID that changes on reinstall and can
  change on OS update — storing absolute paths would silently dangle every
  reference and defeat persistence. (This is the single most important
  correctness decision in B1.)

### Save sequence (transactional, capture never lost)
Run the whole write inside a **single Drift `transaction()`** so the database can
never hold a partial record:
1. Insert `Document` row → obtain `docId`.
2. Create `documents/<docId>/`, read the temp capture bytes → **scrub** → write
   `documents/<docId>/page_1.jpg`.
3. Insert `Page` row with the relative path.
4. If step 2 (file IO / scrub) throws, the transaction **rolls back the
   `Document` row automatically** (Drift rolls back when the closure throws); the
   `catch` then deletes the partially-written `documents/<docId>/` dir, leaves the
   temp capture intact, and surfaces a save error — the user stays on the review
   screen and can retry. No orphan row, no partial record.
5. After the transaction commits, delete the temp source file (best-effort; only
   if under the temp dir).

**Crash safety:** because rows are committed atomically *after* the file is
written, a process kill mid-save leaves **at most an unreferenced image file**
(no row points at it — harmless, GC-able later), never an orphan `Document`
without its `Page`. B2's "list reads storage" therefore never sees a broken
zero-page document.

### Naming
- Default name `Scan <YYYY-MM-DD HH.MM.SS>` from an **injectable clock**
  (`DateTime Function()`) so tests are deterministic. `modifiedAt = createdAt`.
  Rename is D1.

### YAGNI note
- No `folderId` / `tags` columns yet. Feature 02's "accept folders & tags later
  without breaking existing code" criterion is a D-step concern; Drift migrations
  add nullable columns / a tags table when those steps land. The repository
  interface insulates callers from the change.

## Components & interfaces (SOLID / DIP)

```
HomeScreen (Stateful) ──listDocuments()──> DocumentRepository ◄── interface
   │                                              ▲
   │ launches camera, awaits return               │ impl
   ▼                                              │
CameraScreen ── Accept ──> SaveController ──> DriftDocumentRepository
                            (ChangeNotifier)      ├─ ImageMetadataScrubber  (JpegExifScrubber)
                                                  ├─ AppDatabase            (Drift)
                                                  ├─ DocumentFileStore      (path resolution + IO)
                                                  └─ clock: DateTime Function()
```

- **`DocumentRepository`** (interface, the only thing the widget layer knows):
  - `Future<Document> createFromCapture(CapturedImage capture)`
  - `Future<List<Document>> listDocuments()` (newest first)
  The scrubber, DB, file store, and clock are private to the implementation —
  it scrubs, writes the file, and inserts the rows.
- **`DriftDocumentRepository`** — composes `AppDatabase`, `ImageMetadataScrubber`,
  `DocumentFileStore`, and the clock.
- **`ImageMetadataScrubber`** (interface) + **`JpegExifScrubber`** (impl) — see
  below. Feature 07 swaps the impl for the shared scrubber.
- **`DocumentFileStore`** — resolves relative ↔ absolute paths against the app
  documents dir; creates/deletes per-document dirs; writes bytes. Its **base dir
  is injected** (the composition root calls `path_provider` *once* and passes the
  dir in) — `path_provider` returns nothing under host unit tests, so the store
  must never call it internally. Keeps `path_provider` and `dart:io` out of the
  repository's logic for testability.
- **`SaveController`** (`ChangeNotifier`, mirrors `ScanController`): states
  `idle → saving → error`, a double-tap guard, and dispose-safety. Wraps
  `repository.createFromCapture` and exposes `save(CapturedImage)`.
- **`LibraryDependencies`** — composition root parallel to `ScanDependencies`
  (`createRepository()`); tests inject a `FakeDocumentRepository`.
- **`DocumentsListView`** — renders the basic name + date list. **No images** →
  deliberately sidesteps the `Image.file` host-widget-test hang (see
  `flutter-image-file-host-test-hang` memory); thumbnails arrive in B2.

## Data flow / navigation

`HomeScreen → CameraScreen → CaptureReviewScreen`.

- **Accept** → `SaveController.save(image)`; the review screen shows a saving
  indicator (mirrors A3's `capturing` busy state) and disables the buttons while
  in flight.
  - **Success** → navigate home (`popUntil((r) => r.isFirst)`); `HomeScreen`,
    which `await`ed the camera push, re-loads `listDocuments()` and rebuilds.
  - **Failure** → SnackBar "Couldn't save document. Try again." and **stay on
    the review screen** (capture intact, retry available).
- **Retake / back** unchanged from A3.
- `HomeScreen` becomes a `StatefulWidget`: it loads the list in `initState`, and
  re-loads after the camera push resolves.

## EXIF scrubbing (lossless, Orientation preserved)

`JpegExifScrubber` operates on JPEG bytes:

1. Verify the SOI marker `0xFFD8`. If the bytes are not a valid JPEG, **fail
   safe**: throw `MetadataScrubException` (the save then rolls back and surfaces
   the generic save error — we never write unverified data).
2. Read the **Orientation** value (tag `0x0112`) from the original APP1/Exif
   IFD0 if present (default `1`).
3. Walk the JPEG marker segments; **drop** the metadata application segments that
   can carry identifying data — APP1 (Exif + XMP) and APP13 (Photoshop/IPTC).
   Keep APP0 (JFIF) and APP2 (ICC colour profile, non-identifying) and all
   coding segments (DQT/DHT/SOF/SOS + entropy data) **byte-for-byte**.
4. Emit a fresh, **minimal canonical Exif APP1** containing only IFD0 with the
   single Orientation tag, placed immediately after SOI (Exif convention).
5. Concatenate → output. The compressed image scan data is identical to the
   input (lossless; OCR sharpness untouched), and the only metadata that survives
   is Orientation (whitelist, not blacklist — no GPS / Make / Model / Serial /
   Software / DateTime / MakerNote can leak).

This is pure Dart (no runtime dependency), deterministic, and host-testable.

**Correctness guarantee & its dependency.** Because the scan data is byte-identical
and Orientation is preserved, the scrubbed file renders *exactly* like the
original capture — no rotation regression is introduced **by the scrubber**.
"Keep Orientation" only displays upright if **every consumer honors the EXIF
Orientation tag** (Flutter `Image.file` for the review/B3 viewer; later OCR and
PDF export). Flutter has historically been inconsistent here, so this was
de-risked **before** committing the approach:

**On-device spike (2026-06-27) — PASSED.** On the project's physical Samsung
SM-A166B with **Flutter 3.44.4 (stable)**, a probe JPEG carrying orientation in
the **EXIF tag only** (Orientation=6, pixels not baked) rendered
**pixel-identically** to a reference image baked into the upright layout — both
`TL=BLUE TR=RED BL=YELLOW BR=GREEN`; the "ignored" layout did not occur.
Conclusion: **Flutter honors EXIF Orientation** via the engine codec, which
`Image.asset` and `Image.file` share — so kept-Orientation scans render upright
on the review/B3 screens. (Same spike also confirmed this device's camera writes
`Orientation = Rotated 90 CW` and leaks Make/Model/Software/DateTime — the strip
is warranted.)

Remaining plan items (now low risk):
- The scrubber's emitted Exif APP1 must be **valid TIFF** (a malformed block is
  silently ignored → still sideways); the unit test reads the output back with the
  `exif` package to prove Orientation parses as written, and the BDD/REAL_DEVICE
  lane re-confirms upright render end-to-end.
- **Contingency** (only if a future Flutter/engine regression drops EXIF
  honoring): switch `JpegExifScrubber` to bake-orientation-then-strip (decode →
  apply orientation → re-encode q95). Contained single-class change behind the
  `ImageMetadataScrubber` interface — no caller changes.

## Error handling

- Save failure / low storage → rollback (§ save sequence step 6), `error` state,
  SnackBar, stay on review. No crash. Mirrors Feature 01's "graceful, no crash".
- Empty library → existing `EmptyDocumentsView`.
- Non-JPEG / corrupt capture → scrubber fails safe → handled as a save failure.

## Testing strategy (TDD/BDD first)

- **Unit** (host SQLite required — see Dependencies; tests open
  `NativeDatabase.memory()`):
  - `DriftDocumentRepository.createFromCapture` + `listDocuments` round-trip
    against a temp dir + in-memory Drift DB: a row is created, the file
    exists at the resolved relative path, `listDocuments` returns it newest-first.
  - Crash safety: a `createFromCapture` whose file write throws leaves **no**
    `Document` row (transaction rollback) and no orphan dir.
  - Relative-path resolution: a record created under one app-dir resolves under a
    *different* app-dir base (simulates the iOS container-GUID change) — proves
    we did not persist an absolute path.
  - `JpegExifScrubber`: feed a real JPEG carrying GPS + Make + Model +
    Orientation=6 → asserts GPS/Make/Model are gone, **Orientation == 6**
    survives, and the SOF/SOS/entropy bytes are byte-identical to the source
    (lossless). Non-JPEG input → `MetadataScrubException`.
  - `SaveController`: success (idle→saving→idle, returns Document), failure
    (→error, capture retained), double-tap guard, dispose-safety.
  - Deterministic name/date via the injected clock.
- **Widget:**
  - `DocumentsListView` renders name + date from a fake repository; empty state
    when the list is empty.
  - Review **Accept** → save success navigates home; save failure shows the
    SnackBar and stays (using a fake repository whose `createFromCapture` throws).
  - Saving indicator shows / buttons disabled while a save is in flight (gated
    fake repository).
- **BDD** `b1_save_document.feature` (Android + iOS sim):
  - *Given camera permission is granted, when I capture and tap Accept, then a
    document with its name and date appears on the Documents home.*
  - *Given a save fails, when I tap Accept, then I see an error and remain on the
    review screen (the capture is not lost).*
- **Verify gate** `scripts/verify/b1.sh` (sources `scripts/verify/lib.sh`):
  analyze + unit/widget + BDD on emulator and iOS simulator, with a coverage
  floor; asserts success markers (silence = FAIL). Opt-in `REAL_DEVICE=1` lane:
  capture + Accept on a physical Android device, then pull the saved file
  (`adb exec-out run-as <appId> cat files/.../documents/<id>/page_1.jpg >
  $EVIDENCE_DIR/saved.jpg`) and assert with a **concrete EXIF tool** (host
  `exiftool` if present, else a Python `exifread`/`Pillow` snippet — the harness
  `require_tool`s it so a missing tool is a FAIL, never a silent pass): file is
  **non-empty**, contains **no GPS / Make / Model / Software / DateTime** tags,
  and **Orientation matches** the captured value. Also confirm the review/list
  render **upright** (the on-device orientation check above).

## Dependencies added

- Runtime: `drift`, `sqlite3_flutter_libs` (bundles SQLite on **device**),
  `path_provider`, `path`.
- Dev: `drift_dev`, `build_runner`, `exif` (test-only, to assert scrubber output),
  and a **host SQLite for `flutter test`** — `sqlite3_flutter_libs` is
  device-only, so host unit tests need `sqlite3` available (the `sqlite3` Dart
  package's bundled lib, or a verified system `libsqlite3`). The plan pins this so
  round-trip tests actually load.
- **Codegen:** Drift generates `app_database.g.dart` via `build_runner`, running
  alongside the existing `bdd_widget_test` codegen. The plan runs
  `dart run build_runner build --delete-conflicting-outputs`, **commits** the
  generated files (same policy as the committed BDD `_test.dart`), and the gate
  asserts they are current (regenerate + `git diff --exit-code`).
- **Drift `schemaVersion = 1`** with a `MigrationStrategy` stub, so future columns
  (folderId/tags in D, corners/mode/enhancement in E/F/G) migrate cleanly.
- Platform: ensure the iOS min deployment target and Android settings required by
  `sqlite3_flutter_libs` are set in the plan so the build doesn't surprise us.

## Privacy

All storage is local (app documents dir + local SQLite). **No network calls, no
cloud.** Identifying EXIF is stripped on the first permanent write. The privacy
spine — documents never leave the device — holds.

## Known gaps (named, carried with rationale — not silent)

- **iOS relative-path reinstall-survival is verified on the simulator, not a
  physical iPhone.** The relative-path decision specifically protects against the
  iOS container-GUID change on reinstall/update; we prove the resolution logic in
  a host unit test (resolve under a changed base) and exercise the save path on
  the iOS simulator, but do not run a real-iPhone reinstall. Deferred, consistent
  with A3's real-iOS deferral.
- **EXIF Orientation honoring depends on Flutter** (see scrubbing §) — **verified
  PASS** on-device (SM-A166B, Flutter 3.44.4) before committing the approach;
  bake-on-save kept as a documented contingency only.
- **No background GC of unreferenced image files** from a crash-mid-save. Rare,
  harmless (no row references them); a sweep can be added with B2's storage read
  if it ever matters.

## Deliverable (user-testable)

After B1 you can: open the app, tap **Scan**, capture a photo, tap **Accept**,
and see a **new document (name + date) on the Documents home** where the empty
state used to be. **You can test it by** capturing two photos and confirming two
dated entries appear; forcing a save failure (e.g. read-only/full storage in a
test build) and confirming you stay on review with an error and no lost capture;
and, on a real Android device, confirming the saved JPEG exists on disk and
carries no GPS/device EXIF.

## Acceptance criteria (each closed only by a passing test)

- [ ] Accept persists the capture: a JPEG is written under
  `documents/<id>/page_1.jpg` and a `Document`+`Page` row is created — *unit:
  repository round-trip · BDD: capture→Accept→document appears*
- [ ] The stored image path is **relative** and resolves under a changed app-dir
  base — *unit: relative-path resolution*
- [ ] Saved JPEG has identifying EXIF stripped with **Orientation preserved** and
  image data unchanged — *unit: JpegExifScrubber · REAL_DEVICE: no GPS/Make/Model
  on device*
- [ ] The Documents home reads storage and lists saved documents (name + date),
  replacing the empty state — *widget: DocumentsListView · BDD*
- [ ] Save failure surfaces an error and keeps the user on review with the
  capture intact (no crash) — *unit: SaveController failure · widget: Accept
  failure SnackBar*
- [ ] Double-tap on Accept saves once; disposing mid-save does not notify — *unit:
  SaveController guard + dispose-safety*
- [ ] A failed file write leaves **no** `Document`/`Page` row (transactional save,
  no orphan) — *unit: crash-safety rollback*
- [ ] Saved scan renders **upright** on a real device (Orientation honored, or
  bake fallback applied) — *REAL_DEVICE: on-device orientation check*

---

> **Definition of Done gate:** Per the Definition of Done in
> `00-overview-roadmap.md`, B1 is **not done** until every acceptance criterion
> above maps to a passing TDD test and (for user-facing behavior) a BDD scenario,
> the full suite is run and observed green, quality gates pass, and the work is
> reviewed and independently double-checked. "Looks right" / "should pass" is not
> done.
