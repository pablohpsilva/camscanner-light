# P10 — Repository DRY

**Tier 3 (DRY) · Effort S–M · Risk Low · Depends on: P00 (TempFileWriter, AppLogger) for DUP-04/SAFE-03 · Device verification: Android AND iOS**

> **Sequencing:** This is the **first** persistence-layer refactor to land. Every task here is a
> mechanical, behavior-preserving extraction of duplicated logic into private helpers on the existing
> `DriftDocumentRepository`. It deliberately precedes the big class-splitting work (P05) and the
> transaction-boundary changes (P03) so those land on a smaller, de-duplicated surface. Nothing here
> changes the public `DocumentRepository` interface (24 methods) or on-disk/DB behavior.

## Summary

`DriftDocumentRepository` (1242 LOC) has accumulated substantial copy-paste: eight near-identical
"fetch the page row or throw" blocks, two ~30-line page-copy loops (merge/split), a duplicated
enhancer-mode decode, five temp-export-file boilerplate blocks with **inconsistent** exception
semantics, two inline `'documents/$id/page_...jpg'` path builders that bypass `DocumentFileStore`,
a hand-rolled row-by-row renumber in `deletePage`, and four silent `catch` blocks that hide
derivative/OCR failures. This plan extracts each into a single, tested private helper — reducing
LOC, removing latent divergence bugs (a missed column, an inconsistent rethrow, a bypassed store),
and adding observability — **without touching the public interface**, so the full existing test
suite (`drift_document_repository_test.dart` 796 LOC, `..._extra_test.dart` 645 LOC,
`migration_test.dart` 441 LOC, plus BDD) stays green.

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
|----|------------------|--------------|--------|-------------|
| DUP-01 | `select(pages)..where(documentId & position)..getSingleOrNull()` + null-throw at **:314, :468, :519, :664, :698, :752, :850, :918**; max-position dup at **:791, :1008** | 8 copy-pasted "require page" blocks; **6 throw `DocumentSaveException`, 2 throw `DocumentExportException`** (`exportPageAsImage`:468, `exportRecognizedText`:519). Max-position lookup duplicated twice. | ~90 LOC of duplication; a future edit to one block silently diverges the others | live (works today, maintenance hazard) |
| DUP-02 | `mergeInto` :1024–1053 and `splitAfter` :1107–1137 | Duplicated page-copy loop: read bytes → `writeRelative` → conditional flat copy → `PagesCompanion.insert` copying `corners`/`flatRel`/`ocrText`/`ocrBoxes`/`rotationQuarterTurns`/`enhancerMode`. | A column added to one path but not the other **silently drops** a merged/split page's enhancer or rotation | latent (correct today; drifts on next column add) |
| DUP-03 | static `_modeOf` :653–656 vs inline decode in `getDocumentPages` :292–296 | `enhancerMode` int→enum bounds-checked decode duplicated in two forms | Divergent bounds handling risk | live |
| DUP-04 | temp-export boilerplate at :367, :400, :436, :489, :538 | **Inconsistent rethrow:** `exportPdf`:372 has **no** `if (e is DocumentExportException) rethrow` guard (double-wraps a thrown export exception), `exportProtectedPdf`:442 **has** it, `exportRecognizedText`:543 **lacks** it | Inconsistent error message nesting across export methods; hard to reason about | live (observable in wrapped exception text) |
| SAFE-05 | `mergeInto` :1027 and `splitAfter` :1109 | Base image paths built by inline interpolation `'documents/$id/page_..jpg'`, **bypassing `DocumentFileStore.relativeFor`**. (Flat paths correctly use `flatForImage`.) | Path convention lives in two places; a store-path change silently misses these | live (works; convention-drift hazard) |
| CPLX-02 | `deletePage` :861–866 (pre-fetch all rows) + :872–878 (row-by-row `UPDATE` loop) | Fetches every page row just to count, then renumbers survivors one UPDATE per row | O(pages) round-trips + wasted fetch for a job one bulk `UPDATE` does | live (perf, small docs mask it) |
| SAFE-03 | `catch (_) { flatRel = null; }` at :108 and :816; `runOcr` trigger `.catchError((_) {})` at :1181; `_deleteTempSource` `catch (_)` at :1196 | Broad, silent catches: a page can be saved with **no derivative** and nothing is logged; OCR/temp-cleanup failures vanish | Silent data-quality loss; undebuggable field reports | live (silent by design; needs observability, not behavior change) |

## Definition of done

- Public `DocumentRepository` interface unchanged (24 methods, identical signatures + doc contracts).
- New private helpers on `DriftDocumentRepository` (or small file-private classes): `_requirePage`,
  `_maxPositionPage`, `_cloneSourcePage`, `_copyPageFiles`, `EnhancerMode.fromIndex`,
  `_writeTempExport`, plus routed base-path builder + bulk renumber.
- **DUP-04** exception semantics are **uniform** across all five export methods (single rethrow rule).
- **SAFE-05** base paths flow through `DocumentFileStore` (new store method if needed), never inline.
- **CPLX-02** renumber is a single bulk `UPDATE ... WHERE documentId=? AND position>?`.
- **SAFE-03** catches log via `AppLogger` (from P00) and narrow to the expected exception types,
  while preserving the "OCR/derivative/cleanup never fails a save" guarantee.
