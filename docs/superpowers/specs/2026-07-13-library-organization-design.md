# Library Organization — Folders + Tags + Smart Auto-Titles

**Status:** approved design (2026-07-13)
**Feature branch:** `feat/library-organization`

## 1. Goal & motivation

The library is a **flat list** today. `Documents` carries only
`name / createdAt / modifiedAt / isIdCard`; there is no hierarchy, no tags, no
favorites. This is invisible at 10 documents and painful at 200. This feature
adds on-device organization that respects the app's local-first ethos
("Your scans stay on your device — no account, no cloud"):

- **Folders** — a document lives in exactly one folder (like a filesystem).
  Flat, no nesting.
- **Tags** — a document carries zero or more cross-cutting labels.
- **Smart auto-titles** — suggest a document name from its OCR text; the user
  confirms or edits. Never applied silently.

Everything is pure local metadata. **No backend, no cloud, no account.**

## 2. Non-goals (YAGNI)

- No nested/sub-folders.
- No cloud, sync, or sharing of folders/tags.
- No folder colors or custom icons.
- No auto-*tagging* (auto-title only).
- Tags are **not** added to the FTS index (search stays name/OCR-based).
- No persistence of the active folder/tag filter across launches (resets, like
  the current sort state).

## 3. Data model (Drift `schemaVersion` 8 → 9)

Pure metadata. **No change to `DocumentFileStore` (on-disk images) or the FTS
triggers.**

- **`Folders`** table: `id` (autoinc), `name` (text), `createdAt` (dateTime, UTC).
  Flat — no parent column.
- **`Documents.folderId`** — new **nullable** `IntColumn` referencing
  `Folders(id)` with **`onDelete: KeyAction.setNull`**. `null` = "Unfiled".
  Deleting a folder never deletes documents; they fall back to Unfiled.
- **`Tags`** table: `id` (autoinc), `name` (text), `createdAt` (dateTime, UTC).
  Names are normalized (trimmed); duplicate creation is a no-op returning the
  existing tag.
- **`DocumentTags`** join table: `documentId` (→ `Documents`, `onDelete: cascade`),
  `tagId` (→ `Tags`, `onDelete: cascade`), composite primary key `(documentId, tagId)`.

### 3.1 Migration step (`if (from < 9)`)

Order matters:

1. `createTable(folders)`, `createTable(tags)`, `createTable(documentTags)`.
2. `addColumn(documents, documents.folderId)` — **after** `folders` exists,
   because the column carries a `REFERENCES folders(id)` clause.

**Verified constraints / risks:**

- SQLite `ALTER TABLE ADD COLUMN … REFERENCES folders(id) ON DELETE SET NULL`
  is legal **only** for a nullable column with default NULL (satisfied here),
  and only under `PRAGMA foreign_keys = ON` (already set in `beforeOpen`).
  Whether drift's `addColumn` emits the `REFERENCES`/`ON DELETE SET NULL` clause
  intact on real sqlite **must be device-verified** (host + real Android/iOS).
- Deleting a document already cascade-deletes its `DocumentTags` rows
  automatically (FK cascade + pragma ON). `deleteDocument` therefore likely
  needs **no change**; a verifier confirms the existing delete tests stay green
  and no tag-link rows leak.

### 3.2 Migration tests that MUST be updated (three)

- `schema_migration_v7_test.dart:8` — asserts `schemaVersion == 8` → 9.
- `drift/migration_test.dart:240` — asserts `schemaVersion == 8` → 9; add a
  v8→v9 case (existing rows survive; new tables present; `folder_id` present
  and null).
- `drift/ocr_migration_test.dart` — builds a raw **v3** DB and steps the full
  `onUpgrade` chain to current; it now traverses v9. A mis-ordered v9 step
  (addColumn before createTable) fails here too — intended.

## 4. Repository surface (additive only)

**No existing method signature changes** — 4 classes implement
`DocumentRepository` (production `DriftDocumentRepository`, `FakeLibrary`, and
two test overrides), and Dart requires every implementer to satisfy the
interface. New methods are added and implemented in **all four**.

New methods on `DocumentRepository`:

- Folders: `listFolders()` → `List<Folder>`, `createFolder(String name)` → `Folder`,
  `renameFolder(int id, String name)`, `deleteFolder(int id)`,
  `moveToFolder(int documentId, int? folderId)` (`null` = Unfiled).
- Tags: `listTags()` → `List<Tag>`, `createTag(String name)` → `Tag`,
  `deleteTag(int id)`, `setDocumentTags(int documentId, Set<int> tagIds)`,
  `tagsForDocument(int documentId)` → `List<Tag>`.
- Auto-title: `suggestTitleFor(int documentId)` → `String?` — reads page-1
  `ocrText` and delegates to the pure `TitleSuggester`; returns `null` when OCR
  has not yet run or produces no usable title.

**Filtering is NOT a repository concern.** See §6.

### 4.1 `DocumentSummary` enrichment (optional fields only)

`DocumentSummary` gains two **optional** fields so all 11 construction sites and
the 4 fakes keep compiling with no edit:

```dart
final int? folderId;          // null = Unfiled
final List<Tag> tags;         // defaults to const []
```

`_summaries()` populates them with **no N+1**: one extra grouped query for
document→tags (mirroring the existing "first-page path" in-memory map), and
`folderId` read straight off the `documents` row.

## 5. Smart auto-titles

`TitleSuggester` is a **pure Dart** service (no DB, no native deps):

```dart
String? suggest(String ocrText);
```

Behavior: take the first meaningful line, strip noise, collapse whitespace,
cap length; return `null` for empty/garbage. Exhaustively unit-tested on host.

