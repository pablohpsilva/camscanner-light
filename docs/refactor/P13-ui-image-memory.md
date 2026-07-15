# P13 — UI image memory & decoding

**Tier 4 (Perf/Safety) · Effort M · Risk Med · Depends on: none (coordinates with P06 task 7 on the reload/cache path) · Device verification: real Android AND real iOS (mandatory — this touches native decode/memory)**

## Summary

The library UI has five image-memory / decoding inefficiencies. Two are on the
page viewer's hot path — a full-resolution decode of the display image with no
`cacheWidth`, and a **global** `imageCache.clear()` on every crop/rotate/filter —
both of which the code itself flags as memory-unsafe. Two are wasted work on the
capture-review screen (reading the same full-res JPEG off disk twice, and running
a full 5 s detection pass even after the user has already dragged a handle). The
last is a latent drift risk: an auto-scroll slot width derived by hand from
literals scattered across the thumbnail strip.

Because every item here touches native decode/memory behavior — and the page
viewer's fixes interact with the deliberate zoom/epoch stale-frame handling —
**device verification on real Android AND real iOS is mandatory**, not optional.
Behavior (zoom sharpness, no stale frame after an edit, detection accuracy) must
be visually confirmed on-device before any of these is called done.

## Verified findings

| ID | Current location | What's wrong | Impact | live/latent |
| --- | --- | --- | --- | --- |
| full-res-decode | `page_viewer_screen.dart`:815–819 — main `Image.file(File(pg.displayPath), key: ValueKey('${pg.displayPath}#$_imageEpoch'), fit: BoxFit.contain, …)`; class doc :38–41 explicitly says "not memory-safe for many pages… add screen-width cacheWidth" | The display image decodes at **full camera resolution** (up to 12.5 MP) with no `cacheWidth`, even though it's only ever shown fit-to-screen | High RAM per page; on multi-page docs this is the documented OOM risk | live |
| imagecache-clear-global | `page_viewer_screen.dart` `_reloadAfterEdit`:119–127 — `PaintingBinding.instance.imageCache.clear()` + `clearLiveImages()` on **every** crop/rotate/filter | A single edit evicts **every** cached image app-wide (thumbnails, other screens), forcing needless re-decode churn | Perf: wholesale cache thrash per edit; only the edited page's `FileImage` actually needs eviction | live |
| PERF-1-double-read | `capture_review_screen.dart` — `initState` `widget.readBytes(...)` for `_sourceBytes` :99–105 AND `_runDetection` `widget.readBytes(...)` again :113 | The full-res JPEG is read off disk **twice** on every review open | Wasted I/O + a second full-file allocation on a memory-tight screen | live |
| PERF-2-detection-wasted | `capture_review_screen.dart` `_runDetection`:108–125 — awaits `readBytes` then `detector.detect(bytes)` (5 s isolate) and only checks `_userInteracted` **after** detection completes (:115) | A full detection pass (5 s isolate) runs to completion even if the user already dragged a handle or hit Reset (`_userInteracted` already true) | Wasted CPU/battery/isolate time; result is computed then discarded | live |
| kSlot-magic-number | `page_thumbnail_strip.dart`:56 — `const double kSlot = 64.0; // 56 tile + 4 + 4`, derived by hand from literals: tile width `56` (:79/:99), margin `4` (:88), `cacheWidth (56*dpr)` (:102) | `kSlot` is a hand-summed constant; the tile-size literals it depends on are duplicated and don't reference it | A tile-size tweak silently breaks auto-scroll targeting (off-by-slot) | latent (correct today; breaks silently on future edit) |

## Definition of done

- The page viewer's display `Image.file` uses a **screen-width `cacheWidth`**
  (derived from `MediaQuery` width × devicePixelRatio) so the fit-to-screen view
  no longer decodes at full resolution. Zoom may lazily upgrade to a full-res
  decode; the interaction with the `_imageEpoch` stale-frame key is preserved and
  **device-verified** (zoom stays sharp, no stale frame after an edit).
- `_reloadAfterEdit` no longer calls the global `imageCache.clear()` /
  `clearLiveImages()`. Instead an injectable `ImageCacheInvalidator` evicts only
  the affected `FileImage(File(path))` (+ its `ResizeImage` variant if a
  `cacheWidth` is used). Default production impl does the scoped eviction; tests
  inject a spy. The epoch bump stays for the stale-frame fix; **device-verified**
  that an edit still shows the new image and other cached images survive.