- TDD: each helper has a failing host unit test written first; existing suite stays green.
- BDD device runs green on Android AND iOS: `b3_view_and_delete`, `l1_merge_documents`,
  `m1_split_document`, `i1/j1` export scenarios.

## Before → After

| Aspect | Before | After |
|--------|--------|-------|
| "require page row" blocks | 8 copy-pasted, mixed exception type | 1 `_requirePage(docId, pos, op, {exportContext})` |
| max-position lookup | 2 inline copies (:791, :1008) | 1 `_maxPositionPage(docId)` |
| merge/split page copy | 2 × ~30-LOC loops | `_cloneSourcePage(...)` + `_copyPageFiles(...)` |
| enhancer decode | `_modeOf` + inline | `EnhancerMode.fromIndex(i)` (one impl) |
| temp-export boilerplate | 5 blocks, inconsistent rethrow | `_writeTempExport(prefix, name, write)`, uniform semantics |
| base image path | inline `'documents/$id/...'` × 2 | `DocumentFileStore.relativeFor` / new store method |
| deletePage renumber | pre-fetch all + N UPDATEs | 1 bulk `UPDATE` |
| failure visibility | 4 silent `catch (_)` | narrowed catches + `AppLogger` |
| approx LOC | ~1242 | ~1120–1150 (net −90…−120), lower defect surface |

## Tasks

> All tasks operate on `.../drift/drift_document_repository.dart` unless noted. Each is behind the
> stable interface, so each can be a separate subagent PR against the same file — **coordinate merges**
> because they touch overlapping regions. Where two tasks touch the same method, the dependency is
> noted; otherwise they are parallel-safe.

### T10.1 — Extract `_requirePage` + `_maxPositionPage` (DUP-01)
- **Scope:** Replace the 8 "fetch page or throw" blocks (:314, :468, :519, :664, :698, :752, :850, :918)
  with one private `_requirePage(int docId, int pos, String op, {bool export = false})` that throws
  `DocumentExportException` when `export` is true (for :468, :519), else `DocumentSaveException`.
  Replace the two max-position lookups (:791, :1008) with `_maxPositionPage(int docId)`.
- **Files:** `drift_document_repository.dart`.
- **Test-first:** Add host unit tests asserting the **exact** exception type + message for a missing
  page in each of the two export methods vs a save method (guards the type-parameterization).
- **Done:** All 8 call sites + 2 max-position sites use the helpers; exception types unchanged from today.
- **Parallel-safe:** Yes, but touches many methods — land early to reduce later conflicts.

### T10.2 — `EnhancerMode.fromIndex` (DUP-03)
- **Scope:** Add `static EnhancerMode fromIndex(int i)` to `enhancer_mode.dart` (bounds-checked, → `none`).
  Replace `_modeOf` (:653) and the inline decode in `getDocumentPages` (:292–296) with it.
- **Files:** `enhancer_mode.dart`, `drift_document_repository.dart`.
- **Test-first:** Host unit test on `EnhancerMode.fromIndex` for in-range, `-1`, and `>= length`.
- **Done:** Single decode impl; `_modeOf` removed.
- **Parallel-safe:** Yes (isolated).

### T10.3 — Route merge/split base paths through the store (SAFE-05)
- **Scope:** Replace inline `'documents/$targetDocumentId/page_m..._....jpg'` (:1027) and
  `'documents/$newId/page_$k.jpg'` (:1109) with `DocumentFileStore` calls. `relativeFor(docId, pos)`
  covers the split case; for the merge case's collision-avoiding name (`page_m<src>_<pos>`) add a
  store method e.g. `mergedRelativeFor(int docId, int sourceDocId, int sourcePosition)` so the naming
  convention lives only in the store.
- **Files:** `document_file_store.dart` (new method), `drift_document_repository.dart`.
- **Test-first:** Host unit test on the new store method's exact output string (freeze the convention).
- **Done:** No inline `'documents/...'` interpolation remains in the repository.
- **Parallel-safe:** Coordinate with T10.4 (both edit merge/split bodies) — do T10.3 then T10.4, or one subagent does both.

### T10.4 — Extract `_cloneSourcePage` + `_copyPageFiles` (DUP-02)
- **Scope:** Extract the page-copy loop shared by `mergeInto` (:1024–1053) and `splitAfter` (:1107–1137)
  into `_copyPageFiles(src, imageRel)` (returns `flatRel?`) and `_cloneSourcePage(src, {docId, position, imageRel, flatRel})`
  (returns the `PagesCompanion` copying **all** carried columns). Both call sites use the same helper so
  a future column is added once.
- **Files:** `drift_document_repository.dart`. **Uses** the store method from T10.3.
- **Test-first:** Host test that a cloned companion carries `corners`, `flatRel`, `ocrText`, `ocrBoxes`,
  `rotationQuarterTurns`, `enhancerMode` (asserts no column dropped).
