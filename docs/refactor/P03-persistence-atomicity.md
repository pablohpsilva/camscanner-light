# P03 — Persistence atomicity

**Tier 1 (Safety) · Effort M · Risk Med · Depends on: P10 (de-duped merge/split copy loop + `_maxPositionPage`), P00 (AppLogger) · Device verification: Android AND iOS**

> **Sequencing:** Runs **after** P10 lands so the merge/split page-copy logic is already de-duplicated
> into `_cloneSourcePage`/`_copyPageFiles` and the max-position lookup into `_maxPositionPage` — this
> plan then only has to move transaction **boundaries**, not also fight copy-paste. It can run
> independently of, or before, the P05 God-class extraction; the two touch different concerns (boundary
> vs structure). If P05 lands first, apply these boundary fixes inside whatever collaborator owns the
> op. The public `DocumentRepository` interface stays byte-for-byte stable.

## Summary

Two write paths are **not atomic** and can corrupt persisted state on a mid-operation crash:

- **`mergeInto` / `splitAfter` (SAFE-01, LIVE, highest severity).** In `mergeInto` the image/flat
  **files** are copied *outside* the DB transaction (copy loop :1024–1053) and only the row inserts are
  transactional (:1054–1058) — a failure after some files copy but before commit leaves **orphan files**.
  `splitAfter` is worse: its new-document insert, per-page **row inserts**, *and* file copies are **all**
  outside any transaction (loop :1122–1136), while only the source-row **deletes** are transactional
  (:1139–1145). A crash after the new-doc pages are inserted but before the source deletes commit leaves
  the pages **duplicated in both documents** — visible, permanent data corruption.
- **`createFromCapture` / `addPageToDocument` (SAFE-02, LIVE lock contention).** Both hold the **write
  transaction** across slow IO + CPU: `createFromCapture` (:75–133) spans `File.readAsBytes` (:88),
  `scrubber.scrub` (:89), `writeRelative` (:92), and `_writeFlat` (:101, which may `compute` at :606).
  `addPageToDocument` (:790–838) has the same shape (readAsBytes :802, scrub :803, writeRelative :804,
  `_writeFlat` :809). The long-held write lock **blocks every other DB op** for the duration of a full-res
  decode/rotate/enhance — a UI-isolate DB (deliberate; see below) makes this a real stall.

**Fix strategy (both):** make every *row* mutation atomic inside one `_db.transaction`; treat *file*
writes as **append-only new paths** and clean them up in a `catch` if the transaction fails (mirroring
the existing create-path cleanup at :93–96). Do all IO/scrub/flat work **outside** the transaction, then
open a **short** transaction that inserts only rows. This keeps the DB on the root/UI isolate (mandatory
workaround — see constraints) while removing the long lock hold.

## Global constraints honored

- **DB stays on the ROOT/UI isolate.** `openAppDatabase` deliberately avoids `createInBackground`
  because native-assets made sqlite a native asset and `Isolate.spawn` hangs. This plan does **not**
  move the DB off-isolate; it only shortens how long the single transaction is held. Heavy image work
  (`rotateAndBakeJpeg` via `compute` in `_writeFlat`) already runs off-isolate and stays there.
- **Relative paths only.** All new file paths are produced via `DocumentFileStore` (never absolute).
- **Behavior-preserving public interface.** Signatures + documented contracts of all 24 methods unchanged.

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
|----|------------------|--------------|--------|-------------|
| SAFE-01a | `mergeInto` copy loop :1024–1053, insert txn :1054–1058, `deleteDocument(source)` :1067 (post-txn) | Files copied outside the txn; source deletion is a separate op after the insert txn | Crash between file copy and commit → **orphan files**; crash between insert-commit and source-delete → pages exist in **both** docs until the delete lands | **live** (highest severity) |
| SAFE-01b | `splitAfter` new-doc insert :1095–1103, per-page inserts + file copies :1105–1137, source deletes txn :1139–1145 | New-doc row + all page rows + file copies are **entirely outside** any transaction; only the source deletes are transactional | Crash mid-op → pages **DUPLICATED in both documents** (new doc has them, source still has them) — permanent visible corruption | **live** (highest severity) |
| SAFE-02a | `createFromCapture` txn :75–133 wrapping `readAsBytes`:88, `scrub`:89, `writeRelative`:92, `_writeFlat`:101 (→ `compute`:606) | Slow IO + CPU (full-res decode/rotate/enhance) executed **while holding the write transaction** | Write lock held for the whole capture pipeline → **all other DB ops block**; UI-isolate DB makes this a felt stall | **live** (perf/lock) |
| SAFE-02b | `addPageToDocument` txn :790–838 wrapping `readAsBytes`:802, `scrub`:803, `writeRelative`:804, `_writeFlat`:809 | Same long-held-lock shape as SAFE-02a | Same blocking; concurrent list/search/edit stalls behind an add | **live** (perf/lock) |

