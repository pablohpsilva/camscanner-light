# FTS5 search — trigram matching + relevance ranking (design)

**Date:** 2026-07-03
**Status:** Approved (design)
**Sub-project:** 2 — OCR / text extraction (Feature 08) → library search (Feature 02)
**Depends on:** O1 (per-page `ocrText`), O2 (real OCR auto-runs after save), O5 (LIKE search + home search UI)
**Supersedes the search engine of:** [O5](2026-07-01-o5-content-search-design.md) — which explicitly deferred "a dedicated FTS5 index" and "full-text ranking / relevance scoring" until libraries grow. This is that revisit.

## Purpose

O5 shipped working search: `searchDocuments(query)` matches `documents.name` OR any
`pages.ocrText` via `LIKE '%q%'`, wired to a toggleable home-screen search bar, with
OCR auto-populated on every page (O2). Three weaknesses remain, all in the **engine**,
not the UI:

1. **Multi-word queries mostly fail.** `LIKE '%acme invoice%'` needs that exact
   adjacent substring on one page; it won't match a doc with "acme" on page 1 and
   "invoice" on page 3, or "invoice from acme".
2. **No relevance ranking.** Results are newest-first; a 20-hit doc ranks the same as
   an incidental 1-hit.
3. **No index.** A leading-wildcard `LIKE` can't use an index → full-scans every
   page's text on each keystroke. Fine at 50 docs, degrades with thousands of pages.

This slice replaces the engine with a SQLite **FTS5 trigram** index: multi-word AND
matching, `bm25` relevance ranking, and indexed (fast) lookups — **without regressing**
today's substring behavior (see Tokenizer). The **results UI is unchanged** (document
summaries), only their order changes to relevance-first while a query is active.

## Scope

**In:**
- An FTS5 **trigram** virtual table indexing each page's `ocr_text`, kept in sync by
  SQLite triggers on `pages` (no repository write-path changes).
- Schema migration `v4 → v5`: create the vtable + triggers and **backfill** existing
  `ocr_text`.
- Rewrite `searchDocuments(query)` to run a sanitized, ranked trigram `MATCH`
  (multi-word AND), aggregate per document, merge with document-name matches, and
  return the existing `DocumentSummary` shape ordered by relevance.
- A **short-term fallback**: queries containing any term shorter than trigram's 3-char
  floor use the existing `LIKE` path (correct, just unranked).