- **Done:** One copy loop; merge + split both delegate.
- **Parallel-safe:** Depends on T10.3 (shared regions). Independent of all other tasks.

### T10.5 — Extract `_writeTempExport` with uniform semantics (DUP-04)
- **Scope:** Introduce `_writeTempExport(String prefix, String fileName, FutureOr<void> Function(File) write)`
  built on **P00 `TempFileWriter`**. Route `exportPdf` (:367), `exportCombinedPdf` (:400),
  `exportProtectedPdf` (:436), `exportPageAsImage` (:489), `exportRecognizedText` (:538) through it.
  Standardize the rethrow rule: a thrown `DocumentExportException` is **never re-wrapped** (fix the
  missing guards at :372 and :543 to match :442).
- **Files:** `drift_document_repository.dart` (consumes P00 `TempFileWriter`).
- **Test-first:** Host test that each export method, when its inner `write`/build throws a
  `DocumentExportException`, propagates it **un-nested** (single, not double-wrapped) — this test
  should FAIL against today's :372/:543 and pass after.
- **Done:** All five export methods share the helper; exception nesting uniform.
- **Depends on:** P00 `TempFileWriter`. **Parallel-safe** vs T10.1–T10.4.

### T10.6 — Bulk renumber in `deletePage` (CPLX-02)
- **Scope:** Replace the pre-fetch-all-rows (:861–866) + row-by-row UPDATE loop (:872–878) with a single
  bulk statement `UPDATE pages SET position = position - 1 WHERE documentId = ? AND position > ?`
  (via `customStatement`/`customUpdate`). Keep the "delete document when it was the only page" branch.
  Still fetch the single target row via `_requirePage` (T10.1) for the missing-page throw + file cleanup paths.
- **Files:** `drift_document_repository.dart`.
- **Test-first:** Host test deleting a middle page of a 3-page doc asserts survivors renumber to
  contiguous 1..N-1 and `modifiedAt` bumps; deleting the only page deletes the document.
- **Done:** No survivor loop; one bulk UPDATE. (Note: `reorderPages` renumber is **out of scope** — P12.)
- **Parallel-safe:** Yes (only edits `deletePage`).

### T10.7 — Narrow + log the silent catches (SAFE-03)
- **Scope:** Using **P00 `AppLogger`**, replace `catch (_) { flatRel = null; }` at :108 and :816,
  `.catchError((_) {})` at :1181, and `_deleteTempSource`'s `catch (_)` at :1196 with narrowed catch
  types that **log** the failure (level: warning for derivative/OCR, info for temp cleanup) while
  preserving the guarantee that a save is never failed by a derivative/OCR/cleanup error.
- **Files:** `drift_document_repository.dart` (consumes P00 `AppLogger`).
- **Test-first:** Host test injecting a failing processor/`_writeFlat` asserts the save still succeeds
  (page persisted with `flatRelativePath == null`) **and** the injected logger received one warning.
- **Done:** No bare `catch (_)`/`catchError((_){})` in these four spots; save-never-fails guarantee intact.
- **Depends on:** P00 `AppLogger`. **Parallel-safe** vs others.

## Risks & mitigations

- **Risk:** Parameterizing the exception type in `_requirePage` (T10.1) accidentally flips a
  save-method throw to `DocumentExportException` or vice-versa. → **Mitigation:** test-first pins the
  exact type per call site; the existing 1441-LOC repo test suite already asserts many of these.
- **Risk:** `_cloneSourcePage` (T10.4) omits a column, silently corrupting merged/split pages.
  → **Mitigation:** the "all columns carried" host test + existing `l1_merge`/`m1_split` device BDD.
- **Risk:** Bulk renumber (T10.6) uses a raw statement that skips drift's stream invalidation.
  → **Mitigation:** verify via existing `getDocumentPages` assertions in host tests; run `b3` device BDD.
- **Risk:** Uniform rethrow (T10.5) changes an exception **message** some test asserts on.
  → **Mitigation:** grep the test suite for the current double-wrapped message strings before landing;
  adjust only where the fix is the intended behavior (and note it in the PR).
- **Risk:** Overlapping edits (T10.1 touches most methods; T10.3/T10.4 both touch merge/split).
  → **Mitigation:** land T10.1 first; assign T10.3+T10.4 to one subagent or serialize their merges.

## Verification commands

```bash
# From apps/mobile/
flutter analyze                                   # zero-warning bar
dart format lib test

# Host unit + widget suite (the heavy repo suites must stay green)
flutter test test/features/library/drift_document_repository_test.dart
flutter test test/features/library/drift_document_repository_extra_test.dart
flutter test test/features/library/migration_test.dart
flutter test                                      # full host suite

# Device BDD — BOTH platforms (drift/sqlite is native)
flutter test integration_test/b3_view_and_delete_device_test.dart   -d <android-device-id>
flutter test integration_test/l1_merge_documents_device_test.dart   -d <android-device-id>
flutter test integration_test/m1_split_document_device_test.dart    -d <android-device-id>
# repeat each with -d <ios-device-id>
```
