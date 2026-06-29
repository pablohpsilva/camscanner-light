# B2 — Documents list reads from storage (design)

**Status:** approved (design phase)
**Date:** 2026-06-28
**Depends on:** B1 (save photo + document record) — `docs/superpowers/specs/2026-06-27-b1-save-document-design.md`
**Feeds:** B3 (page viewer / tap-to-open), D3 (sort)

## Goal

Turn the home Documents list from B1's bare name+date rows into a **rich list
that reads richer data from storage**: each saved document shows a **thumbnail**,
its **name**, **date**, and **page count**. Prove that saved documents **survive
an app restart** (cold start).

## Scope (locked)

**In:** thumbnails, page count, cold-start restart proof.
**Deferred:** sort → **D3** (the B1 spec was internally inconsistent — it listed
sort under both B2 and D3; D3 governs). Search → its own later step (low value
while documents are few and single-page). Multi-page capture, tap-to-open (B3),
orphan-file sweep — all out.

## What B1 already provides (so B2 does not rebuild it)

- The production composition root (`LibraryDependencies._defaultCreateRepository`)
  already opens a **persistent** `camscanner.sqlite` (in the app support dir) and
  `HomeScreen` reads it on launch. **Persistence across restart is therefore
  already true in production** — B2's job is to (a) **prove** it and (b) make the
  list **read richer data**, not to wire up storage.
- Stored JPEGs are **EXIF-scrubbed but keep the Orientation tag** (lossless,
  byte-level). Flutter honors that tag on-device (proven on SM-A166B), so
  thumbnails are upright with **no re-encode**.
- Image paths are stored **relative**, resolved to absolute **at read time**
  (iOS app-container GUID changes on reinstall/update). B2 keeps this rule.

## Architecture & read model

Today `DocumentRepository.listDocuments()` returns only `Document`
(id/name/dates). A rich tile additionally needs, per document, its **page count**
and its **first page's image path**. That is a new read model.

### `DocumentSummary` (list view model)

```
DocumentSummary {
  Document document;          // existing domain model (id, name, createdAt, modifiedAt)
  int pageCount;              // COUNT of pages for this document
  String? thumbnailPath;      // position-1 page image, resolved to ABSOLUTE at
                              // read time via the injected DocumentFileStore;
                              // null if the document has no page row
}
```

### Repository read

```
DocumentRepository.listDocumentSummaries() : Future<List<DocumentSummary>>
```

