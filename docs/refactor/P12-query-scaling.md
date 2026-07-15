# P12 — Query & scaling

**Tier 4 (Perf) · Effort M · Risk Low · Depends on: P10 (soft, same-file lane); coordinate P05, P06 · Device verification: host + Android AND iOS**

> **Sequencing:** Independent of the safety/structure work; can run in parallel with P10/P05 but its DB
> changes are cleanest once `PageDao` (P05) exists — if P05 hasn't landed, apply the query changes
> directly on `DriftDocumentRepository`. The public `DocumentRepository` interface is unchanged; these
> are internal query-shape and UI-sorting-cost optimizations that preserve every documented contract and
> keep the heavy test suites green.

## Summary

Three scalability issues, all confirmed in source:

- **PERF-01 (LIVE cliff).** `_summaries` (:251–260) selects **every row of the Pages table** — no
  `where`, and it **ignores the `onlyIds` restriction** — just to find each document's first-page path.
  This runs on **every home load and every search** (search calls `_summaries(onlyIds: ...)`, but the
  page scan inside still reads all pages). Cost is O(total pages across the whole library) even when
  showing one search hit.
- **PERF-02 (N+1).** The export paths repeatedly re-query: `exportCombinedPdf` loops `getDocumentPages`
  per id (:392–394); `exportSeparatePdfs` loops `exportPdf` (:418–420); `exportAllPagesAsImages` calls
  `getDocumentPages` (:505) then `exportPageAsImage` **re-selects each page row** (:468–473 via :510–514);
  `_isIdCard` runs its own document query (:377–382); `_exportBaseName` runs its own (:449–457) — so
  `exportPdf` alone triggers two extra document queries. The document row + already-loaded pages should be
  fetched once and threaded through.
- **sort-on-build (LIVE).** `home_screen.dart` sorts in the build path: `_buildBody` calls
  `sortDocuments(_summaries, _sort)` at **:636**, and the `_displayed` getter re-sorts on **every access**
  at **:343–344**. So every unrelated `setState` (each search keystroke, selection toggle, view-mode
  switch) re-sorts the whole library. The sorted list should be computed **once** when `_summaries` or
  `_sort` changes and cached.

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
|----|------------------|--------------|--------|-------------|
| PERF-01 | `_summaries` :251–253 (`_db.select(_db.pages)..orderBy(position)` — **no `where`, ignores `onlyIds`**), used by home load (:143) + search (:188, :224) | Reads ALL page rows to build a first-page-path map, even when only a few docs are shown | O(all pages) DB read + decode on **every** home load and **every** search keystroke; degrades as the library grows | **live** (scalability cliff) |
| PERF-02a | `exportCombinedPdf` :392–394; `exportSeparatePdfs` :418–420; `exportAllPagesAsImages` :505 then `exportPageAsImage` re-selects :468–473 | Re-fetches pages already loaded; per-page row re-select in the all-images path | N+1 queries proportional to page count during export | live (perf) |
| PERF-02b | `_isIdCard` :377–382; `_exportBaseName` :449–457; both re-query `documents` per export | `exportPdf` issues 2 extra doc queries; every export re-reads the doc row | Redundant document queries per export | live (perf) |
| sort-on-build | `home_screen.dart` `_displayed` getter :343–344; `_buildBody` :636 | `sortDocuments(_summaries, _sort)` recomputed inside build / on every getter access | Whole-library re-sort on every unrelated `setState` (search keystroke, selection toggle, view-mode switch) | **live** (UI perf) |

## Definition of done

- **PERF-01:** `_summaries` fetches only the **first page per document** (lowest `position`), selecting
  only the path columns, and **honors `onlyIds`** (restrict the page query to the shown documents).
  Achieved via a correlated subquery / `GROUP BY documentId HAVING position = MIN(position)` (or a
  `MIN(position)` join), not a full-table scan. Output identical to today (same first-page path, count, order).
- **PERF-02:** Each export fetches the document row **once** and threads `name`/`isIdCard`; the
  already-loaded `List<PageImage>` is reused instead of re-`getDocumentPages`/re-selecting rows.
