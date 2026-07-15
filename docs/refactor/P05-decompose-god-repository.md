# P05 — Decompose the God repository

**Tier 2 (SOLID) · Effort L · Risk Med · Depends on: P10 (de-dupe first), and lands after/independent of P03 (atomicity) · Device verification: Android AND iOS**

> **Sequencing:** The **largest** persistence refactor; runs **after** P10 (so extraction operates on a
> de-duplicated surface) and does not block P03 (P03's boundary fixes apply either to the monolith or,
> if P05 lands first, to whichever collaborator owns the op). The invariant throughout: the public
> `DocumentRepository` interface (24 methods) is **unchanged**, so the heavy suites
> (`drift_document_repository_test.dart` 796 LOC, `..._extra_test.dart` 645 LOC, `migration_test.dart`
> 441 LOC, plus BDD) stay green. Collaborators are extracted **behind** the interface; the repository
> becomes a **thin coordinator** that delegates.

## Summary

`DriftDocumentRepository` is a 1242-LOC God class: **one** class implementing **24** `@override`
methods with **9** injected/constructed collaborators (`_db`, `_scrubber`, `_fileStore`, `_clock`,
`_pdfBuilder`, `_processor`, `_ocrEngine`, `_encryptor`, `_compressor`). It mixes CRUD, FTS search +
query sanitization, the derivative (flat) pipeline, six export formats (PDF/combined/separate/protected/
image/text), OCR triggering, and page ordering/merge/split. It even statically imports concrete
PDF-encryption and image-compression implementations via constructor defaults. This plan extracts
cohesive collaborators — `PageDao`, `FtsQuerySanitizer`, `DocumentSearchService`, `DocumentExporter`,
`PageOrderingService`, `PageDerivativePipeline` (+ injectable `JpegRotator`) — each independently
unit-testable, and reduces the repository to a delegating coordinator. Concrete export impls move to the
composition root. The interface, and therefore behavior, is preserved.

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
|----|------------------|--------------|--------|-------------|
| GOD-01 | whole file, ctor :44–63, 24 `@override` methods | One class = CRUD + FTS + derivative pipeline + 6 export formats + OCR + ordering, with 9 collaborators | Untestable in isolation; every concern shares one 1242-LOC surface; violates SRP | live (maintainability) |
| SAFE-06 | `_ftsOps`:146, `_ftsKeywords`:147, `_searchTerms`:151–155, `searchDocuments`:158, `_searchByLike`:173, `_searchRanked`:193–230; MATCH expr `terms.map((t)=>'"$t"').join(' AND ')` :197; LIKE `%$q%` :174 & :210 | FTS query sanitization (the security-sensitive part — prevents FTS syntax/injection into `MATCH`) is embedded in the repo, not a testable unit | Injection-safety logic can't be exhaustively unit-tested on its own; changes risk regressions | live (security-adjacent) |
| SOLID-02 | ctor defaults `const SyncfusionPdfEncryptor()` :53, `const ImageLibraryCompressor()` :54, `DartPageProcessor(warper)` :60 | Persistence layer statically imports PDF-encryption + compression impls (DIP inversion at construction) | `drift_document_repository.dart` transitively depends on syncfusion + image-compression code; can't swap without editing persistence | live (coupling) |
| TEST-01 | `_writeFlat` calls `compute(rotateAndBakeJpeg, ...)` directly :606; top-level fn :1231–1242 | Rotation is not injectable → any test of rotation must run on a device | Forces device tests for a pure transform; slows TDD | live (testability) |
| CPLX-01 | `_writeFlat` :583–642 | One method mixes fast-path skip / off-isolate rotate / fullframe-vs-crop / enhance-with-fallback / flat-vs-null return (`flatBytes = ... ?? rotatedBytes`; then `if (flatBytes==null){delete;return null}`) | High branching density; the `?? rotatedBytes ?? null` fallthrough is easy to break | live (complexity) |

## Definition of done

- Public `DocumentRepository` interface unchanged; `DriftDocumentRepository` still `implements` it and is
  the only type the widget layer sees. All 24 methods delegate to collaborators.