## Definition of done

- **SAFE-01:** `mergeInto` and `splitAfter` are each atomic at the **row** level — all row mutations for
  the logical op commit together or not at all. On txn failure, any files written during the op are
  cleaned up best-effort (logged via `AppLogger`); on success no orphan/duplicate rows can exist.
  - `splitAfter`: new-doc insert + moved-page inserts + source-page deletes commit in **one** transaction.
  - `mergeInto`: appended-page inserts + source-document deletion commit in **one** transaction (file
    copies precede it; the copied paths are new/append-only and cleaned up on failure).
- **SAFE-02:** `createFromCapture` and `addPageToDocument` do all read/scrub/`writeRelative`/`_writeFlat`
  work **outside** any transaction; a **short** transaction inserts only the rows. Page id/path is
  reserved without holding the lock (reserve the doc row first / use a store path independent of a
  not-yet-inserted id, or a two-phase insert).
- No new absolute paths; DB still opened on the root isolate; interface unchanged.
- TDD failing-first tests demonstrating (a) no duplicate/orphan rows on an injected mid-op failure and
  (b) the write transaction no longer spans image work.
- Device BDD green on Android AND iOS for the affected flows.

## Before → After

| Op | Before (txn boundary) | After (txn boundary) | Corruption window closed |
|----|-----------------------|----------------------|--------------------------|
| `mergeInto` | files + inserts split; inserts in txn; source delete separate | files copied first (append-only), **inserts + source-delete in one txn**, file cleanup on failure | orphan files + "in both docs" window |
| `splitAfter` | new-doc + page inserts + copies **all outside txn**; only deletes in txn | copies first (append-only), **new-doc insert + page inserts + source deletes in one txn**, cleanup on failure | **page duplication in both docs** |
| `createFromCapture` | txn spans read/scrub/write/flat (`compute`) | IO/scrub/flat **outside**; short txn inserts doc+page rows | long write-lock hold |
| `addPageToDocument` | txn spans read/scrub/write/flat | IO/scrub/flat **outside**; short txn inserts page row + bumps modifiedAt | long write-lock hold |

## Tasks

### T03.1 — Atomicity test harness for merge/split (test-first for SAFE-01)
- **Scope:** Add host unit tests that inject a failure (a `DocumentFileStore`/DB seam that throws) at a
  chosen point in `mergeInto` and `splitAfter`, then assert the **invariant**: after the failure, no
  page is present in **both** the source and target/new document, and no page row references a file that
  was rolled back. These tests must FAIL against the current split/merge boundaries.
- **Files:** new `test/features/library/persistence_atomicity_test.dart`.
- **Test-first:** yes — this task *is* the red.
- **Done:** two failing tests (merge orphan/dup, split dup) checked in, red on current code.
- **Parallel-safe:** yes (test-only; no source change). Blocks T03.2/T03.3 conceptually (they turn it green).

### T03.2 — Make `splitAfter` atomic (SAFE-01b)
- **Scope:** Restructure `splitAfter` so that: (1) file copies for moved pages happen first, producing
  new append-only relative paths (via `DocumentFileStore`, per P10 SAFE-05); (2) a **single**
  `_db.transaction` inserts the new document row, inserts the moved-page rows, and deletes the moved
  source-page rows; (3) on any failure the transaction rolls back and the newly-written files are
  deleted best-effort and logged. Source-file cleanup of the moved originals stays **after** commit
  (already best-effort). Reuse `_cloneSourcePage`/`_copyPageFiles` (P10).
- **Files:** `drift_document_repository.dart`.
- **Test-first:** T03.1's split test goes green; add a success-path test asserting exact final page
  distribution + names.
- **Done:** new-doc + moved inserts + source deletes are one txn; T03.1 split test green; `m1_split` BDD green.
- **Parallel-safe:** independent of T03.3/T03.4 (different method). Depends on T03.1 (red) + P10.

### T03.3 — Make `mergeInto` atomic (SAFE-01a)
- **Scope:** Restructure `mergeInto` so appended-page **inserts** and the **source-document deletion**
  commit in one `_db.transaction` (call the row-delete logic inline rather than the post-txn
  `deleteDocument(source)` at :1067, so it's inside the same transaction; keep the source **dir** cleanup
  after commit). File copies precede the transaction (append-only new paths); on txn failure delete those
  copied files best-effort + log. Reuse `_cloneSourcePage`/`_copyPageFiles` + `_maxPositionPage` (P10).
