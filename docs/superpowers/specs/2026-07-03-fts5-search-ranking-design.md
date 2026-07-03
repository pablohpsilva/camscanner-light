# FTS5 search — trigram matching + relevance ranking (design)

**Date:** 2026-07-03
**Status:** Approved (design) — revised during planning (see Revision note)
**Sub-project:** 2 — OCR / text extraction (Feature 08) → library search (Feature 02)
**Depends on:** O1 (per-page `ocrText`), O2 (real OCR auto-runs after save), O5 (LIKE search + home search UI)
**Supersedes the search engine of:** [O5](2026-07-01-o5-content-search-design.md) — which explicitly deferred "a dedicated FTS5 index" and "full-text ranking / relevance scoring" until libraries grow. This is that revisit.

> **Revision note (2026-07-03):** first draft indexed one FTS row **per page**. That
> is wrong for the core goal: FTS5 `MATCH 'a AND b'` requires both terms in the **same
> row**, so a query spanning two pages of one document would never match. Corrected to
> one FTS row **per document** (all its pages' OCR text concatenated). This also
> simplifies ranking (one `bm25` per document, no aggregation).

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

This slice replaces the engine with a SQLite **FTS5 trigram** index (one row per
document): multi-word AND matching across a document's pages, `bm25` relevance ranking,
and indexed (fast) lookups — **without regressing** today's substring behavior (see
Tokenizer). The **results UI is unchanged** (document summaries), only their order
changes to relevance-first while a query is active.

## Scope

**In:**
- An FTS5 **trigram** virtual table `doc_fts`, one row **per document**, holding that
  document's pages' `ocr_text` concatenated. Kept in sync by SQLite triggers on `pages`
  (no repository write-path changes).
- Schema migration `v4 → v5`: create the vtable + triggers and **backfill** existing
  documents from their pages' `ocr_text`.
- Rewrite `searchDocuments(query)` to run a sanitized, ranked trigram `MATCH`
  (multi-word AND), merge with document-name matches, and return the existing
  `DocumentSummary` shape ordered by relevance.
- A **short-term fallback**: queries containing any term shorter than trigram's 3-char
  floor use the existing `LIKE` path (correct, just unranked).

