# D1 — Rename document (design)

**Status:** approved (design phase)
**Date:** 2026-06-29
**Roadmap:** group **D (library management)**, step **D1** — rename a saved document.
**Depends on:** B1 (storage, `DocumentRepository`, Drift; `documents.name` + `modifiedAt` columns already exist), B3 (`PageViewerScreen` AppBar title = name; `HomeScreen` library list), C1/C2 (export/preview — touched only by the `_name` fix below).
**Feeds:** D3 (sort, incl. by `modifiedAt`), later group D (folders/tags).

## Goal

Let the user change a document's display name from **two surfaces** — the viewer
AppBar and the library-list row menu — sharing **one dialog** and **one
repository method**. The name stays on-device (privacy spine). **No schema
change**: `documents.name` and `documents.modifiedAt` already exist;
`schemaVersion` stays `1`.

## Scope (locked)

**In:** rename from the viewer (AppBar action) and from the library list
(per-row overflow menu); one shared dialog (trim + non-empty + 100-char cap);
`repository.rename` updating `name` + `modifiedAt`; both surfaces reflect the new
name; failure → SnackBar.
**Deferred / non-goals:** name uniqueness, inline (in-place) list editing,
rename history/undo, folders/tags (later in D), sort-by-modified (D3 —
`modifiedAt` is bumped here but not yet surfaced in any list UI).

## Components (one responsibility each)

### 1. `repository.rename(int id, String newName) → Future<Document>`

New method on the `DocumentRepository` interface (the only persistence surface
the widget layer knows). Trims `newName`; bumps `modifiedAt` via the injected
clock; returns the updated `Document`. Throws a **new** `DocumentRenameException`
when the trimmed name is empty (fail-closed defense — a blank name can never be
written even if a caller skips client validation) or when no such row exists
(0 rows updated).

```dart
/// Renames [documentId] to [newName] (trimmed), bumping modifiedAt. Returns the
/// updated document. Throws [DocumentRenameException] if the trimmed name is
/// empty or no document with that id exists.
Future<Document> rename(int documentId, String newName);
```

```dart
class DocumentRenameException implements Exception {
  final String message;
  const DocumentRenameException(this.message);
  @override
  String toString() => 'DocumentRenameException: $message';
}
```

Drift implementation (`DriftDocumentRepository`):

```dart
@override
Future<Document> rename(int documentId, String newName) async {
  final trimmed = newName.trim();
  if (trimmed.isEmpty) {
    throw const DocumentRenameException('rename failed: empty name');
  }
  final modifiedUtc = _clock().toUtc();
  final updated = await (_db.update(_db.documents)
        ..where((t) => t.id.equals(documentId)))
      .write(DocumentsCompanion(
          name: Value(trimmed), modifiedAt: Value(modifiedUtc)));
  if (updated == 0) {
    throw const DocumentRenameException('rename failed: no such document');
  }
  final row = await (_db.select(_db.documents)
        ..where((t) => t.id.equals(documentId)))
      .getSingle();
  return Document(
      id: row.id,
      name: row.name,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt);
}
```

### 2. `showRenameDialog(BuildContext, String currentName) → Future<String?>`

The shared, reusable dialog (the **DRY** unit both surfaces call). Internally a
private `StatefulWidget` owning a `TextEditingController` (so it pre-fills **and
selects** the current name via `selection = TextSelection(0..len)`,
`autofocus: true`, disposed on close) and tracking the Save-enabled state.

- `maxLength: 100` on the field.
- Save **enabled iff** the trimmed value is non-empty.
- On Save: if `trimmed == currentName` → `pop(null)` (no write, no pointless
  `modifiedAt` bump); else `pop(trimmed)`.
- On Cancel: `pop(null)`.
- Returns the **trimmed** new name, or **null** (cancel *or* unchanged).
- Copy: title **"Rename document"**, actions **"Cancel"** / **"Save"**.
- Keys: `rename-dialog` / `rename-field` / `rename-cancel` / `rename-save`.

## The two surfaces

Both do the same thing — only the trigger differs:

```text
final name = await showRenameDialog(context, current);
if (name == null) return;                       // cancel or unchanged
try {
  final updated = await repo.rename(id, name);
  <reflect: viewer sets _name; list calls _load()>
} catch (_) {
  ScaffoldMessenger...showSnackBar("Couldn't rename");
}
```

### Viewer (`PageViewerScreen`)

- Add a rename `IconButton` (key `page-viewer-rename`, `Icons.edit_outlined`) to
  the AppBar, **leftmost** of the three actions (rename, then export, then
  delete). Guarded by `_loading || _error || _exporting` — **delete's guard**,
  not export's: an empty/0-page doc can still be renamed (delete is likewise
  enabled when empty). Rename follows delete's pattern (modal dialog +
  `mounted`-guarded async tail) — **no `_renaming` flag**; export has
  `_exporting` only because it stays on-screen showing progress.
- The title becomes **local state** `_name` (initialised `_name = widget.name`
  in `initState`); on success `setState(() => _name = updated.name)` so the
  AppBar updates live. The home list reloads on the viewer's pop, reflecting it
  there too.