- **sort-on-build:** The sorted list is computed once when `_summaries` or `_sort` changes and cached in a
  field/controller; `build`/`_displayed` read the cached list. **No behavior change** to sort order.
- Interface unchanged; heavy repo suites + `home_screen_test.dart` green; device BDD green (Android + iOS).

## Before → After

| Aspect | Before | After |
|--------|--------|-------|
| `_summaries` page read | `SELECT * FROM pages ORDER BY position` (all rows, ignores `onlyIds`) | first-page-per-doc only (`MIN(position)`), path columns only, restricted by `onlyIds` |
| Page rows read per home load | O(all pages in library) | O(#documents shown) |
| Page rows read per search | O(all pages) even for 1 hit | O(#hits) |
| `exportPdf` doc queries | 2 extra (`_isIdCard` + `_exportBaseName`) | 1 doc fetch, threaded |
| `exportAllPagesAsImages` | `getDocumentPages` + N per-page re-selects | pages loaded once, reused |
| `exportCombinedPdf`/`Separate` | `getDocumentPages`/`exportPdf` per id | pages fetched once per id, threaded |
| Library re-sorts | every unrelated `setState` (keystroke/toggle/view-switch) | once per `_summaries`/`_sort` change (cached) |

## Tasks

### T12.1 — First-page-only query in `_summaries` (PERF-01) — highest impact
- **Scope:** Replace the all-pages scan (:251–260) with a query that returns, per document, the
  `flatRelativePath`/`relativeImagePath` of the page with `MIN(position)` — via a correlated subquery or a
  `GROUP BY documentId HAVING position = MIN(position)` join — selecting only the two path columns, and
  add a `WHERE documentId IN (onlyIds)` when `onlyIds != null`. Preserve the `flatRelativePath ?? relativeImagePath`
  precedence and the newest-doc-first ordering. If P05's `PageDao` exists, add the method there and call it.
- **Files:** `drift_document_repository.dart` (or `page_dao.dart` if P05 landed).
- **Test-first:** host test (in-memory drift DB) asserting: (a) the returned thumbnail path equals today's
  for multi-page docs (flat vs base precedence), (b) with `onlyIds` set, the page query does **not** read
  rows of excluded documents (spy/counter or a large-fixture timing/row-count assertion), (c) empty-page
  document → null thumbnail. Write it to FAIL against the current full-scan (assert restricted read).
- **Done:** no unconditional `SELECT * FROM pages`; `onlyIds` honored; outputs byte-identical.
- **Parallel-safe:** yes (isolated to `_summaries`). Coordinate only if P05 moves it to `PageDao`.

### T12.2 — Thread the document row through exports (PERF-02b)
- **Scope:** Fetch the `documents` row once at the top of each export method and pass `name` + `isIdCard`
  into `_pdfBuilder.build(...)` and the filename builder, replacing `_isIdCard` (:377) and `_exportBaseName`
  (:449) per-call re-queries. Keep `_exportBaseName`'s sanitization as a pure helper on the already-fetched name.
- **Files:** `drift_document_repository.dart` (or `document_exporter.dart` if P05 landed).
- **Test-first:** host test counting document-table queries per `exportPdf` call drops from 3→1 (spy DB),
  with identical output filename + id-card layout flag.
- **Done:** one doc fetch per export; `_isIdCard`/`_exportBaseName` no longer re-query.
- **Parallel-safe:** yes vs T12.1/T12.3. Coordinate with P05 T05.4 (same methods) — assign together if P05 concurrent.

### T12.3 — Reuse loaded pages in multi-page exports (PERF-02a)
- **Scope:** In `exportAllPagesAsImages`, build each image from the already-loaded `PageImage` list instead
  of calling `exportPageAsImage` (which re-selects the row): factor a private
  `_writePageImageFile(PageImage page, docBaseName, quality)` that both `exportPageAsImage` and the loop use,
  so the row is selected once. In `exportCombinedPdf`/`exportSeparatePdfs`, keep behavior but ensure pages
  are fetched once per document (thread the loaded list where the same doc is reused).
- **Files:** `drift_document_repository.dart` (or `document_exporter.dart` if P05 landed).
- **Test-first:** host test that exporting all pages of a 3-page doc issues **one** page-row read per page
  (not two), with identical files. Keep existing export tests green.
- **Done:** no redundant per-page re-select in `exportAllPagesAsImages`; combined/separate reuse loaded pages.
- **Parallel-safe:** coordinate with T12.2 (same methods) and P05 T05.4.

### T12.4 — Cache the sorted library list off the build path (sort-on-build)
- **Scope:** Compute `sortDocuments(_summaries, _sort)` **once** when `_summaries` or `_sort` changes
  (recompute in the setter/assignment at :136 and wherever `_sort` changes) and store it in a field
  (e.g. `_sortedSummaries`). Change `_displayed` (:343–344) and `_buildBody` (:636) to read the cached
  field instead of re-sorting. **Coordinate with P06:** P06 owns the `LibraryController` extraction —
  **P12 owns only the sorting-cost fix.** If P06 lands first, cache inside the controller; if P12 lands
  first, cache in the `State` field and hand it to P06 later.
- **Files:** `home_screen.dart` (or `LibraryController` if P06 landed).
- **Test-first:** widget test that toggling selection / switching view mode / typing (without changing
  `_summaries` or `_sort`) does **not** re-invoke `sortDocuments` (spy/comparator counter), while a
  `_sort` change **does** recompute; sort order visible to the user is unchanged.
- **Done:** `sortDocuments` runs once per `_summaries`/`_sort` change, not per build/getter access.
- **Parallel-safe:** yes vs T12.1–T12.3 (UI file). Coordinate ownership boundary with P06.

## Risks & mitigations

- **Risk:** The `MIN(position)` first-page query (T12.1) picks a **different** page than today if positions
  aren't strictly contiguous (they are renumbered on delete). → **Mitigation:** test asserts the returned
  path equals the current full-scan result across fixtures incl. reordered/deleted pages; `b3`/`m1` BDD.
- **Risk:** Correlated subquery / GROUP BY expressed in drift's query builder is awkward; a raw
  `customSelect` bypasses stream invalidation. → **Mitigation:** prefer the builder; if raw SQL is needed,
  it's a read-only `_summaries` query (no invalidation concern) — verify via existing home-load tests.
- **Risk:** Threading name/isIdCard (T12.2) changes an export filename or id-card layout. → **Mitigation:**
  export host tests assert identical filename + layout flag; `i1/j1` export BDD on device.
- **Risk:** Reusing loaded pages (T12.3) drops the per-page freshness of a re-select (e.g. a concurrent
  edit). → **Mitigation:** export is a read-snapshot operation; the current code already reads a stale
  `getDocumentPages` list at :505 — behavior is preserved, just without the redundant second read.
- **Risk:** Sort caching (T12.4) goes stale if a mutation updates `_summaries` without invalidating the
  cache. → **Mitigation:** recompute in the single assignment site (:136) + `_sort` change; test proves a
  `_summaries` change refreshes the cached list. Coordinate the ownership seam with P06 to avoid a double cache.

## Verification commands

```bash
# From apps/mobile/
flutter analyze && dart format lib test

# Host: query-shape + sort-caching tests + existing home/repo suites
flutter test test/features/library/drift_document_repository_test.dart
flutter test test/features/library/drift_document_repository_extra_test.dart
flutter test test/features/library/home_screen_test.dart
flutter test                                        # full host suite

# Device BDD — BOTH platforms (drift/sqlite native; first-page query + exports)
flutter test integration_test/b3_view_and_delete_device_test.dart -d <android-device-id>
flutter test integration_test/fts_search_device_test.dart         -d <android-device-id>
flutter test integration_test/o5_content_search_device_test.dart  -d <android-device-id>
flutter test integration_test/i1_export_device_test.dart          -d <android-device-id>
flutter test integration_test/m1_split_document_device_test.dart  -d <android-device-id>
# repeat each with -d <ios-device-id>
```