**Out (unchanged from O5 / this slice's choice):**
- Snippets, match highlighting, jump-to-matching-page. Results stay summaries.
- Fuzzy/typo tolerance, search history, date/type filters.
- Indexing document names in the FTS table (names are short; matched via `LIKE` +
  ranked first — see Architecture). Keeps renames from needing cross-row FTS updates.
- Any home-screen UI change beyond the fact that ranked results replace newest-first
  ordering while a query is active.

## Tokenizer — why trigram (the key decision)

`LIKE '%scan%'` today matches **mid-word** ("re**scan**ned") and works for **any
script** including CJK. The two FTS5 tokenizer choices differ on whether that survives:

- **`unicode61`** (word tokens): best word-boundary ranking + prefix matching, but a
  behavior **regression** — `scan*` won't find "rescanned", and a run of CJK collapses
  to a single token (CJK search breaks). Rejected.
- **`trigram`** (chosen): indexes overlapping 3-char sequences, so `col MATCH 'scan'`
  is **substring** matching for all scripts (CJK included) — no regression vs `LIKE` —
  while adding multi-word AND, `bm25` ranking, and an index. Cost: terms must be
  **≥ 3 chars** (shorter terms → `LIKE` fallback), and the index is larger (acceptable;
  OCR text is modest for a personal scanner).

## Architecture

### Virtual table (standalone, NOT external-content)

```sql
CREATE VIRTUAL TABLE page_fts USING fts5(
  text,
  document_id UNINDEXED,
  tokenize = 'trigram'
);
```

- **`rowid` = `pages.id`.** Stores a **copy** of `ocr_text` plus the owning
  `document_id` (UNINDEXED — carried for aggregation, not searched).
- **Deliberately not `content='pages'` (external-content).** External-content needs the
  fiddly `INSERT INTO page_fts(page_fts, rowid, …) VALUES('delete', …)` protocol with
  OLD values in the UPDATE/DELETE triggers; a mistake there silently desyncs the index.
  A standalone table with a text copy is trivially correct and OCR text is small.

### Triggers (all sync lives here — no repository code touches the index)

Column names are drift's **snake_case** (`ocr_text`, `document_id`), not the Dart
getters. Pages are inserted with `ocr_text` NULL (OCR fills it later, fire-and-forget),
so the triggers must handle null↔text transitions:

```sql
-- new page already carrying text (e.g. copied on split/merge)
CREATE TRIGGER page_fts_ai AFTER INSERT ON pages
WHEN NEW.ocr_text IS NOT NULL BEGIN
  INSERT INTO page_fts(rowid, text, document_id)
  VALUES (NEW.id, NEW.ocr_text, NEW.document_id);
END;

-- ocr_text filled / changed / cleared
CREATE TRIGGER page_fts_au AFTER UPDATE OF ocr_text ON pages BEGIN
  DELETE FROM page_fts WHERE rowid = OLD.id;
  INSERT INTO page_fts(rowid, text, document_id)
    SELECT NEW.id, NEW.ocr_text, NEW.document_id
    WHERE NEW.ocr_text IS NOT NULL;
END;

-- page removed (explicit delete AND FK ON DELETE CASCADE both fire this)
CREATE TRIGGER page_fts_ad AFTER DELETE ON pages BEGIN
  DELETE FROM page_fts WHERE rowid = OLD.id;
END;
```

So every current and future `ocr_text` write path (`runOcr`, re-crop re-OCR, split,
merge, and anything added later) stays indexed for free; deletes (explicit in
`deleteDocument`, and via FK cascade) leave no orphan rows.

### Migration (v4 → v5) + backfill

`schemaVersion` bumps to **5**. The vtable is raw SQL (not a drift table), so
`m.createAll()` does not create it and **no `build_runner` regen is needed**. A shared
private helper `_createFts(Migrator/QueryExecutor)` issues the `CREATE VIRTUAL TABLE` +
three `CREATE TRIGGER` statements; it is called from **both** `onCreate` (after
`createAll`) and `onUpgrade` (`if (from < 5)`). `onUpgrade` then backfills:

```sql
INSERT INTO page_fts(rowid, text, document_id)
SELECT id, ocr_text, document_id FROM pages WHERE ocr_text IS NOT NULL;
```

### `searchDocuments(query)` rewrite

```
trim → empty? → listDocumentSummaries()          (unchanged fast path)
     → tokenize on whitespace, sanitize each term (strip FTS5 operator chars
       " * : - ( ) ^ and bareword AND/OR/NOT/NEAR); drop empties
     → any surviving term < 3 chars, OR no terms survive?
          → LIKE fallback (today's O5 two-step name/ocrText match, unranked)
     → else RANKED path:
          matchExpr = terms joined with ' AND ', each wrapped in double quotes:  "acme" AND "invoice"
          rows = SELECT document_id, MIN(bm25(page_fts)) AS score
                 FROM page_fts WHERE page_fts MATCH :matchExpr
                 GROUP BY document_id                       -- best-matching page wins
          nameIds = SELECT id FROM documents WHERE name LIKE %rawTrimmed%   -- name signal
          order:  name-match docs first (createdAt desc), then text-only docs by score ASC
                  (bm25: lower = more relevant), distinct doc ids
          → _summaries(onlyIds: orderedIds) rebuilt in that order
```

- **Sanitization is the crash guard.** Raw user text (which may contain `"`, `*`, `-`,
  `(`, `NEAR`, …) is **never** passed to `MATCH`; every term is stripped and quoted.
  This is mandatory — a malformed `MATCH` expression is a SQL error, not empty results.
- **Ordering:** `_summaries(onlyIds:)` today orders by `createdAt desc`. For the ranked
  path it must instead preserve the **computed relevance order**; the helper gains an
  optional ordered-id list (build a `CASE`/index map, or sort in Dart after fetch). The
  `onlyIds: null` and unordered paths keep O5's behavior (existing tests guard them).
- **Name matches rank first** because a title hit is a strong intent signal and names
  aren't in the trigram index. Within each group, existing order applies.

## Data flow

```
type "acme inv" ─▶ HomeScreen._onQueryChanged
                    └─ repo.searchDocuments('acme inv')
                        terms ["acme","inv"] → "inv" < 3 chars → LIKE fallback (unranked)
type "acme invoice" ─▶ repo.searchDocuments('acme invoice')
                        terms ["acme","invoice"] all ≥3 → MATCH  "acme" AND "invoice"
                          → per-doc MIN(bm25) → merge name LIKE → relevance order
                        ─▶ (query still current?) setState(list)  [race guard unchanged]
```

## Error handling

- Malformed `MATCH` is prevented by sanitization; still, `searchDocuments` DB failures
  surface the existing `documents-error` state + retry (same path as O5).
- Migration failure (e.g. FTS5 unavailable) aborts the open — see Risk below; it is
  retired before any user-facing work by the Plan's step 1 probe.
- Trigger/index desync is structurally prevented (triggers own all writes); a delete
  test asserts no orphan `page_fts` rows remain.

## Testing strategy (TDD/BDD first)

**Risk retired first (Plan step 1):** a throwaway probe that runs
`CREATE VIRTUAL TABLE t USING fts5(x, tokenize='trigram')` under **host** `flutter test`
(drift `NativeDatabase.memory()`). Device is fine (`sqlite3_flutter_libs` ships FTS5);
if the host's libsqlite3 lacks FTS5/trigram, the engine tests move to device
`integration_test` (same shape as the OpenCV host-test limitation). Everything else is
unaffected.

**Unit (host, `NativeDatabase.memory()` seeded with docs + pages/`ocrText`):**
- multi-word AND across **different pages** of one doc matches (the core O5 gap);
- substring / mid-word match preserved ("scan" finds "rescanned"); CJK substring
  matches (trigram parity vs `LIKE`);
- ranking: a doc with more/closer hits ranks above an incidental 1-hit;
- name-hit doc sorts ahead of a text-only hit;
- operator-laden input (`"`, `*`, `-`, `NEAR`, unbalanced `(`) never throws and returns
  sensible results (sanitization);
- short-term query (`"a"`, `"ab"`) takes the `LIKE` fallback and still matches;
- empty/whitespace query returns the same set as `listDocumentSummaries`;
- `pageCount` / `thumbnailPath` correct (reused `_summaries`), doc appears once.

**Migration (host):**
- v4 DB with pre-existing `ocr_text` → open at v5 → backfill indexed (search finds it);
- INSERT-null-then-UPDATE-text indexes the page; UPDATE text→null removes it;
- deleting a document (and a single page) leaves **no** orphan `page_fts` rows.

**Existing tests updated:** O5 `searchDocuments` tests asserting newest-first order
under a ranked query are updated to relevance order; `listDocumentSummaries`
(`onlyIds: null`) tests stay green (regression guard on the unranked path).

**BDD (`.feature` → on-device Samsung RZCY51D0T1K):**
- *Given two saved documents — one whose pages contain "acme" and "invoice" on
  different pages, one containing neither — when I search "acme invoice", then I see
  the first document and not the second.* Seeded via the persistent-storage pattern,
  then **the app launches reading that same storage** (per the BDD-seed rule), so the
  migration/backfill runs against seeded rows.

## Cross-platform

Pure SQLite + Dart. FTS5 with the trigram tokenizer is bundled in
`sqlite3_flutter_libs` on both iOS and Android; no platform channels. UI is unchanged.

## Definition of Done

- `page_fts` vtable + triggers created in `onCreate` and `onUpgrade` (shared helper),
  `schemaVersion = 5`, backfill verified by migration tests.
- `searchDocuments` ranked trigram path + sanitization + `LIKE` short-term/edge
  fallback + name-first merge, TDD-covered; `listDocumentSummaries` tests green.
- Existing O5 search tests updated to relevance ordering.
- `.feature` BDD (multi-word across pages) generated and green on-device.
- `flutter analyze` clean; host suite green; on-device verification passes; plans/specs
  index updated. No orphan-row or desync path left open.
