# B3 — Page viewer / tap-to-open (design)

**Status:** approved (design phase)
**Date:** 2026-06-28
**Depends on:** B1 (save photo + document record), B2 (documents list reads from storage) —
`docs/superpowers/specs/2026-06-28-b2-documents-list-design.md`
**Feeds:** later steps (rename, share/export, multi-page capture, OCR)

## Goal

Tap a document on the home list to **open a full-screen page viewer** with
**pinch-zoom + pan**, and **delete** a document from that viewer (confirm →
remove the document, its pages, and its on-disk files → return to the list with
the document gone). B2 deliberately left the tile with no `onTap`; B3 wires it.

## Scope (locked)

**In:** tap-to-open; full-screen viewer with pinch-zoom + pan, multi-page-ready
(`PageView`, shows 1 page today); delete (confirm → remove row + pages + files →
back to list).
**Deferred (each its own later step):** rename, share/export, multi-page
capture, page reorder, OCR, orphan-file sweep, immersive system-chrome hiding,
a11y/semantics polish.

## What B1/B2 already provide (so B3 does not rebuild it)

- The `Page` domain model and `Pages` table (FK `onDelete: cascade` to
  `Documents`; `PRAGMA foreign_keys = ON` per connection via `beforeOpen`).
- `DocumentFileStore.absoluteFor(rel)` — resolve relative→absolute **at read
  time** (iOS container GUID rule) — and `deleteDocumentDir(docId)`, which
  already guards `if (await dir.exists())` (so deleting a document whose image
  file was never written is a safe no-op, not a throw).
- The production composition root builds **one** `DriftDocumentRepository` in
  `HomeScreen`; B3 passes that **same instance** to the viewer (no second DB
  connection).
- The host-test image hazard (`flutter-image-file-host-test-hang`): a
  **loadable** `Image.file` path **hangs** host widget tests. B3 viewer host
  tests therefore use **non-loadable** paths and assert **wiring**, not pixels;
  actual rendering + zoom are REAL_DEVICE.

## Read model + repository additions

Two new methods on `DocumentRepository` (the only persistence surface the widget
layer knows — DIP):

```
getDocumentPages(int documentId) : Future<List<PageImage>>   // position asc, ABSOLUTE paths
deleteDocument(int documentId)   : Future<void>              // transactional; see Delete semantics
```

New view model (symmetric with `DocumentSummary`; keeps the widget layer dumb —
it never touches the file store):

```
PageImage { int position; String imagePath; }   // imagePath = ABSOLUTE, resolved at read time
```

- `getDocumentPages` runs **one** query (`select Pages where documentId order
  by position asc`) and resolves each `relativeImagePath`→absolute via the
  injected `DocumentFileStore`. **No N+1. No schema change** (`schemaVersion`
  stays 1).

### Migration surface (exact files touched)

- `lib/.../document_repository.dart` — add the two interface methods.
- `lib/.../drift/drift_document_repository.dart` — implement both.
- `lib/.../widgets/documents_list_view.dart` — add an **optional**
  `ValueChanged<DocumentSummary>? onOpen`; the tile `onTap` is `null` when
  `onOpen` is null (so existing construction stays valid).
- `lib/.../home_screen.dart` — pass `onOpen: _openDocument`; add `_openDocument`.
- `lib/.../page_viewer_screen.dart` — **new** viewer screen (feature root, like
  `home_screen.dart` — screens are not under `widgets/`).
- `lib/.../page_image.dart` — **new** `PageImage` view model.
- `test/features/library/documents_list_view_test.dart` — add an `onOpen`-fires
  test (existing tests keep compiling because `onOpen` is optional).
- `test/support/fake_library.dart` — `FakeDocumentRepository` gains
  `getDocumentPages` + `deleteDocument`.
- `integration_test/b3_view_and_delete.feature` + generated `_test.dart`, and
  the new `test/step/` files it references (see Tier 2) — **new**.

## Viewer UI — `PageViewerScreen` (StatefulWidget)

Constructed with `documentId`, `name`, and the `repository` (the same instance
`HomeScreen` already holds).