**Out (unchanged from O5 / this slice's choice):**
- Snippets, match highlighting, jump-to-matching-page. Results stay summaries.
- Fuzzy/typo tolerance, search history, date/type filters.
- Indexing document names in the FTS table (names are short; matched via `LIKE` +
  ranked first — see Architecture). Keeps renames from touching the FTS index.
- Any home-screen UI change beyond ranked results replacing newest-first ordering while
  a query is active.

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

### Virtual table — one row per document (standalone, NOT external-content)

```sql
CREATE VIRTUAL TABLE doc_fts USING fts5(text, tokenize = 'trigram');
```

- **`rowid` = `documents.id`.** The single `text` column holds that document's pages'
  `ocr_text` joined with spaces (`group_concat`). One row per document means a
  multi-word `MATCH` (AND) is satisfied when the terms appear **anywhere across the
  document's pages** — the core requirement.
- **Deliberately not `content='...'` (external-content).** External-content needs the
  fiddly `'delete'`-command trigger protocol with OLD values; a mistake there silently
  desyncs the index. A standalone table holding a text copy is trivially correct, and a
  document's concatenated OCR text is small at phone scale.

### Triggers (all sync lives here — no repository code touches the index)

Any change to a page's `ocr_text` rebuilds that **document's** row from scratch
(delete-then-reinsert the `group_concat` of its still-present, non-null pages). Column
names are drift's snake_case (`ocr_text`, `document_id`). The three bodies are identical
except INSERT/UPDATE key on `NEW.document_id` and DELETE on `OLD.document_id`:

```sql
-- a page arrives already carrying text (e.g. copied on split/merge)
CREATE TRIGGER doc_fts_ai AFTER INSERT ON pages
WHEN NEW.ocr_text IS NOT NULL BEGIN
  DELETE FROM doc_fts WHERE rowid = NEW.document_id;
  INSERT INTO doc_fts(rowid, text)
    SELECT document_id, group_concat(ocr_text, ' ')
    FROM pages WHERE document_id = NEW.document_id AND ocr_text IS NOT NULL
    GROUP BY document_id;
END;

-- ocr_text filled / changed / cleared on an existing page
CREATE TRIGGER doc_fts_au AFTER UPDATE OF ocr_text ON pages BEGIN
  DELETE FROM doc_fts WHERE rowid = NEW.document_id;
  INSERT INTO doc_fts(rowid, text)
    SELECT document_id, group_concat(ocr_text, ' ')
    FROM pages WHERE document_id = NEW.document_id AND ocr_text IS NOT NULL
    GROUP BY document_id;
END;

-- a page removed (explicit delete AND FK ON DELETE CASCADE both fire this)
CREATE TRIGGER doc_fts_ad AFTER DELETE ON pages BEGIN
  DELETE FROM doc_fts WHERE rowid = OLD.document_id;
  INSERT INTO doc_fts(rowid, text)
    SELECT document_id, group_concat(ocr_text, ' ')
    FROM pages WHERE document_id = OLD.document_id AND ocr_text IS NOT NULL
    GROUP BY document_id;
END;
```

- The `GROUP BY document_id` makes the SELECT yield **zero rows** when the document has
  no non-null pages left, so the row is simply dropped (no NULL insert). This is why
  the last-page-deleted / text-cleared cases stay clean.
- Rebuild-per-write is idempotent and cheap (a `group_concat` over a handful of small
  page rows). Every current and future `ocr_text` write path (`runOcr`, split, merge,
  and anything added later) stays indexed for free; deletes leave no orphan rows.

### Migration (v4 → v5) + backfill

`schemaVersion` bumps to **5**. The vtable is raw SQL (not a drift table), so
`m.createAll()` does not create it and **no `build_runner` regen is needed**. A shared
private helper `_createFts()` issues the `CREATE VIRTUAL TABLE` + three `CREATE TRIGGER`
statements; it is called from **both** `onCreate` (after `createAll`) and `onUpgrade`
(`if (from < 5)`). `onUpgrade` then backfills one row per document:

```sql
INSERT INTO doc_fts(rowid, text)
SELECT document_id, group_concat(ocr_text, ' ')
FROM pages WHERE ocr_text IS NOT NULL
GROUP BY document_id;
```

### `searchDocuments(query)` rewrite

```
trim → empty? → listDocumentSummaries()          (unchanged fast path)
     → tokenize on whitespace, sanitize each term (strip FTS5 operator chars
       " * : - ( ) ^ ; drop bareword AND/OR/NOT/NEAR); drop empties
     → any surviving term < 3 chars, OR no terms survive?
          → LIKE fallback (today's O5 two-step name/ocrText match, unranked)
     → else RANKED path:
          matchExpr = terms each wrapped in double quotes, joined ' AND ':  "acme" AND "invoice"
          rows = SELECT rowid AS did, bm25(doc_fts) AS score
                 FROM doc_fts WHERE doc_fts MATCH :matchExpr ORDER BY score   -- one row/doc
          nameIds = SELECT id FROM documents WHERE name LIKE %rawTrimmed% ORDER BY created_at DESC
          order:  name-match docs first (createdAt desc), then text-match docs by score ASC
                  (bm25: lower = more relevant), distinct doc ids
          → _summaries(onlyIds: idSet) then re-sorted into that computed order
```

- **Sanitization is the crash guard.** Raw user text (which may contain `"`, `*`, `-`,
  `(`, `NEAR`, …) is **never** passed to `MATCH`; every term is stripped and quoted.
  A malformed `MATCH` expression is a SQL error, not empty results — so this is
  mandatory.
- **Ordering:** `_summaries(onlyIds:)` today orders by `createdAt desc`; the ranked path
  fetches those summaries and re-sorts them in Dart by the computed relevance order
  (a doc-id→rank map). The `onlyIds: null` and LIKE-fallback paths keep O5's behavior
  (existing tests guard them).
- **Name matches rank first** because a title hit is a strong intent signal and names
  aren't in the trigram index.

## Data flow

```
type "acme inv" ─▶ HomeScreen._onQueryChanged
                    └─ repo.searchDocuments('acme inv')
                        terms ["acme","inv"] → "inv" < 3 chars → LIKE fallback (unranked)
type "acme invoice" ─▶ repo.searchDocuments('acme invoice')
                        terms all ≥3 → MATCH  "acme" AND "invoice"  over per-DOCUMENT rows
                          (matches a doc even if the two words are on different pages)
                          → bm25 order → merge name LIKE → relevance order
                        ─▶ (query still current?) setState(list)  [race guard unchanged]
```

## Error handling

- Malformed `MATCH` is prevented by sanitization; still, `searchDocuments` DB failures
  surface the existing `documents-error` state + retry (same path as O5).
- Migration failure (e.g. FTS5 unavailable) aborts the open — see Risk below; retired
  before any user-facing work by the Plan's step 1 probe.
- Trigger/index desync is structurally prevented (triggers own all writes, full rebuild
  per change); a delete test asserts no orphan `doc_fts` rows remain.

## Testing strategy (TDD/BDD first)

**Risk retired first (Plan Task 1):** a throwaway probe that runs
`CREATE VIRTUAL TABLE t USING fts5(x, tokenize='trigram')` under **host** `flutter test`
(drift `NativeDatabase.memory()`). Device is fine (`sqlite3_flutter_libs` ships FTS5);
if the host's libsqlite3 lacks FTS5/trigram, the engine tests move to device
`integration_test` (same shape as the OpenCV host-test limitation). Everything else is
unaffected.

**Unit (host, `NativeDatabase.memory()` seeded with docs + pages/`ocrText`):**
- **multi-word AND across DIFFERENT pages** of one doc matches (the core O5 gap) while a
  decoy doc containing only one of the terms does not;
- substring / mid-word match preserved ("scan" finds "rescanned"); CJK substring
  matches (trigram parity vs `LIKE`);
- ranking: a doc with more/closer hits ranks above an incidental 1-hit;
- name-hit doc sorts ahead of a text-only hit;
- operator-laden input (`"`, `*`, `-`, `NEAR`, unbalanced `(`) never throws and returns
  sensible results (sanitization);
- short-term query (`"a"`, `"ab"`) takes the `LIKE` fallback and still matches;
- empty/whitespace query returns the same set as `listDocumentSummaries`;
- `pageCount` / `thumbnailPath` correct (reused `_summaries`), doc appears once.

**Data-layer (host):**
- inserting/updating a page's `ocr_text` makes the doc findable; clearing it (→null)
  and deleting the page/document leave **no** matching `doc_fts` row (rebuild + orphan
  checks);
- the **backfill** statement indexes pre-existing OCR text (populate pages, wipe
  `doc_fts`, run backfill, assert found).

**Existing tests:** the O5 `search_documents_test.dart` cases assert membership, not
cross-document order, so they should stay green **unchanged** under the ranked engine
(verify, don't rewrite); `listDocumentSummaries` (`onlyIds: null`) tests guard the
unranked path.

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

- `doc_fts` vtable + triggers created in `onCreate` and `onUpgrade` (shared helper),
  `schemaVersion = 5`, backfill verified by data-layer tests.
- `searchDocuments` ranked trigram path + sanitization + `LIKE` short-term/edge
  fallback + name-first merge, TDD-covered; `listDocumentSummaries` tests green.
- Existing O5 search tests stay green under the new engine.
- `.feature` BDD (multi-word across pages) generated and green on-device.
- `flutter analyze` clean; host suite green; on-device verification passes; plans/specs
  index updated. No orphan-row or desync path left open.
