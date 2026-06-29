# E2 — Perspective Flatten: Design

**Status:** Approved (brainstorming) — ready for writing-plans
**Date:** 2026-06-29
**Roadmap:** Group E (Manual crop) — E1 corner overlay · E2 perspective flatten · E3 re-edit. E2 builds directly on E1 (corners persisted on `Pages`).

## Goal

Take the crop corners saved in E1 and produce a perspective-corrected (flattened)
JPEG of the document — so the viewer and PDF export show a head-on rectangle
rather than the original angled capture. The original image is never modified
(non-destructive); the flattened image is a derived cache written at save time.

## Decisions (locked during brainstorming)

1. **Imaging library:** `image` package (pure Dart, no native deps, runs in a
   `compute()` isolate). `ImageWarper` interface (DIP) hides the implementation.
2. **Timing:** flatten at `createFromCapture` time — the save spinner already
   exists; the extra CPU time is hidden there. The viewer shows the flat image
   immediately on first open.
3. **Storage:** a new nullable `Pages.flatRelativePath` TEXT column (schema v3
   migration). Null = no flat (full-frame or warp skipped). `DocumentFileStore`
   derives the flat path as `documents/$docId/page_${position}_flat.jpg`.
4. **Fallback:** a warp failure (exception, degenerate quad, self-crossing quad)
   **never blocks the save** — the original is always persisted first; the flat
   is best-effort. On failure `flatRelativePath` stays null and the viewer shows
   the original.
5. **Full-frame short-circuit:** `corners == CropCorners.fullFrame` → skip warp
   entirely; `flatRelativePath` null. No CPU wasted on an identity transform.