- New collaborators, each with its own host unit tests:
  - **`PageDao`** — the drift page/document row queries (`_requirePage`, `_maxPositionPage`,
    getDocumentPages mapping, position renumber, insert/update/delete) behind a plain interface.
  - **`FtsQuerySanitizer`** — a **pure value object**: raw query → `{terms, matchExpr, likePattern,
    useLike}` with **exhaustive** host unit tests (SAFE-06).
  - **`DocumentSearchService`** — owns `searchDocuments`/`_searchByLike`/`_searchRanked`, uses the
    sanitizer + `PageDao`/DB for the ranked bm25 + name-first merge.
  - **`DocumentExporter`** — owns all six export formats + `_isIdCard`/`_exportBaseName`/`_pdfFileNameFor`;
    **holds** `_pdfBuilder`, `_encryptor`, `_compressor`, `_scrubber` and the temp-file writer.
  - **`PageOrderingService`** — `reorderPages`, `deletePage` renumber, `mergeInto`, `splitAfter` sequencing.
  - **`PageDerivativePipeline`** — `_writeFlat` split into explicit stages; depends on an injectable
    **`JpegRotator`** (default wraps `compute(rotateAndBakeJpeg, ...)`).
- **SOLID-02:** `SyncfusionPdfEncryptor`/`ImageLibraryCompressor`/`DartPageProcessor` defaults move to the
  composition root (`LibraryDependencies` / `main.dart` wiring); persistence no longer statically imports them.
- **TEST-01/CPLX-01:** rotation is injectable; `_writeFlat` is decomposed into named stages inside the pipeline.
- TDD failing-first for every new collaborator; existing suites + BDD green on Android AND iOS.

## Before → After

| Aspect | Before | After |
|--------|--------|-------|
| Classes | 1 God class | thin coordinator + **6** focused collaborators (`PageDao`, `FtsQuerySanitizer`, `DocumentSearchService`, `DocumentExporter`, `PageOrderingService`, `PageDerivativePipeline` + `JpegRotator`) |
| Repository LOC | ~1242 | coordinator ~250–350 (delegation), logic distributed across small units |
| Methods on repo | 24 `@override`, all with logic | 24 `@override`, each a one-to-few-line delegation |
| Collaborators on repo | 9 (incl. concrete export impls via defaults) | injected collaborator objects; concrete export impls owned by `DocumentExporter`, wired at the composition root |
| FTS sanitization | inline in repo | pure `FtsQuerySanitizer`, exhaustively unit-tested |
| Rotation | `compute(...)` inline, device-only test | injectable `JpegRotator`, host-testable |
| `_writeFlat` | 1 method, ~5 interleaved concerns | named stages in `PageDerivativePipeline` |
| Testability | monolith, device-heavy | each collaborator host-unit-tested in isolation |

## Tasks

> Extraction order is chosen so low-coupling units come first and the coordinator is rewired last.
> Tasks T05.1–T05.6 each add a new unit + delegate to it; they are **parallel-safe** because they carve
> **disjoint** method groups off the same file — assign each to a subagent but **serialize the final
> merge** into the coordinator (or land the coordinator rewire, T05.7, last).

### T05.1 — Extract pure `FtsQuerySanitizer` (SAFE-06) — do first, zero-risk
- **Scope:** New `lib/features/library/search/fts_query_sanitizer.dart`: a pure class taking a raw query
  and returning terms (operator chars from `_ftsOps` stripped, boolean keywords from `_ftsKeywords`
  dropped, empties removed), the `MATCH` expression (`'"$t"'` AND-joined), the LIKE pattern (`%q%`), and a
  `useLike` flag (any term `< 3` chars or empty → LIKE). No DB dependency.
- **Files:** new sanitizer + `test/.../fts_query_sanitizer_test.dart`.
- **Test-first:** exhaustive cases — quotes/`*`/`:`/`^`/`()`/`-` stripping, bareword `and/or/not/near`
  dropping (case-insensitive), sub-3-char → LIKE, all-sanitized-away → LIKE, multi-word AND expr,
  attempted FTS-syntax injection neutralized.
- **Done:** sanitizer covered ≥ its branches; repo's `_searchTerms`/`_ftsOps`/`_ftsKeywords` slated to be replaced by it.
- **Parallel-safe:** yes (new file, no repo edit yet).