- **`_name` replaces every `widget.name` use in the screen body** — both the
  AppBar `title` AND the `PdfPreviewScreen(name: …)` argument in `_exportPdf`.
  Otherwise a renamed-then-exported PDF preview shows the **stale** name. After
  this change `widget.name` appears **only** in the `_name = widget.name`
  initializer.

### List (`DocumentsListView` + `HomeScreen`)

- Each row gets a trailing **icon-only** `PopupMenuButton` (key
  `document-menu-${id}`, ⋮) with a single **Rename** item. The item carries its
  own key (e.g. `document-rename-${id}`) — **found by key, never by text**: an
  open menu shows the text "Rename" while the dialog title is "Rename document",
  so a `find.text('Rename')` would be ambiguous. The menu button is an icon with
  no visible text until opened, and a right-edge hit-target, so it neither adds a
  text node nor steals the tile's centre-tap `onTap`.
- New `onRename` callback (`ValueChanged<DocumentSummary>?`); when null the menu
  is omitted (for the isolated widget test).
- `HomeScreen._renameDocument(s)`: show dialog → `repo.rename` → on success call
  the existing `_load()` (no spinner — `_load()` doesn't set `_loading`; the list
  sorts by `createdAt`, which rename doesn't change, so order is stable) →
  failure → "Couldn't rename" SnackBar.

## Migration surface (the C1 trap — replace, not scatter)

Adding `rename` to the interface is a **compile-break** until every implementer
has it. `grep` confirms the surface is **exactly three** (no other file
implements or constructs the repo):

1. **`DocumentRepository`** (interface) — add the method + `DocumentRenameException`.
2. **`DriftDocumentRepository`** — the real implementation above.
3. **`FakeDocumentRepository`** (`test/support/fake_library.dart`) — must both
   **mutate** its in-memory `documents` list (replace the `Document` with the new
   name + bumped `modifiedAt`, so the home `_load()` path reflects it) **and
   return** that updated `Document` (so the viewer's `_name = updated.name`
   works). Add a `throwOnRename` flag (for the failure-path widget tests) and a
   call record (e.g. `renamedNames` / last id+name) for assertions.
   `_FlakyPagesRepo extends FakeDocumentRepository` inherits `rename` — no change.

These land in **one task** so the tree compiles.

## Validation & error handling

- **Dialog:** trim; non-empty (Save disabled otherwise); 100-char cap;
  duplicates allowed (names aren't unique, like files); unchanged → no write.
- **Repository:** re-validates non-empty → `DocumentRenameException`; missing id
  → `DocumentRenameException`.
- **Failure** (either surface): "Couldn't rename" SnackBar, stay put, no crash.

## Testing (host vs device — TDD/BDD, both platforms)

### Repository (real in-memory Drift)
- renames + **bumps `modifiedAt`**: uses the **advancing-clock** pattern already
  in the file (`var t; clock: () => t`) — create at T1, rename at T2; assert
  `modifiedAt == T2` **and** `createdAt == T1`. (The shared `repo()` helper's
  clock is *fixed*, so it cannot show a bump — only this test uses the advancing
  clock.)
- trims surrounding whitespace; returns the updated `Document`.
- throws `DocumentRenameException` on empty/whitespace-only (fixed clock OK).
- throws `DocumentRenameException` on a non-existent id.

### Dialog (`showRenameDialog`, host widget)
- pre-filled **and fully selected**; Save disabled on empty/whitespace;
  returns the trimmed value; returns **null** on cancel; returns **null** when
  unchanged; 100-char cap enforced.

### Viewer (`PageViewerScreen`, host)
- rename action present and **guarded** (disabled in the error state — parallel
  to delete's existing test; **enabled when empty**, like delete — no
  empty-disabled test).
- confirm → calls `repo.rename` + the AppBar title updates to the new name.
- failure → "Couldn't rename" SnackBar, stays.
- **Extend the existing in-flight test** (`page_viewer_screen_test.dart`,
  "both AppBar actions are disabled while an export is in flight"): now assert
  **`page-viewer-rename` is also disabled** during export, and rename it to
  *"all AppBar actions are disabled while an export is in flight"*. (Otherwise the
  test's name lies and a rename-during-export regression goes uncaught.)

### List / Home (host)
- `DocumentsListView`: renders the per-row menu (key) when `onRename` is set,
  omits it when null; existing assertions (`findsNWidgets(2)` on the name text,
  centre-tap → `onOpen`) still hold (icon adds no text; right-edge hit-target).
- `HomeScreen`: open menu → Rename → enter a new name → `repo.rename` called +
  the new name shows in the list (via `_load()`; the fake mutated `documents`).
- failure → "Couldn't rename" SnackBar.

### Integration (Tier-2, android + ios) — `d1_rename.feature`
Renames via the **list overflow menu** (drives the most native-risky path on
device: overlay menu route **+** `enterText`). The viewer-rename trigger is the
lower-risk path and is fully host-covered.

```gherkin
Feature: Rename a document
  Scenario: Rename a document from the library list
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    And I open the rename menu for the first document
    And I rename the document to {'Field Notes'}
    Then I see {'Field Notes'} text
```

- After `I tap Accept` the app is back on **Home** with the doc listed (same as
  the C2 flow before `I open the first document`), so the scenario goes straight
  to the row menu — it does **not** reuse `i_open_the_first_document`.
- **Step text is punctuation-free / parameter-clean** to avoid the
  `bdd_widget_test` silent-empty-stub hazard (a step-name↔camelCase mismatch
  generates a vacuously-passing stub). No apostrophes; parameters use bdd's
  curly-brace form `{'…'}` (per the existing `i_see_text`).
- **New steps (two):**
  - `i_open_the_rename_menu_for_the_first_document.dart` →
    `iOpenTheRenameMenuForTheFirstDocument`: tap `document-menu-1`,
    `pumpAndSettle`, tap `document-rename-1`, `pumpAndSettle`.
  - `i_rename_the_document_to.dart` → `iRenameTheDocumentTo(tester, String name)`:
    `enterText` into `rename-field` (replaces the pre-filled text — no clear
    needed), `pumpAndSettle`, tap `rename-save`, `pumpAndSettle`.
- **Reused:** `i_see_text` (`Then I see {'Field Notes'} text`) for the assertion —
  no new assertion step. Plus the B1 capture steps
  (`the_app_is_launched_…_empty_storage`, `i_tap_the_scan_button`,
  `i_tap_the_shutter`, `i_tap_accept`).
- The BDD scenario runs on the **real** repo (`tempLibraryDependencies`), so
  `rename`'s real implementation is exercised on-device.

## Verification harness — `scripts/verify/d1.sh`

Built on `scripts/verify/lib.sh` (primitives confirmed against `c2.sh`):

- **Static asserts:** `rename(` on the repo interface + `DriftDocumentRepository`;
  `DocumentRenameException`; `showRenameDialog` exists; `rename-field` /
  `rename-save` keys; `page-viewer-rename` in the viewer; `document-menu-` in the
  list view; `schemaVersion => 1` unchanged; scrubber `minimalExifApp1` (privacy
  regression).
- **(A) guard invariant (grep-implementable):** assert `page_viewer_screen.dart`
  contains the initializer `_name = widget.name` **and** that `widget.name` occurs
  in the file **exactly once** (`[ "$(grep -c 'widget.name' …)" = "1" ]`). Today
  it occurs twice (the two uses being migrated); after the fix the only remaining
  occurrence is the initializer, so a count of 1 proves both the AppBar title and
  the `_exportPdf` preview argument now read `_name`. This locks the fix against
  silent regression without needing to scope a grep to a function body.
- **No-empty-stub guard** (mirrors `c2.sh:37–42`): the two new step files are
  real (`i_open_the_rename_menu_…` contains `document-rename-`;
  `i_rename_the_document_to` contains `enterText` + `rename-save`), and the
  generated `d1_rename_test.dart` calls `iOpenTheRenameMenuForTheFirstDocument(`,
  `iRenameTheDocumentTo(`, and `iSeeText(`.
- **Codegen current:** `dart run build_runner build` + no uncommitted diff for
  `d1_rename_test.dart` (drift `.g.dart` is unchanged — no schema bump).
- `mobile:test` (`--skip-nx-cache`) · `mobile:analyze` · `assert_coverage_floor 70`.
- `verify_integration_android d1_rename_test.dart` ·
  `verify_integration_ios d1_rename_test.dart`.
- **Fail-closed:** `VERIFY_SKIP_DEVICE=1 → GATE: FAIL` (never silent).
- **Opt-in REAL_DEVICE Tier-3:** manual — rename a doc, confirm the new name
  shows in the list and on the viewer AppBar on a physical device.

## Acceptance criteria

1. Rename from the **viewer** updates the AppBar title live and (on return) the
   list — *viewer host widget* (the device tier exercises the list path, not the
   viewer — see §Integration).
2. Rename from the **list** overflow menu updates that row — *list/home widget +
   integration (android + ios)*.
3. New name **persists** (survives reload/restart) and **bumps `modifiedAt`**
   (createdAt unchanged) — *repository (advancing clock)*.
4. Empty/whitespace-only is rejected (Save disabled; repo throws) — *dialog +
   repository*.
5. **Unchanged** name → no write — *dialog*.
6. Rename **failure** → SnackBar, no crash, stays put — *widget*.
7. A renamed doc's **PDF preview shows the new name** (the `_name` fix) —
   *covered by the (A) gate invariant + viewer host*.
8. **Privacy spine:** the name never leaves the device — *code review*.

Criteria 1–8 gated (render/visual confirmation of the name on a physical device
is the opt-in REAL_DEVICE Tier-3 lane, deferred-with-sign-off like B3/C1/C2).

## Privacy spine (binding, unchanged)

The name is read, edited, and written entirely **on-device** (Drift/SQLite).
Nothing is uploaded, shared, or sent off-device. No new dependency; no network
surface introduced.
