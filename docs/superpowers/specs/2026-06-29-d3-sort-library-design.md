# D3 — Sort the Library: Design

**Status:** Approved (brainstorming) — ready for writing-plans
**Date:** 2026-06-29
**Roadmap:** Group D (library management). Builds on B1 (storage/Drift), B3 (HomeScreen list + page viewer), D1 (rename). D2 (delete) shipped under B3.

## Goal

Let the user control the order documents appear in the HomeScreen library
list. Today `DriftDocumentRepository.listDocumentSummaries()` hard-codes
`ORDER BY documents.createdAt DESC` (newest-created first) with no way to
change it. D3 adds a sort control offering three criteria — **Name**,
**Created**, **Modified** — each in either direction, applied in-memory as a
presentation concern.

## Decisions (locked during brainstorming)

1. **Criteria:** Name, Date created, Date modified — each with a direction
   toggle (asc/desc). Six effective orderings.
2. **Persistence:** **Session-only.** The chosen sort lives in HomeScreen
   in-memory state and resets to the default on every cold start. No
   preference store exists today, and adding one (schema bump or a new
   dependency) is out of scope. **`schemaVersion` stays 1.**
3. **Control:** An always-visible inline segmented control (a row of
   `ChoiceChip`s) directly under the AppBar, shown only when the loaded list
   is non-empty.
4. **Where sorting happens:** **In-memory pure function (Approach B).** The
   repository is **not changed** — it keeps returning its canonical
   `createdAt DESC` list. A pure `sortDocuments(...)` orders the presentation
   in the widget layer.

## Architecture

The sort is a presentation concern, so it lives entirely in the widget layer.
The repository, Drift schema, and `FakeDocumentRepository` are **untouched** —
this is the key blast-radius win over D1 (which changed the repo interface and
all three implementers).

```
HomeScreen (_sort: DocumentSort, session state)
  ├─ SortControlBar(sort, onCriterionTapped)   // under AppBar, when list non-empty
  └─ DocumentsListView(summaries: sortDocuments(_summaries, _sort), ...)
        ↑
     sortDocuments(...)  // pure, in document_sort.dart
```

- The repo's `listDocumentSummaries()` returns `createdAt DESC` unchanged.
- `_summaries` (raw repo order) is never mutated; only the presented copy is
  sorted.
- Tapping a chip → `nextSort(...)` → `setState(_sort = …)`. Pure, in-memory,
  no `_load()`, no DB query.

## Components

### 1. `lib/features/library/document_sort.dart` (new)

The sort model + the two pure functions. One responsibility: define and
compute ordering. No Flutter import — pure Dart, trivially unit-testable.

```dart
enum SortCriterion { name, created, modified }
enum SortDirection { asc, desc }

class DocumentSort {
  final SortCriterion criterion;
  final SortDirection direction;
  const DocumentSort(this.criterion, this.direction);

  /// Default = today's behavior: newest-created first.
  static const DocumentSort initial =
      DocumentSort(SortCriterion.created, SortDirection.desc);

  @override
  bool operator ==(Object other) =>
      other is DocumentSort &&
      other.criterion == criterion &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(criterion, direction);
}
```