6. **Output sizing (#1 — edge-length, per feature-03 baseline):**
   `outW = max(|TR−TL|, |BR−BL|)`, `outH = max(|BL−TL|, |BR−TR|)`.
7. **Convex-quad guard (deferred by E1):** E2 checks convexity before warping;
   self-crossing quads throw `WarpException` (caught → null flat, save proceeds).
8. **Consumers:** `PageViewerScreen`, `PdfBuilder`, and the thumbnail path in
   `listDocumentSummaries` all switch from `imagePath` to `displayPath`
   (`flatImagePath ?? imagePath`).

## The coordinate-frame contract (inherited from E1)

Corners are normalized `[0..1]` in the **EXIF-applied display frame**. The
`image` package does **NOT** automatically apply EXIF Orientation on
`img.decodeImage()` — `img.bakeOrientation(src)` must be called immediately
after decode to rotate the pixel data into the display frame before any
coordinate math. After baking, `src.width/height` match the display-frame
dimensions and the flat output carries no Orientation tag (pixels are already
correctly oriented). Skipping this step would apply corners in the raw sensor
frame, producing a misaligned warp on any rotated capture.

Denormalization for the homography uses the baked pixel dimensions
(`src.width × src.height`), never a raw JPEG SOF header.

## Architecture

```
createFromCapture(capture, corners)
  → JpegExifScrubber.scrub(bytes)           (unchanged)
  → FileStore.writeRelative(rel, scrubbed)   (original, unchanged)
  → corners != fullFrame?
      yes → compute(warpFn, {bytes: scrubbed, corners})
               image pkg decodes bytes → bakeOrientation → naturalSize
               convexity check → WarpException if crossed
               edge-length output size
               solve homography H, invert → H⁻¹
               inverse-map + bilinear sample → output img.Image
               encodeJpg(quality: 92) → flatBytes
             → flatRel = flatRelativeFor(docId, position)
             → FileStore.writeRelative(flatRel, flatBytes)
             WarpException / any error → flatRel = null
      no  → flatRel = null
  → DB: insert page row (relativeImagePath, flatRelativePath = flatRel)
  → DB commit

getDocumentPages(docId)
  → reads flatRelativePath column
  → PageImage(imagePath: abs(rel), flatImagePath: abs(flatRel) if non-null, corners)

PageImage.displayPath  →  flatImagePath ?? imagePath
PageViewerScreen       →  Image.file(File(pg.displayPath))
PdfBuilder             →  File(page.displayPath).readAsBytes()
listDocumentSummaries  →  thumbnail = flatRelativePath ?? relativeImagePath
```

The warp runs inside a top-level `warpFn` function passed to `compute()` so it
is isolate-safe (no closures over mutable state). The `_db.transaction()` closure
awaits the result before the page insert — Drift allows async work in the closure.

## Components

### 1. `lib/features/library/image_warper.dart` (new)

DIP boundary — the widget layer and repository depend on this interface, never
on the `image` package directly.

```dart
abstract interface class ImageWarper {
  /// Returns flattened JPEG bytes, or null if [corners] are full-frame (no-op).
  /// [bytes] is the EXIF-scrubbed source JPEG.
  /// Throws [WarpException] for self-crossing or degenerate quads.
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners);
}

class WarpException implements Exception {
  final String message;
  const WarpException(this.message);
  @override
  String toString() => 'WarpException: $message';
}
```

`naturalSize` is derived by the implementation from the decoded bytes (not a
parameter) — after `img.decodeImage()` + `img.bakeOrientation()`, `src.width/height`
are in the EXIF-applied display frame. This keeps the interface minimal.

### 2. `lib/features/library/perspective_warper.dart` (new)

Pure-Dart implementation. All pixel work happens inside a static top-level
function so `compute()` can serialize it.

**Algorithm (inside `compute`):**

1. `corners == CropCorners.fullFrame` → return null.
2. Decode and orient: `img.Image src = img.bakeOrientation(img.decodeImage(bytes)!)`.
   `bakeOrientation` rotates pixel data to match the EXIF Orientation tag then
   strips the tag — `src.width/height` are now in the display frame, matching
   the stored corners.
3. Denormalize corners to pixel coords:
   `px = corner.dx * src.width`, `py = corner.dy * src.height`.
4. **Convexity guard:** compute 2-D cross-products at TL, TR, BR, BL; if any
   sign differs from the others (or any magnitude is zero), throw
   `WarpException('self-crossing or degenerate quad')`.
5. **Output size (edge-length #1):**
   `outW = max(dist(TL,TR), dist(BL,BR)).round()`,
   `outH = max(dist(TL,BL), dist(TR,BR)).round()`.
   If `outW < 2 || outH < 2` → throw `WarpException('degenerate quad')`.
6. **Homography (DLT 8-equation system):**
   Src corners (TL,TR,BR,BL) → dst corners (0,0),(W,0),(W,H),(0,H).
   Solve 8×8 linear system (Gaussian elimination in pure Dart) → 3×3 matrix H.
   Invert H → H⁻¹ for inverse mapping.
7. **Inverse raster scan:** for each `(dx, dy)` in `[0,outW) × [0,outH)`:
   map via H⁻¹ → `(sx, sy)`; bilinear-sample from `src` via
   `src.getPixelInterpolated(sx, sy, Interpolation.linear)`;
   write to output image.
8. `img.encodeJpg(output, quality: 92)` → `Uint8List`.

```dart
class PerspectiveWarper implements ImageWarper {
  const PerspectiveWarper();

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) =>
      compute(_warpFn, _WarpArgs(bytes: bytes, corners: corners));
}

// Top-level so compute() can serialize it.
Uint8List? _warpFn(_WarpArgs args) { ... }

class _WarpArgs {
  final Uint8List bytes;
  final CropCorners corners;
  const _WarpArgs({required this.bytes, required this.corners});
}
```

### 3. `pubspec.yaml`

Add under `dependencies`:
```yaml
image: ^4.5.0
```

### 4. `lib/features/library/drift/app_database.dart` (modify — schema v3)

```dart
// on Pages table
TextColumn get flatRelativePath => text().nullable()();

@override
int get schemaVersion => 3;

@override
MigrationStrategy get migration => MigrationStrategy(
  onUpgrade: (m, from, to) async {
    if (from < 2) await m.addColumn(pages, pages.corners);        // v1→v2 (E1)
    if (from < 3) await m.addColumn(pages, pages.flatRelativePath); // v2→v3 (E2)
  },
  beforeOpen: (details) async {
    await customStatement('PRAGMA foreign_keys = ON');
  },
);
```

Old and v2 rows have `flatRelativePath = null` → read as no flat.

### 5. `lib/features/library/document_file_store.dart` (modify)

```dart
String flatRelativeFor(int docId, int position) =>
    'documents/$docId/page_${position}_flat.jpg';
```

### 6. `lib/features/library/drift/drift_document_repository.dart` (modify)

- Constructor gains `required ImageWarper warper` (stored as `_warper`).
- `createFromCapture` extension after writing the scrubbed original:

```dart
String? flatRel;
if (corners != null && corners != CropCorners.fullFrame) {
  try {
    final flat = await _warper.warp(scrubbed, corners);
    if (flat != null) {
      flatRel = _fileStore.flatRelativeFor(docId, position);
      await _fileStore.writeRelative(flatRel!, flat);
    }
  } catch (_) { /* WarpException or IO error — flat stays null */ }
}
await _db.into(_db.pages).insert(
  PagesCompanion.insert(
    ...,
    corners: Value(corners?.toStorage()),
    flatRelativePath: Value(flatRel),
  ),
);
```

- `getDocumentPages` maps the new column:

```dart
PageImage(
  position: pg.position,
  imagePath: _fileStore.absoluteFor(pg.relativeImagePath).path,
  corners: CropCorners.tryParse(pg.corners) ?? CropCorners.fullFrame,
  flatImagePath: pg.flatRelativePath == null
      ? null
      : _fileStore.absoluteFor(pg.flatRelativePath!).path,
)
```

- `listDocumentSummaries` thumbnail prefers flat:

```dart
firstPathByDoc.putIfAbsent(
  pg.documentId,
  () => pg.flatRelativePath ?? pg.relativeImagePath,
);
```

### 7. `lib/features/library/page_image.dart` (modify)

```dart
class PageImage {
  final int position;
  final String imagePath;          // original (E3 re-edit source)
  final CropCorners corners;
  final String? flatImagePath;     // null = no flat (full-frame or warp skipped)

  const PageImage({
    required this.position,
    required this.imagePath,
    this.corners = CropCorners.fullFrame,
    this.flatImagePath,
  });

  /// Display/export path: flat when available, original otherwise.
  String get displayPath => flatImagePath ?? imagePath;
}
```

Existing construction sites pass no `flatImagePath` → defaults to null → non-breaking.

### 8. `lib/features/library/page_viewer_screen.dart` (modify)

```dart
// one-line change in _buildPages:
Image.file(File(pg.displayPath), fit: BoxFit.contain, ...)
```

### 9. `lib/features/library/pdf/pdf_builder.dart` (modify)

```dart
// one-line change in build():
final bytes = await File(page.displayPath).readAsBytes();
```

### 10. `lib/features/library/library_dependencies.dart` (modify)

Add `warper: const PerspectiveWarper()` to the `DriftDocumentRepository(...)` call
inside `_defaultCreateRepository()` (the production wiring function).

### 11. `test/support/fake_library.dart` (modify)

`DriftDocumentRepository` gains `required ImageWarper warper`, so the two helpers
that construct it directly will fail to compile without the new argument.

- **`FakeImageWarper`** (add to this file):

```dart
class FakeImageWarper implements ImageWarper {
  final bool throws;
  final Uint8List? returnValue;   // null = simulate full-frame / no-op
  int calls = 0;
  FakeImageWarper({this.throws = false, this.returnValue});

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) async {
    calls++;
    if (throws) throw WarpException('fake: warp failed');
    return returnValue;
  }
}
```

- **`tempLibraryDependencies()`** — add `warper: const PerspectiveWarper()` (uses
  real warper; integration scenarios exercise the real path).
- **`persistentLibraryDependencies()`** — same.

`FakeDocumentRepository` itself does not change — it never calls the warper
(that logic lives only in `DriftDocumentRepository`).

## Error handling & edge cases

| Scenario | Behavior |
|---|---|
| `corners == CropCorners.fullFrame` | Skip warp; `flatRelativePath` null; viewer shows original |
| Self-crossing quad | `WarpException` caught; `flatRelativePath` null; save succeeds |
| Degenerate quad (< 2 px output) | `WarpException` caught; `flatRelativePath` null; save succeeds |
| `image` decode fails | Exception caught; same fallback |
| Flat file write fails | Exception caught; `flatRelativePath` null; save succeeds |
| `flatImagePath` set but file deleted later | `Image.file` `errorBuilder` shows broken-image icon (existing behavior) |

The original is always persisted before the warp is attempted. A partial save
(original written, warp failed) leaves the document in a fully usable state.

## Privacy spine

No new network access. The flat JPEG is written to the same on-device document
directory as the original. It is scrubbed source bytes warped — EXIF headers are
stripped by the `image` package re-encode (no GPS/device metadata in output).

## Testing (TDD/BDD)

- **Unit `perspective_warper_test.dart` (new):**
  `fullFrame` → null; valid non-trivial quad → returns JPEG with edge-length
  dimensions; self-crossing quad → `WarpException`; degenerate (zero-area) →
  `WarpException`; convexity cross-product helper; output-size formula;
  **rotated-image round-trip**: synthesize a JPEG with EXIF Orientation ≠ 1
  (90° rotation), warp with a known rectangular quad in the display frame, assert
  output dimensions match edge-length in the display (not sensor) frame — guards
  the `bakeOrientation` contract is exercised end-to-end.

- **Widget `page_viewer_screen_test.dart` (extend):**
  `PageImage` with `flatImagePath` set → viewer file key resolves to flat path;
  `flatImagePath: null` → falls back to `imagePath`.

- **`pdf_builder_test.dart` (extend):**
  `PdfBuilder` reads `page.displayPath`; when `flatImagePath` is set the flat
  bytes are embedded.

- **Repo `drift_document_repository_test.dart` (extend):**
  Inject `FakeImageWarper`; non-full-frame corners → `flatRelativePath` stored
  and round-trips through `getDocumentPages`; full-frame corners →
  `flatRelativePath` null; warper throws → `flatRelativePath` null and save
  returns a valid document.

- **Migration `drift/migration_test.dart` (extend):**
  v2 → v3: `flatRelativePath` column appears; existing rows read null; fresh
  write with non-null flat path round-trips.
  v1 → v3 (cumulative): build a v1 DB (no `corners`, no `flatRelativePath`),
  open at v3, assert both columns added and old rows survive.

- **BDD `e2_flatten.feature` (new):**
  _Given_ I launch the app _and_ scan a document with non-full-frame corners
  _When_ I accept _and_ I open the first document
  _Then_ I see the page viewer (finds `page-viewer-page-0`).
  Automated assertion: `page-viewer-page-0` is present in the widget tree —
  visual correctness (that the image is actually flattened) is deferred to the
  `REAL_DEVICE` Tier-3 lane. Reuses existing launch/scan/shutter/accept/
  `i_open_the_first_document` steps; adds one new step
  `i_see_the_page_viewer` (finds `page-viewer-page-0`).

- **Verify `scripts/verify/e2.sh` (new):**
  Static asserts: `ImageWarper`; `WarpException`; `PerspectiveWarper`;
  `bakeOrientation` call present in `perspective_warper.dart` (guards the
  EXIF-frame contract — absence = silent misalignment on rotated captures);
  `FakeImageWarper` present in `test/support/fake_library.dart`;
  `tempLibraryDependencies` passes `warper:` arg;
  `flatRelativePath` column + `onUpgrade` `addColumn`; `flatRelativeFor`;
  `displayPath` getter; `image:` in pubspec; schema v3; no-uncommitted-generated-diff;
  codegen current; `mobile:test` + `mobile:analyze`; `assert_coverage_floor 70`;
  `verify_integration_android/ios e2_flatten_test.dart`; fail-closed
  `VERIFY_SKIP_DEVICE=1 → GATE:FAIL`; opt-in `REAL_DEVICE` Tier-3 (capture angled
  doc, confirm flat result in viewer and PDF).

## Acceptance criteria

- [ ] Non-full-frame corners → flattened JPEG written at save time; `flatRelativePath`
  persisted in DB; viewer and PDF use the flat image — *repo round-trip test +
  BDD*
- [ ] Full-frame corners → no flat file written; `flatRelativePath` null; viewer/PDF
  use original — *repo test*
- [ ] Warp failure (crossed quad, degenerate, decode error) → `flatRelativePath`
  null; save still succeeds; viewer shows original — *repo test (injected
  throwing warper)*
- [ ] Output dimensions follow edge-length sizing (#1): width = max(top-edge,
  bottom-edge), height = max(left-edge, right-edge) — *unit: output-size formula*
- [ ] Self-crossing quads throw `WarpException`; degenerate (< 2 px) throws
  `WarpException` — *unit: convexity + degenerate guards*
- [ ] `img.bakeOrientation()` is applied before coordinate math — corners (stored
  in EXIF-applied frame) are correctly aligned with decoded pixels on any
  rotated capture — *static assert in verify script + unit: warp of a
  synthetically rotated image produces correct output*
- [ ] Schema v2 → v3 migration adds `flatRelativePath`; existing rows survive as
  null; fresh write round-trips — *migration test*
- [ ] `PageViewerScreen` and `PdfBuilder` use `displayPath` (flat when available,
  original otherwise) — *widget + pdf tests*
- [ ] Thumbnail in document list prefers flat path — *repo test*
- [ ] `ImageWarper` is a DIP interface; `PerspectiveWarper` never imported by
  widget layer — *static assert in verify script*
- [ ] Privacy: flat JPEG carries no EXIF metadata (re-encoded clean by `image`
  pkg); no new network access — *static assert (no new network dep)*
- [ ] TDD/BDD: unit + widget + repo + migration + both-platform integration +
  verify gate green; `REAL_DEVICE` Tier-3 deferred with standing sign-off

---

> **Definition of Done gate:** Per `00-overview-roadmap.md`, nothing is done
> until every acceptance criterion above maps to a passing test, the full suite
> is run and observed green, quality gates pass, and the work is reviewed and
> double-checked. Evidence before assertions, always.