- **Files:** `drift_document_repository.dart`.
- **Test-first:** T03.1's merge test goes green; success-path test asserts target page count/order + source gone.
- **Done:** inserts + source-row deletes one txn; T03.1 merge test green; `l1_merge` BDD green.
- **Parallel-safe:** independent of T03.2/T03.4. Depends on T03.1 + P10.

### T03.4 — Move image work out of the create/add write transaction (SAFE-02)
- **Scope:** For `createFromCapture`: insert the document row (short txn or pre-reserve), compute the
  page's relative path from the returned `docId`, then perform `readAsBytes`/`scrub`/`writeRelative`/
  `_writeFlat` **outside** any transaction, then a **short** txn inserts the page row. Preserve the
  existing base-write cleanup semantics (delete doc dir + roll back on base-write failure). For
  `addPageToDocument`: compute `newPosition` via `_maxPositionPage` (short read), do IO/scrub/flat
  outside a txn, then a short txn inserts the page row + bumps `modifiedAt`. Keep `_triggerOcr` /
  `_deleteTempSource` post-commit as today.
- **Files:** `drift_document_repository.dart`.
- **Test-first:** add a test using an instrumented DB/clock that records whether a transaction is open
  during the `_writeFlat`/`compute` call — assert it is **not**. Keep all existing create/add tests green.
- **Done:** no transaction is held across image work in either method; existing create/add + `b2_restart`
  BDD green.
- **Parallel-safe:** independent of T03.2/T03.3. Depends on P10 (`_maxPositionPage`).

### T03.5 — Failure-cleanup helper for append-only file writes
- **Scope:** Extract a small `_cleanupWrittenFiles(List<String> relPaths)` (best-effort delete + log via
  `AppLogger`) used by T03.2/T03.3 catch blocks, so both ops clean up copied files uniformly. Mirrors
  the existing create-path cleanup pattern.
- **Files:** `drift_document_repository.dart`.
- **Test-first:** host test that a forced txn failure after N file copies deletes exactly those N files.
- **Done:** shared helper; both merge/split use it. **Depends on:** P00 `AppLogger`.
- **Parallel-safe:** land alongside T03.2/T03.3 (they consume it) — assign together or serialize.

## Risks & mitigations

- **Risk:** Moving row deletes for merge into the insert transaction changes `deleteDocument`'s
  encapsulated cascade/FK behavior. → **Mitigation:** the source rows are deleted with the same
  page-then-document order inside the txn (FK pragma is on); T03.1 invariant + `l1_merge` BDD verify.
- **Risk:** Pre-reserving/inserting the document row in `createFromCapture` before the page write, then
  a base-write failure, must still roll back the document row (no empty doc). → **Mitigation:** keep the
  base-write failure path deleting the doc dir **and** ensure the doc-row insert is inside the same short
  final txn OR explicitly deleted on failure; test asserts no orphan empty document after injected failure.
- **Risk:** Longer window between file write and row insert (SAFE-02) means a crash leaves an
  **orphan file with no row** — but that's the *safe* failure mode (harmless orphan), strictly better than
  today's in-txn image work. → **Mitigation:** documented as the intended trade-off; orphan files are
  already tolerated elsewhere (`deleteDocument` comment). No dangling **row** is ever created.
- **Risk:** DB-on-UI-isolate constraint accidentally violated by an eager refactor toward background
  isolates. → **Mitigation:** explicit DO-NOT in this doc; `openAppDatabase` untouched; reviewer checks.
- **Risk:** Instrumentation seam for "is a txn open during image work" is brittle. → **Mitigation:**
  use a spy `PageProcessor`/`_writeFlat` injection that records `_db`'s in-transaction state via a test
  hook, rather than asserting on drift internals.

## Verification commands

```bash
# From apps/mobile/
flutter analyze && dart format lib test

# New atomicity tests + existing heavy repo suites
flutter test test/features/library/persistence_atomicity_test.dart
flutter test test/features/library/drift_document_repository_test.dart
flutter test test/features/library/drift_document_repository_extra_test.dart
flutter test                                       # full host suite

# Device BDD — BOTH platforms (drift/sqlite native; atomicity is a native-DB property)
flutter test integration_test/l1_merge_documents_device_test.dart -d <android-device-id>
flutter test integration_test/m1_split_document_device_test.dart  -d <android-device-id>
flutter test integration_test/b2_restart_persistence_device_test.dart -d <android-device-id>
flutter test integration_test/b3_view_and_delete_device_test.dart -d <android-device-id>
# repeat each with -d <ios-device-id>
```
