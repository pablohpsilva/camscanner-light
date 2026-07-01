# O5 — Library search by content (name + OCR text) (design)

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 2 — OCR / text extraction (Feature 08) → feeds Feature 02 (library search)
**Depends on:** O1 (per-page `ocrText` persistence), O2 (real OCR auto-runs after save)
**Feeds:** the third and last of Feature 08's outputs — *"content-search index for the library (Feature 02)"*.

## Purpose

OCR runs automatically and caches each page's text (O2), that text is selectable
in exported PDFs (O3) and viewable/copyable in-app (O4). The remaining OCR output
is **finding a document by the words inside it**. This slice adds library search
that matches a query against both the **document name** and any **page's
recognized OCR text**, surfacing matching documents in the home list. Everything
stays on-device.

## Scope

**In:**
- A repository `searchDocuments(query)` returning the same `DocumentSummary`
  shape as `listDocumentSummaries`, for documents whose **name** or any **page
  `ocrText`** contains the query (case-insensitive substring).
- A **search field** on the home screen: a toggleable AppBar search that filters
  the document list live as the user types; clearing/closing restores the full
  list; a distinct empty state when nothing matches.

**Out (later / separate):**
- Highlighting the matched snippet / jump-to-page (nice-to-have follow-up).
- Full-text ranking / relevance scoring (substring match is enough at phone
  scale; results stay newest-first).
- Fuzzy/typo-tolerant matching, search history, filters by date/type.
- A dedicated FTS5 index — a `LIKE` scan is fine for a personal scanner's
  library size; revisit only if libraries grow large.

## UX

### Home AppBar
- The `Documents` AppBar gains a **search icon** (`documents-search`,
  `Icons.search`). Tapping it enters **search mode**: the title is replaced by a
  `TextField` (`documents-search-field`, autofocus, hint *"Search documents"*),
  the leading widget becomes a back/close arrow (`documents-search-close`) that
  exits search mode, and a trailing **clear** button (`documents-search-clear`)
  empties the field. This toggle pattern is the standard, most-efficient search
  affordance and renders identically on iOS and Android.
- While in search mode the **sort bar is hidden** (results are inherently
  recency-ordered; re-introducing sort here is scope creep). Exiting search
  restores the sort bar and the user's chosen sort.

### Behavior
- Typing filters the list **live**. On each change the screen calls
  `repository.searchDocuments(currentText)` and renders the results.
- **Empty query** (field empty or whitespace) shows the **full list** again
  (same as not searching).
- **No matches** shows a centered empty state (`documents-search-empty`):
  *"No documents match \"<query>\"."*
- **Race guard:** results are applied only if the query that produced them still
  equals the field's current text — a slower earlier query can't overwrite a
  newer one. (No debounce: a local SQLite `LIKE` at phone scale is sub-ms;
  KISS over a timer.)
- Opening a result and coming back preserves search mode and re-runs the query
  (a delete/rename may have changed matches).

## Architecture

- **`DocumentRepository.searchDocuments(String query) → Future<List<DocumentSummary>>`**
  (new interface method):
  - `query.trim()` empty → delegates to `listDocumentSummaries()` (identical
    result), so the caller has one code path.
  - Otherwise **two steps** (the two-step split is required for a correct page
    count — see below):
    1. **Match document ids** — a joined+grouped query returns the ids of
       documents where `documents.name LIKE '%q%'` **OR** any joined
       `pages.ocrText LIKE '%q%'`. `q` is the trimmed query wrapped in `%…%`.
       No `lower()`: SQLite `LIKE` is already case-insensitive for ASCII
       (`'%INVOICE%'` matches `invoice` and vice-versa). Grouping by
       `documents.id` yields each matching doc once (a doc with two matching
       pages appears once). If no ids match, return `[]` early.
    2. **Build summaries for those ids** via `_summaries(onlyIds: matchedIds)`.
  - **Why two steps (not one grouped query with the WHERE inlined):** the page
    count is `pages.id.count()`. If the `name/ocrText LIKE` filter were applied
    *before* grouping, a document that matches only through one page's `ocrText`
    would have its non-matching page rows filtered out, so its count would be 1
    even with several pages. Matching ids first, then counting **all** pages of
    those ids in step 2, keeps `pageCount` correct.