- Newest-first (order by `createdAt` desc), same ordering guarantee as B1.
- Computed with **grouped / aggregate Drift queries — no N+1**. Concretely: one
  grouped query joining `Documents` ⟕ `Pages` for the per-document `COUNT`, and
  one query selecting the **lowest-`position`** page path per `documentId`
  (`MIN(position)` — not literally `position == 1`, so it stays correct if a
  future multi-page document loses page 1); zip in Dart. (Exact Drift code is the
  plan's job.)
- **Replaces** `listDocuments()`. The exact migration surface (every caller and
  test) is:
  - `lib/.../document_repository.dart` — interface method
  - `lib/.../drift/drift_document_repository.dart` — implementation
  - `lib/.../home_screen.dart:60` — the only production caller
  - `test/.../drift_document_repository_test.dart:65,84` — repository test
  - `test/support/fake_library.dart:48` — the fake (see below)
  The dead `listDocuments()` is removed (YAGNI).

### No schema change / no migration

Page count and thumbnail path are **derived at read time** (aggregate + join) —
**no new columns**. `schemaVersion` stays **1**; no migration step is added.
This bounds B2's storage risk: the on-disk format is unchanged from B1.

### Fake repository shape (host tests)

`FakeDocumentRepository` currently builds a `Document` in `createFromCapture` but
**never creates a page row**. When it moves to `listDocumentSummaries()` it must
**synthesize**, per document: `pageCount: 1` and a **non-loadable**
`thumbnailPath` (e.g. an obviously-missing path) — so host widget tests render
the placeholder via `errorBuilder` instead of hanging on a real `Image.file`.

### DIP / responsibility boundaries

- The **repository** resolves relative→absolute. It already owns the
  `DocumentFileStore` on the write side; reading-resolve is the symmetric read
  side, performed **fresh on each launch** — this keeps the "store relative,
  resolve at read time" rule intact and iOS-container-safe.
- The **widget layer stays dumb**: it receives summaries carrying an
  already-resolved path (which, in host tests, is deliberately non-loadable) and
  never touches `path_provider` or the file store.

## Thumbnail rendering

### `DocumentThumbnail` widget (one job: paint a small upright thumbnail or a placeholder)

```
DocumentThumbnail({ String? path, double size = 48 })
  path == null   → placeholder: Icon(Icons.description_outlined)
  else           → Image.file(
                     File(path),
                     cacheWidth: round(size * devicePixelRatio), // codec downsamples at decode
                     fit: BoxFit.cover,
                     gaplessPlayback: true,
                     errorBuilder: → same placeholder,            // missing/corrupt → graceful
                   )
```

- **Upright for free:** stored JPEGs keep the Orientation tag; Flutter honors it
  on-device. No re-encode, no baking.
- **Memory-safe:** `cacheWidth` decodes at thumbnail resolution, not full-res,
  even though the source is a full-size scan; Flutter's image cache avoids
  redundant decodes.
- **Host-test-safe:** in host widget tests `path` is **non-loadable** (per the
  `flutter-image-file-host-test-hang` lesson), so `Image.file` hits
  `errorBuilder` fast (placeholder) instead of hanging. Host tests assert the
  widget is built with the right path/key and that the placeholder shows; **actual
  pixel rendering is verified on-device** (REAL_DEVICE lane), same pattern as B1.

## List UI

`DocumentsListView` changes from `List<Document>` → `List<DocumentSummary>`.
Each tile:

- **leading:** `DocumentThumbnail(path: summary.thumbnailPath)`, key `document-thumb-<id>`
- **title:** document name
- **subtitle:** `<localised date> · <N> page` / `pages` (singular/plural)
- keeps the `document-tile-<id>` key
- **no `onTap`** — opening a document is B3 (YAGNI here)

Loading / empty / error states are **reused unchanged** from B1
(`documents-loading`, `EmptyDocumentsView`, `documents-error` + `documents-retry`).

## Restart-persistence proof (three tiers, honest about what each shows)

A true OS-level process kill + relaunch is **not reliably automatable** in
Flutter's `integration_test` (it re-pumps a widget tree inside one running
process; it cannot fork a new process). The tiers differ in how much state each
actually destroys:

| Tier | Destroys | Proves | Automatable |
|---|---|---|---|
| 1 — host repo test | the SQLite **connection** (`db.close()` → reopen same file) | bytes are durably on disk, survive a connection lifecycle | ✅ in-gate, deterministic |
| 2 — integration | the **widget tree** (re-pump a fresh app against the same file) | the app's read path rebuilds the list from storage on a cold build | ✅ emulator + iOS sim |
| 3 — **OS kill** (manual) | the **entire process** (Dart VM + open connection) | the genuine real-user cold start | ❌ manual only |

- **Tier 1 (decisive automatable proof):** build `DriftDocumentRepository` on a
  real **temp-file** `NativeDatabase` (not in-memory), save a document,
  `db.close()`, open a **brand-new** `AppDatabase` on the **same file**, assert
  `listDocumentSummaries()` returns the doc with correct `pageCount` and a
  resolvable thumbnail path.