**Timing (corrected):** OCR runs **fire-and-forget** after save
(`_triggerOcr → runOcr().catchError`), and is skipped for the `NoOpOcrEngine`
used by host tests. So there is **no OCR text at the moment of save** and the
suggestion cannot be offered "at scan time." Instead the suggestion is offered
where OCR text is guaranteed to be persisted:

- The **rename dialog** shows a "Suggest name" affordance that calls
  `suggestTitleFor`; it is hidden/disabled while the result is `null` (OCR not
  ready or no usable title).

Non-destructive: the user always confirms or edits. The document keeps its
default `Scan <timestamp>` name until the user accepts a suggestion.

## 6. UI (single-screen model — no separate folder navigation)

`HomeScreen` already loads **all** summaries into `_summaries` and does sort +
search **in memory** (`_displayed`). Folder/tag filtering is likewise **pure
in-memory** over the enriched summaries — no new repository query methods, and
folder chip counts compute in memory.

- **Folder filter bar** under the search field: `All · Unfiled · <folder> (n)… · ＋`.
  Single-select; sets the active folder filter. **Rendered only when ≥1 folder
  exists** (so libraries with no folders look byte-identical to today, keeping
  existing home tests green).
- **Tag filter**: a filter affordance opening a bottom sheet of tag chips
  (multi-select, AND). **Rendered only when ≥1 tag exists.**
- **Document card**: small tag chips.
- **Move / manage-tags**: added to the existing per-document context menu
  (alongside rename/share/delete) and to the selection-mode bar (bulk move /
  bulk tag).
- **`_displayed` integration**: the active folder/tag filter is applied to
  `_displayed`, so selection-mode export operates on exactly the visible set.
  Search results are also post-filtered in memory by the active filter.

### 6.1 Feature flags

Three new build-time flags in `FeatureFlags`, default **on**:
`FEATURE_FOLDERS`, `FEATURE_TAGS`, `FEATURE_SMART_TITLES`. Each gates **every**
entry point for its capability (folder bar, tag sheet, per-doc menu items,
selection-bar bulk actions, rename-dialog suggest button). Threaded through
`LibraryDependencies.features` — never read as a bare global.

## 7. Testing (TDD + BDD, both platforms — non-negotiable)

- **TDD host (in-memory Drift):** `TitleSuggester` (many pure cases); folder &
  tag CRUD; `moveToFolder`/`setDocumentTags`; `setNull` on folder delete; tag
  cascade on document delete; `DocumentSummary` enrichment (folderId + tags,
  no N+1); the three migration tests updated + a v8→v9 case.
- **BDD host (`test/bdd/**`, counts toward coverage):** create folder, move a
  document into a folder, filter by folder, create/add a tag, filter by tags,
  suggest a title in the rename dialog. `bdd_widget_test`-generated
  `*_test.dart`; steps shared in `test/step/`; regenerated via `build_runner`.
- **Device (Android + iOS):** one `integration_test/*_device_test.dart` proving
  the v8→v9 migration runs on real sqlite (root-isolate open), folder/tag
  membership survives relaunch, and the seed/screenshot harness still opens the
  v9 DB. Auto-title exercised with real ML Kit OCR.

## 8. Parallel decomposition (independent subagent tasks + independent verifiers)

**Wave 0 — foundation (1 task, unblocks the rest):** schema + v9 migration +
`@DriftDatabase` update + `build_runner` regen + new models (`Folder`, `Tag`) +
optional `DocumentSummary` fields + update the three migration tests + a v8→v9
migration test. Must land first.

**Wave 1 — parallel (depend only on Wave 0 + interface):**
- T1: repo **folder** methods + host tests.
- T2: repo **tag** methods (incl. `setDocumentTags`, cascade) + host tests.
- T3: `DocumentSummary` **enrichment** in `_summaries()` (folderId + tags) + tests.
- T4: pure **`TitleSuggester`** + exhaustive unit tests (no schema dep — may
  start immediately) + `suggestTitleFor` repo method.
- T5: **feature flags** (`FEATURE_FOLDERS/TAGS/SMART_TITLES`) threaded through
  `LibraryDependencies` + tests.
- T6: implement the new interface methods as no-ops/simple in **all 4 fakes**
  (keeps the suite compiling; done alongside whichever task adds each method).

**Wave 2 — parallel UI (depend on Wave 1):**
- U1: folder filter bar + create-folder dialog + in-memory folder filter on
  `_displayed` + host BDD.
- U2: tag filter sheet + tag chips on cards + in-memory tag filter + host BDD.
- U3: move-to-folder + manage-tags in per-doc menu **and** selection bar + BDD.
- U4: rename-dialog "Suggest name" wiring + BDD.

**Wave 3 — parallel verification (do NOT trust "done"):** each impl task is
checked by a **separate** verifier that re-runs the tests and reads the diff
adversarially.
- V1: migration / data-loss review (ordering, `setNull` vs cascade, FTS
  untouched, three migration tests updated).
- V2: repo SQL / transaction review (N+1, tag cascade, no signature drift).
- V3: UI + flag-gating + BDD-coverage review (every entry point gated;
  conditional rendering keeps existing tests green; `_displayed`/selection
  correctness).
- V4: **device run on Android + iOS** (migration on real sqlite, persistence
  across relaunch, seed/screenshot harness, auto-title with real OCR).
- V5: full host suite + `flutter analyze` (zero-warning bar) + coverage gate
  (`scripts/coverage.sh`).

## 9. Definition of done

Nothing is "done" until: TDD unit/widget tests green on host; host BDD
scenarios green; the device integration test green on a **real Android device
AND a real iOS device** (or an explicit, named gap); `flutter analyze` clean;
coverage gate holds; and every verifier (V1–V5) has independently confirmed the
work it reviewed. Evidence (exact commands + green output) before any "done".