- **DRY:** `listDocumentSummaries` is refactored to delegate to a private
  `_summaries({Set<int>? onlyIds})` (null = all). The only change to its body is
  an optional `..where(documents.id.isIn(onlyIds.toList()))` on the grouped
  documents query when `onlyIds` is provided (no page-level filter, so the count
  is over all of each matched doc's pages). `searchDocuments` calls
  `_summaries(onlyIds: matchedIds)`. The existing `listDocumentSummaries` tests
  regression-guard the `onlyIds: null` path.
- **Known minor limitation:** the query is not escaped for `LIKE`
  metacharacters (`%`, `_`), so a query literally containing them behaves as a
  wildcard. Acceptable for a personal scanner's word search; escaping (with
  `ESCAPE`) is a follow-up if it ever matters.
- **Home screen** gains `_searching` / `_query` state, a `_runSearch(query)`
  (race-guarded), and swaps the AppBar + body between normal and search modes.
  The list widget (`DocumentsListView`) is reused unchanged for results.

## Data flow

```
type "invoice" ─▶ HomeScreen._runSearch('invoice')
                    └─ repo.searchDocuments('invoice')
                         ├─ trim empty? → listDocumentSummaries()
                         └─ else: ids where name/ocrText LIKE %invoice% (distinct)
                                   → _summaries(onlyIds: ids) → newest-first summaries
                  ─▶ (query still current?) setState(list) ─▶ DocumentsListView | search-empty
```

## Error handling

- `searchDocuments` DB failure → the home surfaces the existing documents-error
  state (same path as `_load`), with retry.
- Race guard prevents stale overwrites; no partial/torn UI.

## Testing strategy (TDD/BDD first)

**Unit (host `flutter test`):** against a `NativeDatabase.memory()` Drift repo
seeded with documents + pages (some with `ocrText`):
- matches by document name (case-insensitive);
- matches by a page's `ocrText` (case-insensitive) even when the name doesn't;
- a document with two pages both matching appears exactly once (DISTINCT);
- empty/whitespace query returns the same set as `listDocumentSummaries`;
- a non-matching query returns an empty list;
- results carry the correct pageCount + thumbnailPath (reused summary logic).

**Widget (host `flutter test`):**
- tapping `documents-search` reveals `documents-search-field`;
- typing filters the list to the fake repo's returned matches;
- `documents-search-clear` empties the field and restores the full list;
- `documents-search-close` exits search mode (sort bar returns);
- a query with no matches shows `documents-search-empty`.
- No `Image.file` decode of real files (thumbnails use the existing
  `DocumentThumbnail`, which is null/placeholder-safe in host tests).

**BDD (`.feature` → on-device Samsung RZCY51D0T1K):**
- *Given a saved document whose page text is "INVOICE 2026", when I search
  "invoice", then I see that document; when I search "zzz", then I see the
  no-matches message.*
- Seeded via the persistent-storage pattern (a page row with `ocrText`), then
  the app launches reading that storage (reuse `the app launches reading that
  same storage`), per the BDD-seed-needs-app-launch rule.

## Cross-platform

Pure Dart/Flutter: a SQLite `LIKE` query and a Material `TextField` in the
AppBar. No platform channels; identical on iOS and Android.

## Definition of Done

- `searchDocuments` on the interface + Drift impl (+ fake), TDD-covered; the
  `listDocumentSummaries` refactor keeps its tests green.
- Home search mode (toggle, live filter, clear, close, empty state), widget-tested.
- `.feature` BDD generated and green on-device.
- `flutter analyze` clean; host suite green; `scripts/verify/o5.sh` passes on
  device; plans index updated.
