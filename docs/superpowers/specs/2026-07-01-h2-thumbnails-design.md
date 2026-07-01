# H2 Page Thumbnail Strip — Implementation Design

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** H1 (`addPageToDocument`, `_activeDocId`/`_pageCount` in `CameraScreen`), B1/B3 (`PageViewerScreen`, `getDocumentPages`)
**Feeds:** H3 (reorder — will convert strip to drag-reorder), H4 (delete/retake — will add long-press on strip tiles)
**Step in roadmap:** H2 — Page thumbnail strip

---

## Purpose

Add a horizontal scrollable strip of page thumbnails to the bottom of `PageViewerScreen`.
Replaces the "X / N" text indicator. Tapping a thumbnail animates the `PageView` to that
page. The strip auto-scrolls to keep the current page visible when the user swipes.

This is the foundational strip that H3 and H4 will extend (drag-reorder and per-page
delete/retake without modifying the strip widget's API).

### In scope

- New `PageThumbnailStrip` widget — pure display, no repository calls
- Replace "X / N" text indicator in `PageViewerScreen` with the strip
- Wire strip tap → `PageController.animateToPage`
- Strip auto-scrolls to active thumbnail on page change
- BDD scenario: viewer with 2 pages → see 2 thumbnails → tap second → page 2 visible
- `scripts/verify/h2.sh`

### Out of scope

- Thumbnail strip on `CameraScreen` during a scan session (the "N pages saved" text
  counter is sufficient for H2; no session-strip planned until feedback requires it)
- Reorder (H3), delete/retake per page (H4)
- Strip on any screen other than `PageViewerScreen`

---

## Architecture

### New file: `lib/features/library/widgets/page_thumbnail_strip.dart`

Pure display widget. Receives data, emits callbacks. No async, no repository.

```dart
/// Horizontal scrollable strip of page thumbnails.
/// [currentIndex] is 0-based, matching [PageView] / [PageController].
/// Auto-scrolls to keep the active thumbnail visible when [currentIndex] changes.
/// Tapping a tile calls [onTap] with that tile's 0-based index.
class PageThumbnailStrip extends StatefulWidget {
  final List<PageImage> pages;
  final int currentIndex;
  final void Function(int index) onTap;

  const PageThumbnailStrip({
    super.key,
    required this.pages,
    required this.currentIndex,
    required this.onTap,
  });
}
```

**Dimensions (fixed):**
- Tile: 56 px wide × 80 px tall (portrait 7:10, close to A4 ratio)
- Horizontal margin per tile: 4 px each side (8 px total slot → effective slot = 64 px)
- Strip height: 96 px (80 tile + 8 top + 8 bottom padding)
- Strip background: `Colors.black`

**Per-tile rendering (`Key('page-thumb-$index')`, 0-based):**
```dart
Image.file(
  File(pages[index].displayPath),
  width: 56,
  height: 80,
  fit: BoxFit.cover,
  cacheWidth: (56 * dpr).round(),
  errorBuilder: (_, __, ___) => placeholder,
)
```
Placeholder: `Container(color: surfaceContainerHighest, child: Icon(Icons.description_outlined))`

**Current-page highlight:** 2 px border in `Theme.of(context).colorScheme.primary`.

**Auto-scroll implementation:**
Internal `ScrollController`. On `didUpdateWidget` when `currentIndex` changes (and on first
`initState`), animate to center the active tile:
```dart
void _scrollToCurrent() {
  if (!_scrollController.hasClients) return;
  const kSlot = 64.0;
  const kPad = 8.0;
  // Center the active tile in the strip viewport.
  // Approximation: scroll left edge to (index × slot) — half viewport + half tile.
  // We don't have viewport width here, so use a fixed conservative offset:
  // just scroll to bring the item's left edge to the start of the visible area.
  final target = (kPad + currentIndex * kSlot)
      .clamp(0.0, _scrollController.position.maxScrollExtent);
  _scrollController.animateTo(
    target,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
  );
}
```

**Keys:**
| Widget | Key |
|--------|-----|
| `ListView` (the strip itself) | `Key('page-thumbnail-strip')` |
| Each tile | `Key('page-thumb-$index')` (0-based) |

---

### Modified: `lib/features/library/page_viewer_screen.dart`

**Remove:** the `Positioned` "X / N" text indicator and its `Key('page-viewer-indicator')`.

**Add:** `PageThumbnailStrip` at the bottom of the page view area.

Replace `_buildPages`:

```dart
Widget _buildPages(List<PageImage> pages) {
  return Column(
    children: [
      Expanded(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) {
                final pg = pages[i];
                return InteractiveViewer(
                  key: Key('page-viewer-page-${pg.position}'),
                  child: Image.file(
                    File(pg.displayPath),
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 64),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      PageThumbnailStrip(
        key: const Key('page-thumbnail-strip'),
        pages: pages,
        currentIndex: _current,
        onTap: (i) => _controller.animateToPage(
          i,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ),
      ),
    ],
  );
}
```

**OCP:** `FilterPickerStrip`, `EnhancerMode`, all enhancers, `DriftDocumentRepository.createFromCapture()`,
and `addPageToDocument` must NOT be modified.

---

## Data Flow

```
PageViewerScreen._load()
  → repository.getDocumentPages(documentId)
  → _pages: List<PageImage>
  → _buildPages(_pages)
    → Column [
        Expanded → PageView.builder (full-resolution, pinch-zoom)
        PageThumbnailStrip(pages: _pages, currentIndex: _current, onTap: ...)
      ]

User swipes PageView:
  onPageChanged(i) → setState(_current = i)
  → PageThumbnailStrip.didUpdateWidget(currentIndex = i)
  → _scrollController.animateTo(...)

User taps thumbnail i:
  PageThumbnailStrip.onTap(i)
  → _controller.animateToPage(i, ...)
  → PageView fires onPageChanged(i)
  → setState(_current = i) (already i — no-op but harmless)
```

---

## Testing Strategy

| Layer | What is tested |
|-------|----------------|
| Widget: `PageThumbnailStrip` | Renders N tiles for N pages; `Key('page-thumb-0')` … present |
| Widget: `PageThumbnailStrip` | Current tile has primary-color border; others do not |
| Widget: `PageThumbnailStrip` | Tapping tile i calls `onTap(i)` |
| Widget: `PageViewerScreen` | With 2 pages: `Key('page-thumbnail-strip')` present; `Key('page-viewer-indicator')` absent |
| Widget: `PageViewerScreen` | Tapping `page-thumb-1` triggers page navigation (calls animateToPage via onTap stub) |
| BDD | Viewer open with 2-page doc → 2 thumbnails visible → tap second → page 2 shown |
| Static | `PageThumbnailStrip` class in `page_thumbnail_strip.dart` |
| Static | `Key('page-thumbnail-strip')` in `page_viewer_screen.dart` |
| Static | `Key('page-thumb-` in `page_thumbnail_strip.dart` |

---

## BDD Scenarios

**Feature file:** `integration_test/h2_page_thumbnail_strip.feature`

```gherkin
Feature: H2 Page thumbnail strip

  Scenario: Thumbnail strip is visible with multiple pages
    Given the page viewer is open with a 2-page document
    Then I see 2 page thumbnails in the strip

  Scenario: Tapping a thumbnail navigates to that page
    Given the page viewer is open with a 2-page document
    When I tap the second page thumbnail
    Then the page viewer shows page 2
```

---

## Verify Script

`scripts/verify/h2.sh` — follows `lib.sh` pattern:
- Static: `PageThumbnailStrip` in `page_thumbnail_strip.dart`; `Key('page-thumbnail-strip')` in `page_viewer_screen.dart`; `Key('page-thumb-` in `page_thumbnail_strip.dart`; feature file exists; generated test exists
- `pnpm nx run mobile:test` passes
- `pnpm nx run mobile:analyze` clean
- Coverage ≥ 70%
- BDD device gate (skippable with `VERIFY_SKIP_DEVICE=1`)

---

## Deliverable (user-testable)

Open a multi-page document → the bottom of the viewer shows a horizontal strip of page
thumbnails. Tap any thumbnail → the viewer jumps to that page. Swipe the main view →
the strip scrolls to keep the active thumbnail visible.

**Test it by:**
1. Take 2 scans (H1 flow) → tap Done → open the document.
2. The viewer shows a thumbnail strip at the bottom with 2 tiles.
3. Swipe to page 2 → the second thumbnail gets a highlight border.
4. Tap the first thumbnail → view jumps back to page 1.

---

## Acceptance Criteria

- [ ] `PageThumbnailStrip` class exists in `page_thumbnail_strip.dart` — *static*
- [ ] Strip shows one tile per page; each tile renders the page's `displayPath` — *widget*
- [ ] Current tile has a primary-color 2 px border — *widget*
- [ ] Tapping tile i calls `onTap(i)` — *widget*
- [ ] `PageViewerScreen` shows strip; old "X / N" indicator is gone — *widget*
- [ ] Strip tap → `PageController.animateToPage` (page navigation) — *widget*
- [ ] BDD: 2-page viewer → 2 thumbnails visible — *integration*
- [ ] BDD: tap second thumbnail → page 2 shown — *integration*
- [ ] All host tests pass; analyze clean; coverage ≥ 70% — *verify script*

---

> **Definition of Done gate:** Per `00-overview-roadmap.md`, this feature is not done until
> every acceptance criterion above maps to a passing test, the full suite is green, quality
> gates pass, and the work is reviewed and double-checked.