- Capture-review reads the source bytes **once**: `initState` starts a single
  `Future<Uint8List>` that both `_sourceBytes` and `_runDetection` await (no
  second `readBytes`).
- `_runDetection` re-checks `_userInteracted` **before** starting
  `detector.detect` (and ideally after `readBytes` too), so an already-interacted
  user skips the wasted 5 s detection pass.
- `page_thumbnail_strip.dart` defines `kTileWidth` and `kTileMargin` **once** and
  derives `kSlot = kTileWidth + 2*kTileMargin`; the tile builder and `cacheWidth`
  reference those constants (no bare `56`/`4`).
- All existing widget + BDD suites stay green; new unit/widget tests cover the
  invalidator scoping, the single-read, the pre-detection interaction check, and
  the derived-`kSlot` arithmetic.
- Device-verified on real Android AND real iOS for the page-viewer decode/cache
  changes and the capture-review changes (native decode + isolate detection).

## Before → After

| Aspect | Before | After |
| --- | --- | --- |
| Display decode | `Image.file` at **full resolution**, no `cacheWidth` (page_viewer:815–819); doc admits it's not memory-safe | Screen-width `cacheWidth` for the fit-to-screen view; zoom lazily upgrades to full-res |
| Cache eviction per edit | **Global** `imageCache.clear()` + `clearLiveImages()` — evicts everything app-wide | Scoped `ImageCacheInvalidator.evict(FileImage(path))` — only the edited page |
| Source bytes on review | Read off disk **twice** (`_sourceBytes` + `_runDetection`) | Read **once**; both await the same `Future` |
| Detection after interaction | Full 5 s detect runs, checked only **after** completion | `_userInteracted` re-checked **before** `detect`; skipped if already interacted |
| Thumbnail slot width | Hand-summed `kSlot = 64.0` from scattered `56`/`4` literals | `kSlot = kTileWidth + 2*kTileMargin`, single source; builder/cacheWidth reference the constants |

## Tasks

Each task is independent, subagent-runnable, TDD-first, and keeps every suite
green. Tasks 3, 4, 5 are self-contained and fully parallel; tasks 1 and 2 both
touch the page viewer and coordinate with P06 task 7.

1. **Add screen-width `cacheWidth` to the page-viewer display image
   (`full-res-decode`).**
   Scope: `page_viewer_screen.dart`:801–826 (`_buildPages`). Compute
   `cacheWidth` from `MediaQuery.sizeOf(context).width * devicePixelRatio`,
   rounded; apply to the main `Image.file`. Preserve the `_imageEpoch` key.
   Consider (and document) whether zoom needs a full-res upgrade path; if so,
   scope it to a follow-up or gate it behind zoom scale.
   Test-first: widget test asserting the Image is built with a bounded
   `cacheWidth` (via a testable seam or by asserting the ResizeImage provider);
   full page_viewer suite green.
   Done: green host tests **+ device-verified** on Android AND iOS (zoom still
   sharp, no regression). Parallel-safe: coordinate with task 2 (same file).

2. **Replace global cache wipe with scoped `ImageCacheInvalidator`
   (`imagecache-clear-global`).**
   Scope: new `lib/features/library/image_cache_invalidator.dart` (injectable;
   default impl evicts `FileImage(File(path))` and, if task 1 landed, the
   matching `ResizeImage`). Rewire `_reloadAfterEdit`:119–127 to evict only the
   edited page's path instead of `clear()`/`clearLiveImages()`. Thread it through
   the Dependencies class (per project DI convention), not `new`-ed inline.
   Test-first: unit test that the invalidator evicts exactly the target provider
   and leaves others; widget test with a spy invalidator that `_reloadAfterEdit`
   calls it with the edited path, not a global clear.
   Done: green **+ device-verified** that a crop/rotate/filter shows the new
   image while other thumbnails survive. Parallel-safe: coordinate with task 1
   (same file) and P06 task 7 (which moves `_reloadAfterEdit` onto the
   controller — land the invalidator so the controller calls it).