**`List<DocumentSummary> sortDocuments(List<DocumentSummary> docs, DocumentSort sort)`**
- Operates on a **copy** (`[...docs]`); never mutates the input.
- **Name:** case-insensitive — `a.document.name.toLowerCase().compareTo(b.document.name.toLowerCase())`. (SQLite's default BINARY collation would sort uppercase before lowercase; the in-memory function deliberately collates naturally.)
- **Created / Modified:** `a.document.createdAt.compareTo(...)` / `modifiedAt`.
- **Direction:** the primary comparator result is negated when `direction == desc`.
- **Stable tie-break:** when the primary key is equal, fall back to
  `createdAt` **DESC**, then `id` ascending — fully deterministic. Dart's
  `List.sort` is not guaranteed stable, so the tie-break is explicit.
- **Total:** handles 0 / 1 / n items; never throws.

**`DocumentSort nextSort(DocumentSort current, SortCriterion tapped)`**
- If `tapped != current.criterion` → switch to `tapped` with its **default
  direction**: Name → `asc`, Created → `desc`, Modified → `desc`.
- If `tapped == current.criterion` → keep the criterion, **flip** the
  direction.

### 2. `lib/features/library/widgets/sort_control_bar.dart` (new)

```dart
class SortControlBar extends StatelessWidget {
  final DocumentSort sort;
  final ValueChanged<SortCriterion> onCriterionTapped;
  const SortControlBar({
    super.key,
    required this.sort,
    required this.onCriterionTapped,
  });
}
```

- A single horizontal row (e.g. `Wrap`/`Row` of `ChoiceChip`s with spacing),
  fixed order: **Name**, **Created**, **Modified**.
- The **active** chip has `selected: true` and shows a trailing direction
  arrow: `Icons.arrow_upward` (asc) / `Icons.arrow_downward` (desc). Inactive
  chips show no arrow.
- Each chip's `onSelected`/`onTap` calls `onCriterionTapped(criterion)`.
- **Keys:** row `Key('sort-control-bar')`; chips `Key('sort-chip-name')`,
  `Key('sort-chip-created')`, `Key('sort-chip-modified')`; direction arrow
  `Key('sort-direction-asc')` / `Key('sort-direction-desc')`. Tests assert the
  active criterion and the direction **by key**, never by reading icon glyphs.
- Labels: `Name`, `Created`, `Modified`.

### 3. `lib/features/library/home_screen.dart` (modify)

- Add `DocumentSort _sort = DocumentSort.initial;` session state.
- `build`: render `sortDocuments(_summaries, _sort)` into `DocumentsListView`
  (raw `_summaries` unchanged).
- Place `SortControlBar(sort: _sort, onCriterionTapped: _onSortCriterion)` at
  the top of the body **only when `_summaries.isNotEmpty`** and not in
  loading/error states (i.e. in the same branch that renders the list).
- `void _onSortCriterion(SortCriterion c) => setState(() => _sort = nextSort(_sort, c));`
- No repository change, no `_load()` change.

## Data flow & interaction with existing features

- **Rename (D1):** `_renameDocument` already calls `_load()`, refreshing
  `_summaries`. Because `build` re-applies `sortDocuments(_, _sort)`, a renamed
  document automatically re-positions under an active Name/Modified sort. No
  extra code.
- **Scan / delete / open-return:** same — each path already calls `_load()`;
  the active sort re-applies on the next `build`.
- **Empty / loading / error:** the sort bar is hidden; `sortDocuments` is never
  asked to order absent data.
- **Equal keys:** duplicate names or identical timestamps resolve via the
  explicit `createdAt DESC` → `id` tie-break; the list never jitters.

## Error handling

No new error paths. `sortDocuments` is pure and total (never throws); the bar
is absent whenever there is no data. No file or DB writes, so no IO failure
modes are introduced.

## Privacy spine

Entirely on-device and in-memory. No network, no new dependency, no file or DB
write. The name never leaves the device. EXIF scrubbing and relative-path
storage are untouched.

## Testing

### Unit — pure logic (correctness core)
`test/features/library/document_sort_test.dart`:
- `sortDocuments`: Name asc/desc **case-insensitive** (`apple`/`Banana`/`banana`);
  Created asc/desc; Modified asc/desc; **does not mutate** input; **tie-break**
  deterministic (equal names → `createdAt DESC` → `id`); 0 / 1 / n items.
- `nextSort`: switch-to-inactive uses the criterion's default direction
  (Name→asc, Created→desc, Modified→desc); tap-active flips direction.

### Widget — sort control
`test/features/library/widgets/sort_control_bar_test.dart`:
- Renders 3 chips by key; active chip selected with the correct arrow **by
  key**; inactive chips show no arrow; tapping a chip fires
  `onCriterionTapped` with the right criterion.

### Widget — HomeScreen
`test/features/library/home_screen_test.dart` (extend):
- Bar hidden in loading/error/empty; shown with ≥1 doc.
- Tapping a chip re-orders the rendered `DocumentsListView` (assert tile order
  changes) **without** a repo re-query — the Fake records no additional
  `listDocumentSummaries` call beyond the initial load.

### Integration (BDD) — wiring smoke test
`integration_test/d3_sort.feature` → generated `d3_sort_test.dart`. Honest
scope (mirrors D1): proves the control wires to a re-sort without crashing;
ordering correctness is unit-covered.

```gherkin
Feature: Sort the library
  Scenario: Switch the library sort to name
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    And I tap the sort chip {'name'}
    Then I see the sort chip {'name'} is active
```

- Reuses existing steps:
  `the_app_is_launched_with_camera_permission_granted_and_empty_storage`,
  `i_tap_the_scan_button`, `i_tap_the_shutter`, `i_tap_accept`.
- **2 new step files** (punctuation-free step text to avoid bdd silent-empty
  stubs), each no-stub-guarded:
  - `test/step/i_tap_the_sort_chip.dart` → `iTapTheSortChip(tester, String criterion)`:
    tap `Key('sort-chip-$criterion')`, `pumpAndSettle`.
  - `test/step/i_see_the_sort_chip_is_active.dart` →
    `iSeeTheSortChipIsActive(tester, String criterion)`: assert the chip with
    `Key('sort-chip-$criterion')` is selected (find the `ChoiceChip` by key,
    expect `selected == true`).

## Verification — `scripts/verify/d3.sh` (modeled on d1.sh)

Static asserts:
- `document_sort.dart` defines `sortDocuments`, `nextSort`, `class DocumentSort`.
- Case-insensitive guard: `toLowerCase()` appears in `document_sort.dart`.
- Keys present: `sort-control-bar`, `sort-chip-name`, `sort-chip-created`,
  `sort-chip-modified`, `sort-direction-asc`, `sort-direction-desc`.
- **`schemaVersion => 1`** unchanged (proves no schema bump).
- **No repo signature change:** `listDocumentSummaries()` in the interface
  still takes no arguments (grep the interface).
- Privacy spine: scrubber `minimalExifApp1` still present.

No-stub guard (mirror d1.sh): `i_tap_the_sort_chip.dart` contains
`sort-chip-`; `i_see_the_sort_chip_is_active.dart` contains `selected`;
generated `d3_sort_test.dart` calls `iTapTheSortChip(`,
`iSeeTheSortChipIsActive(`.

Codegen current (build_runner) + no uncommitted diff for `d3_sort_test.dart`.
`mobile:test` + `mobile:analyze` + `assert_coverage_floor 70`.
`verify_integration_android d3_sort_test.dart` + `verify_integration_ios ...`.
Fail-closed: `VERIFY_SKIP_DEVICE=1 → GATE:FAIL`. Opt-in `REAL_DEVICE` Tier-3
manual: tap each chip, confirm the list order changes on a physical device.

## Acceptance criteria

1. HomeScreen shows a sort control (3 chips: Name/Created/Modified) under the
   AppBar when the library is non-empty; hidden when empty/loading/error.
2. Tapping an inactive criterion sorts by it in that criterion's default
   direction (Name→asc, Created→desc, Modified→desc); tapping the active
   criterion flips direction; the active chip shows the matching arrow.
3. Name sort is case-insensitive; Created/Modified sort by their DateTime.
4. Ties resolve deterministically (`createdAt DESC` → `id`); no jitter.
5. The default sort on cold start is newest-created-first (unchanged from
   today); the choice is session-only and not persisted.
6. Sorting re-orders the list in-memory with no DB re-query; renamed/scanned/
   deleted documents re-position correctly after their existing `_load()`.
7. `schemaVersion` stays 1; `DocumentRepository` interface is unchanged; no new
   dependency; nothing leaves the device.
8. TDD/BDD: unit (sort logic), widget (control + HomeScreen), integration
   (both platforms), verify gate green; `REAL_DEVICE` Tier-3 deferred with
   standing sign-off.