- Loads pages in `initState` → **loading / error / loaded / empty** states (same
  shape as `HomeScreen`), each with a test key:
  - `page-viewer-loading` — `CircularProgressIndicator` while reading pages.
  - `page-viewer-error` — `getDocumentPages` threw; shows a message + a
    **retry** (`page-viewer-retry`) that re-runs `getDocumentPages` (mirrors
    `HomeScreen`'s error/retry).
  - `page-viewer-empty` — zero pages (data anomaly or a race against delete);
    an explicit "this document has no pages" placeholder, never a blank
    `PageView` or crash.
- **Loaded:** a `PageView` of zoomable pages. Each page =
  `InteractiveViewer` (pinch-zoom + pan) wrapping
  `Image.file(File(p.imagePath), errorBuilder: → placeholder)`. Decodes
  **full-resolution** (no `cacheWidth`) so zoom is usable. Per-page key
  `page-viewer-page-<position>`. A page indicator (`page-viewer-indicator`)
  shows **always**, reading `1 / N` (`1 / 1` today) — it confirms
  multi-page-readiness and matches the approved viewer mockup.
- **AppBar:** title = document name; automatic back; a **delete** action
  (`Icons.delete_outline`, key `page-viewer-delete`).

> **Full-res decode is NOT memory-safe for many pages.** A `PageView` keeps
> neighbor pages alive; full-res decoding of many large scans at once would
> OOM. The **read model** is multi-page-ready, but the **decode policy is not**:
> when multi-page capture lands, the viewer must add decode management
> (screen-width `cacheWidth` + offscreen dispose). Named here so it is a known
> future constraint, not a silent over-claim.

> **Zoom is bitmap-scaling, not re-decode.** `InteractiveViewer` scales the
> already-decoded bitmap; sharpness is capped at the decoded resolution (no
> tiled re-decode). Full-res decode is precisely what makes zoom usable — do not
> "optimize" the decode down.

## Navigation wiring

`HomeScreen` owns navigation (the dumb list never imports the repository or a
route):

```
DocumentsListView(summaries: _summaries, onOpen: _openDocument)   // list just invokes the callback

Future<void> _openDocument(DocumentSummary s) async {
  final repo = _repository;
  if (repo == null) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
      PageViewerScreen(documentId: s.document.id, name: s.document.name, repository: repo)));
  await _load();   // reflect a delete that happened in the viewer
}
```

This mirrors the existing `_openScan` (push, then `await _load()` on return).

## Delete semantics (row-first, orphan-safe)

`deleteDocument(int documentId)`:

1. **DB first (authoritative), in one transaction:** delete `Pages where
   documentId`, then the `Documents` row. Explicit page-delete (not relying
   solely on the `foreign_keys` pragma being on in every connection) — correct
   even if the pragma were off.
2. **Then best-effort** `_fileStore.deleteDocumentDir(documentId)`.

**Why row-first:** worst case (crash or IO failure between commit and dir
delete) is **orphan files with no row referencing them** — harmless, the same
stance B1 took on stray files (a sweep is a later step). File-first would risk
the *bad* case (row present, file gone → permanent dangling reference).

- Deleting a **non-existent id is a no-op, no throw** (double-tap safe).
- If the DB delete itself throws, the viewer **stays put** and shows a transient
  "Couldn't delete" `SnackBar` (capture the messenger before the `await`).

### Confirm dialog + delete sequence (the screen owns it, not the dialog)

The dialog is a pure `showDialog<bool>` that performs **no** side effect — it
only returns the user's choice. The **screen** owns the sequence, so the failure
SnackBar lands on the viewer's own Scaffold and there is no captured-Navigator-
inside-the-dialog dance:

```
final ok = await showDialog<bool>(context: ..., builder: ...);  // dialog returns true/false only
if (ok != true) return;                       // Cancel / dismiss → nothing happens
try {
  await widget.repository.deleteDocument(widget.documentId);
  if (!mounted) return;
  Navigator.of(context).pop();                // leave the viewer → Home._load() reflects the delete
} catch (_) {
  if (!mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text("Couldn't delete")));  // stay on the viewer
}
```

`AlertDialog` copy — "Delete this document? This can't be undone." → **Cancel**
(key `page-viewer-delete-cancel`, returns `false`) / **Delete** (destructive,
key `page-viewer-delete-confirm`, returns `true`). Exactly **two** Navigator
operations occur and in this order: the dialog closes (returning its bool),
then — only on success — the viewer pops. The failure path pops neither.

## Restart / durability proof (three tiers — B3 is read + delete, not save)

Read durability is already proven by B1/B2 cold start; B3's viewer reads the
same storage. The new claim B3 must prove is that **delete is durable**.

| Tier | Destroys | Proves | Automatable |
|---|---|---|---|
| 1 — host repo test | the DB **connection** (`db.close()` → reopen same file) | after delete, reopen shows the doc gone **and** its dir gone | ✅ in-gate |
| 2 — integration | the **widget tree** (cold launch vs the same file + dir) | open → view → delete → back on the list, doc gone | ✅ android + ios |
| 3 — REAL_DEVICE (deferred) | the **process** + real gestures | pinch-zoom magnifies, upright render; OS-kill after delete still gone | ❌ manual |

- **Tier 1 (decisive automatable proof):** build `DriftDocumentRepository` on a
  real **temp-file** `NativeDatabase`, save a document, `deleteDocument`,
  `db.close()`, reopen a **brand-new** `AppDatabase` on the **same file**, assert
  `listDocumentSummaries()` no longer lists it, `getDocumentPages()` returns
  empty, and the on-disk document dir is gone.
- **Tier 2:** **seed** a document on disk via a throwaway connection (reuse B2's
  `persistentLibraryDependencies` + seed-on-disk helper), **cold launch** the
  app against the same DB file + dir, tap the tile → viewer opens, tap delete →
  confirm → assert back on the home list with the document gone. (Seeding only
  the row, not the image file, also exercises the missing-file placeholder in
  the viewer and the `dir-absent` branch of `deleteDocumentDir`.)
  - New feature: `integration_test/b3_view_and_delete.feature` and its generated
    `_test.dart`. New step files under `test/step/`: open the document
    (taps `document-tile-<id>`), see the page viewer (`page-viewer-page-1`),
    tap delete (`page-viewer-delete`), confirm delete
    (`page-viewer-delete-confirm`), the document is gone.
  - **Silent-stub guard (B2 lesson):** `bdd_widget_test` **silently generates an
    empty stub** when a Gherkin step name does not map to its expected
    camelCase step file — a **vacuous pass**. Each new step's generated wiring
    MUST be confirmed to call a real, asserting step implementation (no empty
    stub), exactly as B2 required.
- **Tier 3 (REAL_DEVICE, deferred-with-sign-off):** on the SM-A166B, pinch-zoom
  actually magnifies and the page renders upright; after a real `adb shell am
  force-stop` + relaunch, a deleted document is still gone.

## Testing (host)

- **Repository:** `getDocumentPages` → pages position-asc with absolute paths,
  single query (no N+1); `deleteDocument` removes rows + dir; **idempotent** on a
  missing id; **Tier-1 close/reopen durability**.
- **`PageViewerScreen`:** loading→loaded; loaded asserts `InteractiveViewer` +
  `Image.file` with the right path/key per page using **non-loadable paths →
  assert wiring, not pixels** (the `flutter-image-file-host-test-hang` lesson;
  re-confirmed by spike 3: no hang, `find.byType(InteractiveViewer)` +
  `image is FileImage` with the right path + `errorBuilder != null` are all
  assertable). **The viewer asserts `image is FileImage`, NOT `ResizeImage`** —
  the viewer decodes full-res (no `cacheWidth`), unlike B2's thumbnail; do not
  copy B2's `ResizeImage` matcher here. **zero-pages → empty placeholder**;
  **`getDocumentPages` throws → error state (`page-viewer-error`) shown, no
  crash; retry re-runs the load**; delete → confirm dialog → **Delete** calls
  `deleteDocument` + pops; **Cancel** → no call; **delete throws → no pop, error
  SnackBar, viewer still present**. (Both the load-error and the delete-error
  branches are tested, not vacuously uncovered.)
- **`DocumentsListView`:** tile `onTap` invokes `onOpen` with the correct
  summary; with `onOpen == null` the tile has no tap handler (existing tests).
- **Regression (privacy spine):** B1 EXIF-clean + transactional-save and B2 list
  guarantees stay green.

### Honest limit on acceptance criterion 5 (orphan-safety)

Row-first ordering bounds the worst case to harmless orphan files, but injecting
a file-IO failure *between* the DB commit and the dir delete is not cheaply
testable in a host test. The **durability test proves the happy path** (rows +
dir gone after reopen); the orphan-safety **worst case is enforced by code
review of the ordering**, not by a passing assertion. Stated so criterion 5 is
not read as gated the same way as 1–4.

## Spikes (de-risk load-bearing premises before the plan locks)

1. **Gesture conflict:** `InteractiveViewer` inside `PageView` on the real
   toolchain — confirm the chosen handling (disable page-swipe while zoomed vs
   physics tuning) so "multi-page-ready" is not a latent bug.
2. **Delete cascade + dir delete** on a temp-file DB: confirm the delete leaves
   the reopened DB empty and the dir gone.
3. **Host-test behavior** of an `InteractiveViewer`-wrapped `Image.file` with a
   non-loadable path: confirm no hang and that wiring is assertable.

## Verification harness

`scripts/verify/b3.sh` on the existing `lib.sh` (mirrors `b2.sh`):

- static asserts: `PageViewerScreen`, `getDocumentPages`, `deleteDocument`,
  `InteractiveViewer`, `onOpen` callback wiring, confirm-dialog keys,
  `schemaVersion => 1`,
- codegen marker (`Built with build_runner`),
- `mobile:test`, `analyze`,
- coverage floor 70 (excluding `*.g.dart`),
- integration android + ios (`verify_integration_android` / `_ios`
  `b3_view_and_delete_test.dart`),
- **no-empty-stub guard:** assert each new B3 generated step calls a real step
  implementation (the B2 silent-stub / vacuous-pass hazard),
- the **Tier-1 delete-durability test** as a named required check,
- **EXIF-clean regression** (privacy spine),
- negative control: `VERIFY_SKIP_DEVICE=1 → GATE: FAIL` (fail-closed),
- opt-in REAL_DEVICE Tier-3,
- `GATE: PASS` only on exit 0 + marker.

## Acceptance criteria

1. Tapping a document opens the viewer showing its page(s).
2. The viewer supports pinch-zoom + pan (host: wiring; pixels: REAL_DEVICE).
3. `getDocumentPages` returns pages position-asc, absolute paths, no N+1.
4. Delete (confirm) removes the document row + pages + on-disk dir; the list
   reflects it; **durable across DB close/reopen** (Tier-1).
5. Delete is idempotent and row-first orphan-safe (worst case = harmless orphan
   files — see the honest limit above; enforced by code review, not a gated
   assertion).
6. A missing/corrupt page file yields a placeholder; zero pages yields an empty
   state; a **failed page load yields a retryable error state**
   (`page-viewer-error` + `page-viewer-retry`); never a crash or a hang.
7. Tier-2 integration passes on emulator + iOS sim (open → view → delete → gone).
8. EXIF-clean + transactional + B2 list guarantees regression-pass (privacy
   spine intact).
9. *(REAL_DEVICE, deferred)* pinch-zoom magnifies + upright render.
10. *(REAL_DEVICE, deferred)* a true OS-kill after delete still shows it gone.

Criteria 1–8 are gated host/emulator/sim (5 with the stated review-enforced
caveat). Criteria 9–10 are the opt-in REAL_DEVICE lane, deferred-with-sign-off
consistent with B1/B2.

## Known gaps / non-goals (explicit)

- No rename, share/export, multi-page capture, page reorder, OCR, orphan-file
  sweep, immersive system-chrome hiding, or a11y/semantics polish.
- Full-res decode is **not** memory-safe for many pages; the viewer needs decode
  management when multi-page capture lands (see the viewer note).
- Orphan-safety worst case is review-enforced, not test-gated (criterion 5).
- Tier-3 OS-kill + pixel zoom are **manual** REAL_DEVICE checks, not gated.

## Privacy spine (binding, unchanged)

Documents never leave the device. No cloud, no network calls. The viewer renders
the same on-device files; delete removes local data only. Nothing is uploaded,
shared, cached off-device, or indexed externally.