- **Tier 2:** **seed** a document directly into a persistent on-disk SQLite file
  via a throwaway connection that is then **closed** (modelling "this data was
  persisted before the current app instance started"), then **launch the app
  fresh** against the **same** DB file and documents dir, and assert the seeded
  document appears on the home list with its page-count text. This is a truer
  cold-start *read* than re-pumping inside one live process (which never kills
  the process or its DB connection), it is deterministic (no camera-tap flow),
  and — by seeding only the row, not the image file — it also exercises the
  missing-file→placeholder path on-device. (The app's own *save* path is already
  proven by B1's flow + Tier 1's repository persistence.)

  > **Why the existing helper can't be reused.** `tempLibraryDependencies()`
  > (`fake_library.dart:63`) constructs **`NativeDatabase.memory()`** *and* a
  > fresh `createTemp('b1bdd')` dir **inside the factory closure** — so each
  > `createRepository()` call yields a *new empty* DB and a *new empty*
  > documents dir; a re-pump gets a clean slate and nothing persists. Tier 2
  > therefore needs a **new** helper (e.g. `persistentLibraryDependencies(dbFile,
  > baseDir)`) that captures **both** a **file-backed** `NativeDatabase(dbFile)`
  > at a **stable path** **and** a **stable `DocumentFileStore` baseDir**
  > *outside* the factory, and reuses both across re-pumps. The DB file alone is
  > insufficient: if the documents dir also rotates, the page file written on the
  > first pump is orphaned and every thumbnail resolves to "missing".
  > `tempLibraryDependencies()` stays as-is for the existing (memory) success
  > scenario; Tier 2 is a **new** scenario.
- **Tier 3 (REAL_DEVICE, deferred-with-sign-off, like B1):** `adb shell am
  force-stop com.camscannerlight.mobile` (or swipe-away) then relaunch on the
  SM-A166B; the document shows with an **upright** thumbnail. Carries the two
  device-only claims (real cold start + upright thumbnail).

## Testing

- **Repository:** `listDocumentSummaries()` returns correct `pageCount` +
  first-page path; **newest-first ordering preserved**; a document whose page
  file is missing still lists (thumbnail degrades to placeholder).
- **`DocumentThumbnail` widget:** null path → placeholder; non-loadable path →
  placeholder via `errorBuilder` (no hang).
- **`DocumentsListView` widget:** N summaries → N tiles, each with name,
  `date · N page(s)` subtitle, and a `DocumentThumbnail`; structure asserted
  without hang.
- **Regression (privacy spine):** the B1 **EXIF-clean** check and
  transactional-save guarantees still pass.

## Verification harness

`scripts/verify/b2.sh` on the existing `lib.sh`:

- coverage floor (excluding `*.g.dart`, as in B1),
- codegen marker (`Built with build_runner`),
- integration android + ios (`verify_integration_android` / `_ios`),
- the **Tier-1 restart test** as a named required check,
- **EXIF-clean regression** (privacy spine),
- negative control: `VERIFY_SKIP_DEVICE=1 → GATE: FAIL` (fail-closed),
- `GATE: PASS` only on exit 0 + marker.

## Acceptance criteria

1. Home list shows each saved document with a thumbnail, name, date, and page count.
2. `listDocumentSummaries()` aggregates page count + first-page path with no N+1,
   newest-first.
3. Tier-1 restart test passes (data survives DB close/reopen on disk).
4. Tier-2 integration test passes on emulator + iOS sim (fresh widget tree reads
   storage).
5. A missing/corrupt image file yields a placeholder — never a crash or a hang.
6. EXIF-clean + transactional guarantees regression-pass (privacy spine intact).
7. *(REAL_DEVICE, deferred)* a true OS-kill cold start shows the document.
8. *(REAL_DEVICE, deferred)* the thumbnail renders upright on device.

Criteria 1–6 are gated host/emulator/sim. Criteria 7–8 are the opt-in
REAL_DEVICE lane, deferred-with-sign-off consistent with B1.

## Known gaps / non-goals (explicit)

- No **sort** (D3), no **search**, no **multi-page capture** (page count reads 1
  for every document until multi-page capture lands — the aggregate read is
  multi-page-ready), no **tap-to-open** (B3).
- No **orphan-file sweep** (B1 noted stray files as harmless — no row references
  them; a sweep can ride a later cleanup step).
- Tier-3 OS-kill is a **manual** REAL_DEVICE check, not a gated criterion.

## Privacy spine (binding, unchanged)

Documents never leave the device. No cloud, no network calls. Thumbnails are
rendered from the same on-device files; nothing is uploaded, cached off-device,
or indexed externally.