### T05.2 — Introduce injectable `JpegRotator` (TEST-01)
- **Scope:** New `JpegRotator` interface with `Future<Uint8List?> rotate(Uint8List bytes, int quarterTurns)`;
  default `ComputeJpegRotator` wraps `compute(rotateAndBakeJpeg, RotateJpegArgs(...))`. Thread it through
  the derivative pipeline (T05.5). Keep `rotateAndBakeJpeg` top-level (isolate entrypoint).
- **Files:** new `jpeg_rotator.dart` + test; used by T05.5.
- **Test-first:** host test with a fake rotator asserting `_writeFlat`/pipeline calls it with the right
  quarter-turns and honors a `null` (undecodable) return → `DocumentSaveException`.
- **Done:** rotation injectable; a fake makes rotation host-testable.
- **Parallel-safe:** yes (new file). Consumed by T05.5.

### T05.3 — Extract `PageDao`
- **Scope:** New `PageDao` wrapping the drift row access the repo uses: fetch page by (docId,pos) [reuses
  P10 `_requirePage` semantics], max-position row, `getDocumentPages` row→`PageImage` mapping (using
  `EnhancerMode.fromIndex` from P10), insert/update/delete companions, bulk renumber (P10 CPLX-02). Holds
  `_db` + `_fileStore` for path resolution.
- **Files:** new `page_dao.dart` + test.
- **Test-first:** host tests (with an in-memory drift DB) for each query mapping.
- **Done:** repo's raw `_db.select(_db.pages)...` calls have a single home. **Depends on:** P10 helpers.
- **Parallel-safe:** yes; other collaborators call it.

### T05.4 — Extract `DocumentExporter` (+ move concrete impls, SOLID-02)
- **Scope:** New `DocumentExporter` owning `exportPdf`, `exportCombinedPdf`, `exportSeparatePdfs`,
  `exportProtectedPdf`, `exportPageAsImage`, `exportAllPagesAsImages`, `exportRecognizedText`, plus
  `_isIdCard`/`_exportBaseName`/`_pdfFileNameFor` and the `_writeTempExport` helper (P10 DUP-04). It
  **holds** `_pdfBuilder`, `_encryptor`, `_compressor`, `_scrubber`. **Move** the `SyncfusionPdfEncryptor`
  and `ImageLibraryCompressor` defaults out of the repository ctor to the composition root so persistence
  stops importing them.
- **Files:** new `export/document_exporter.dart` + test; `library_dependencies.dart`/`main.dart` wiring.
- **Test-first:** host tests for each export (fake builder/encryptor/compressor), including the uniform
  rethrow semantics from P10.
- **Done:** `drift_document_repository.dart` no longer imports syncfusion/compression impls; exporter tested.
- **Depends on:** P10 (`_writeTempExport`). **Parallel-safe** vs T05.1–T05.3, T05.5.

### T05.5 — Extract `PageDerivativePipeline` + decompose `_writeFlat` (CPLX-01)
- **Scope:** New `PageDerivativePipeline` owning `_writeFlat` split into named stages:
  `_shouldSkip` (fast path: `quarterTurns==0 && fullFrame && none`) → delete existing flat, return null;
  `_rotate` (via injected `JpegRotator` from T05.2); `_enhanceFullFrame` vs `_warpAndEnhanceCrop`
  (each with explicit fallback); `_finalizeFlat` (the `flatBytes == null → delete+null` else write). Holds
  `_processor` + `_fileStore`. The tangled `flatBytes = ... ?? rotatedBytes` fallthrough becomes explicit
  per-branch returns.
- **Files:** new `page_derivative_pipeline.dart` + test.
- **Test-first:** host tests for each stage/branch (fast-path skip; rotate-only; fullframe+enhance with
  processor returning null → falls back to input; crop path null → falls back to rotated; final null →
  deletes existing flat + returns null). Uses fake `JpegRotator` + fake `PageProcessor`.
- **Done:** `_writeFlat` logic lives in the pipeline as discrete, individually tested stages.
- **Depends on:** T05.2. **Parallel-safe** vs others.