3. **Read source bytes once on capture-review (`PERF-1-double-read`).**
   Scope: `capture_review_screen.dart`:88–125. In `initState`, start a single
   `Future<Uint8List> _bytesFuture = widget.readBytes(widget.image.path)`; have
   both the `_sourceBytes` setter and `_runDetection` `await` it instead of each
   calling `readBytes`.
   Test-first: a fake `readBytes` counter asserting it is invoked **once** per
   screen open (was twice); existing review tests green.
   Done: green host test **+ device-verified** review opens correctly.
   Parallel-safe: yes (isolated file; independent of tasks 1,2,5).

4. **Skip wasted detection after interaction (`PERF-2-detection-wasted`).**
   Scope: `capture_review_screen.dart` `_runDetection`:108–125. Re-check
   `if (!mounted || _userInteracted) return;` **before** `detector.detect(...)`
   (and after the awaited read), so an already-interacted user never pays for the
   5 s isolate. Preserve the existing post-detect guard (:115) too.
   Test-first: a fake detector counting `detect` calls; simulate
   `_userInteracted = true` before detection starts and assert `detect` is **not**
   called; and the normal path still calls it once and applies corners.
   Done: green host test **+ device-verified** (detect skipped when user drags
   first; still runs on the untouched path). Parallel-safe: yes (same file as
   task 3 — sequence the two or split the edits; both are small and local).

5. **Derive `kSlot` from named tile constants (`kSlot-magic-number`).**
   Scope: `page_thumbnail_strip.dart`:54–107. Define
   `static const double kTileWidth = 56;` and `kTileMargin = 4;` (top of the
   State or as file constants); set `kSlot = kTileWidth + 2 * kTileMargin`; make
   `_buildTile`'s `width`/`margin`/`cacheWidth` reference them (no bare `56`/`4`).
   Test-first: a unit test asserting `kSlot == kTileWidth + 2*kTileMargin`, plus a
   widget test that auto-scroll targets `kPad + index*kSlot` (the existing scroll
   behavior is unchanged).
   Done: green; a future tile-size change can't silently break auto-scroll.
   Parallel-safe: yes (isolated file; no device needed — pure layout arithmetic,
   though a quick on-device scroll sanity check is cheap).

## Risks & mitigations

- **`cacheWidth` makes zoom blurry.** Mitigation: bound `cacheWidth` to
  screen-width × DPR (already the resolution the user sees fit-to-screen);
  device-verify pinch-zoom sharpness on both platforms; if a full-res zoom is
  required, gate an upgrade behind zoom scale as a follow-up rather than reverting.
- **Scoped eviction leaves a stale frame after an edit.** Mitigation: keep the
  `_imageEpoch` key bump (it forces element recreation) alongside the scoped
  evict; unit-test the invalidator evicts the exact provider; device-verify the
  crop/rotate/filter regeneration shows the fresh image (this is the exact bug
  the global clear was papering over).
- **Interaction with P06 task 7 (`_reloadAfterEdit` moves to the controller).**
  Mitigation: land `ImageCacheInvalidator` as an injectable collaborator so
  whichever owner (widget now, controller after P06) calls it identically;
  coordinate ordering with P06.
- **Detection-skip changes timing and flakes a device test.** Mitigation: the
  pre-detect guard only short-circuits when `_userInteracted` is already true (a
  strict subset of current behavior); assert both branches with a fake detector;
  device-verify the untouched path still auto-detects.
- **`cacheWidth`/DPR needs a `BuildContext`.** Mitigation: read it in `build`
  where `MediaQuery` is available (not in a controller); keep the value derivation
  out of any pumped-widget-free unit test by exposing a small pure helper for the
  arithmetic.

## Verification commands

```bash
# From apps/mobile/
flutter analyze
dart format lib test
dart run build_runner build --delete-conflicting-outputs

# Host: scoping / single-read / skip-detection / kSlot arithmetic
flutter test test/features/library/image_cache_invalidator_test.dart
flutter test test/features/scan/capture_review_screen_test.dart
flutter test test/features/library/widgets/page_thumbnail_strip_test.dart
flutter test test/features/library/page_viewer_screen_test.dart
flutter test                                   # full host suite green

# Device (BOTH platforms, mandatory — native decode + memory + isolate)
flutter test integration_test/k1_rotate_page_device_test.dart -d <android-device-id>
flutter test integration_test/k1_rotate_page_device_test.dart -d <ios-device-id>
# plus a capture-review device run exercising detect + review decode
flutter test integration_test/<capture_review>_device_test.dart -d <android-device-id>
flutter test integration_test/<capture_review>_device_test.dart -d <ios-device-id>
```
