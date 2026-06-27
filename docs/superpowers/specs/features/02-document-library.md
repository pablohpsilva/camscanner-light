# Feature 02 — Document Library & Management

**Date:** 2026-06-27
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** Step 0; shares the document model with Feature 06
**Related:** Feature 08 (search by OCR text), Feature 11 (cloud sync)

## Purpose

The home screen and where saved documents live — browse, open, and manage all
scanned documents. Owns **local persistence** (how documents, pages, and derived
caches are stored).

## Organization

- **MVP:** flat, sortable, name-searchable list/grid.
- **Later (planned):** folders and tags. The model reserves optional `folderId`
  and `tags`, and the repository abstracts "how documents are organized," so
  adding them later doesn't disturb existing code (OCP).

## Operations

- Open, rename, delete (with confirm), sort by date/name. Build steps D1 rename,
  D2 delete, D3 sort.
- **Search:** by name now; by OCR text once Feature 08 lands.

## Storage

- Image / PDF / cache files on disk (app documents directory).
- A **local embedded DB** for document & page metadata.
- All behind a **`DocumentRepository`** interface (DIP). Concrete DB (e.g.
  Drift/SQLite or Isar) is chosen at planning time.
- The persisted unit is the non-destructive page model
  (`original + corners + mode + enhancement`).

## Architecture (SOLID/KISS/DRY)

- Repository pattern; the list/grid UI depends only on the repository interface,
  not storage details (SRP/DIP).
- This is also the app home screen; its empty-state version is build step A1.

## Out of scope

- Capture (01), in-document page operations (06), sharing (12), cloud sync /
  accounts (11).

## Testing strategy (TDD/BDD first)

- **Unit:** repository CRUD (create/list/rename/delete); sort by date/name; name
  search filtering; persistence round-trips the non-destructive model.
- **Widget:** list/grid renders documents; rename dialog; delete confirm; empty
  state.
- **BDD scenarios:**
  - *Given saved documents, when I open the app, then they appear with thumbnail,
    name, date, and page count.*
  - *Given a document, when I rename it, then the new name persists across
    restarts.*
  - *Given a document, when I delete and confirm, then it's removed from the
    library and storage.*
  - *Given I type in search, then only documents whose name matches are shown.*

## Acceptance criteria

1. Library lists saved documents with thumbnail, name, date, page count.
2. User can open, rename, delete (confirm), and sort by date/name.
3. Name search filters the list.
4. Data persists across restarts via the repository.
5. Model/repository are structured to accept folders & tags later without
   breaking existing code.
6. All logic test-first; BDD scenarios pass.