### T05.6 — Extract `DocumentSearchService` + `PageOrderingService`
- **Scope:** `DocumentSearchService` owns `searchDocuments`/`_searchByLike`/`_searchRanked` using
  `FtsQuerySanitizer` (T05.1) + `PageDao`/`_db` (bm25 `customSelect`, name-first merge, rank-ordered
  `_summaries`). `PageOrderingService` owns `reorderPages`, `deletePage` renumber sequencing, and the
  `mergeInto`/`splitAfter` orchestration (delegating row/file work to `PageDao` + the P10
  `_cloneSourcePage`/`_copyPageFiles`). **Note:** if P03 has landed, the merge/split **atomicity**
  boundaries live here — coordinate so P03's single-transaction rule is preserved inside this service.
- **Files:** new `search/document_search_service.dart`, `page_ordering_service.dart` + tests.
- **Test-first:** host tests for ranked-vs-like selection, name-first ordering; reorder/delete renumber
  invariants; merge/split page distribution.
- **Done:** both services own their methods; repo delegates. **Depends on:** T05.1, T05.3; coordinate w/ P03.
- **Parallel-safe:** yes vs T05.4/T05.5.

### T05.7 — Rewire `DriftDocumentRepository` into a thin coordinator (do last)
- **Scope:** Replace each of the 24 method bodies with delegation to the collaborators. Update the ctor to
  accept the collaborators (with production defaults constructed at the **composition root**, not inline
  concrete heavy impls). Delete the now-migrated private members. Confirm the class still
  `implements DocumentRepository` with identical signatures.
- **Files:** `drift_document_repository.dart`, `library_dependencies.dart`, `main.dart` wiring.
- **Test-first:** the **existing** heavy repo suites are the regression gate — they must pass unchanged
  (add a few coordinator-level delegation tests if a seam is newly injectable).
- **Done:** repo is delegation-only (~250–350 LOC); full host suite + BDD green.
- **Depends on:** T05.1–T05.6. **Not parallel** — this is the integration step; serialize it last.

## Risks & mitigations

- **Risk:** Extraction subtly changes an observable behavior (an exception type, ordering, a `modifiedAt`
  bump) that a test asserts. → **Mitigation:** the 1441-LOC repo test suite + `migration_test` are the
  gate; run them after **each** task, not just at the end.
- **Risk:** Moving concrete impls to the composition root breaks the const-constructible
  `*Dependencies` pattern. → **Mitigation:** keep defaults const where the impls are const-constructible;
  thread through `LibraryDependencies` per CLAUDE.md ("do not `new` it inline").
- **Risk:** `FtsQuerySanitizer` extraction changes what queries hit LIKE vs MATCH (SAFE-06 is
  security-adjacent). → **Mitigation:** exhaustive host tests mirror the current `_searchTerms`/threshold
  logic exactly before any behavior change; `fts_search`/`o5_content_search` BDD on device.
- **Risk:** Parallel subagents editing the same 1242-LOC file conflict. → **Mitigation:** each task adds a
  **new file** + minimal delegation stub; the disruptive edit (deleting migrated members) is concentrated
  in T05.7, run last by a single agent.
- **Risk:** Overlap with P03 on merge/split. → **Mitigation:** explicit coordination note in T05.6; if P03
  lands first, `PageOrderingService` must carry the single-transaction boundary forward (verified by P03's
  atomicity test moved/kept green).

## Verification commands

```bash
# From apps/mobile/
flutter analyze && dart format lib test
dart run build_runner build --delete-conflicting-outputs   # if any *.feature/step added

# Per-collaborator unit tests
flutter test test/features/library/fts_query_sanitizer_test.dart
flutter test test/features/library/page_dao_test.dart
flutter test test/features/library/document_exporter_test.dart
flutter test test/features/library/page_derivative_pipeline_test.dart
flutter test test/features/library/document_search_service_test.dart
flutter test test/features/library/page_ordering_service_test.dart

# Regression gate — existing heavy suites unchanged + full host suite
flutter test test/features/library/drift_document_repository_test.dart
flutter test test/features/library/drift_document_repository_extra_test.dart
flutter test test/features/library/migration_test.dart
flutter test

# Device BDD — BOTH platforms
flutter test integration_test/fts_search_device_test.dart        -d <android-device-id>
flutter test integration_test/o5_content_search_device_test.dart -d <android-device-id>
flutter test integration_test/l1_merge_documents_device_test.dart -d <android-device-id>
flutter test integration_test/m1_split_document_device_test.dart  -d <android-device-id>
flutter test integration_test/i1_export_device_test.dart         -d <android-device-id>
# repeat each with -d <ios-device-id>
```
