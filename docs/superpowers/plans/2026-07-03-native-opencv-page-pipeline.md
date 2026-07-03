# Native OpenCV Page Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ~5 s pure-Dart warp+enhance in the save path with a native OpenCV (dartcv) pipeline (<1 s/page), keeping the pure-Dart pipeline as a transparent fallback.

**Architecture:** A `PageProcessor` seam (`process(bytes, corners, mode) → Uint8List?`) with three impls: `NativePageProcessor` (dartcv in a timeout-guarded `compute` isolate), `DartPageProcessor` (encapsulates today's shipped warp+enhance behavior), and `FallbackPageProcessor` (native → Dart on failure). The repository routes both the full-frame enhance and the cropped flat through the injected `PageProcessor`.

**Tech Stack:** Dart/Flutter, `package:opencv_dart/opencv_dart.dart as cv` (dartcv4, already a dependency), `package:image` (Dart fallback), drift.

## Global Constraints

- Quality parity is a GATE: native Auto output must match Dart Auto — device parity test mean abs pixel diff < 2.0/255 (JPEG-recompression noise aside); Color/Grayscale visually sane.
- Never lose a page: every save yields a stored, correctly-processed page via fallback.
- No UI/public-API change: UI keeps passing `ImageEnhancer`; repository maps to `EnhancerMode` via `enhancerModeOf` (exists in `lib/features/library/warp_enhancer.dart`).
- Flat long side capped at `kDefaultFlatMaxDimension` (= 3500), defined in `lib/features/library/perspective_warper.dart`.
- Native runs in a `compute()` isolate wrapped with `.timeout(const Duration(seconds: 5))`; on `TimeoutException` → treat as null → fallback. (A wedged native isolate cannot be killed; the timeout is the recovery.)
- Strict Mat dispose in `finally` (two-tier, like `lib/features/scan/opencv_edge_detector.dart`).
- Auto constants MUST equal the Dart ones: proxy long side 512, dilate radius 7 (→ 15×15 kernel), blur radius 12, white clip 0.01, black anchor 0.55, max gain 6.0, Auto JPEG quality 95, others 92.
- `NativePageProcessor` handles full-frame + STRAIGHT crops only. Bent crops (`!corners.isStraight`) → native returns null → Dart Coons fallback.
- libdartcv cannot load under host `flutter test`; native impls are verified only via `integration_test` on device RZCY51D0T1K. Pure-Dart parts are host-TDD'd.

---

## File Structure

- Create `lib/features/library/page_processor.dart` — the `PageProcessor` interface (+ the `none && fullFrame → null` contract doc).
- Create `lib/features/library/dart_page_processor.dart` — `DartPageProcessor` encapsulating today's shipped behavior (full-frame enhance + cropped warp+enhance with the real-vs-fake warper dispatch).
- Create `lib/features/library/fallback_page_processor.dart` — `FallbackPageProcessor`.
- Create `lib/features/library/native_page_processor.dart` — `NativePageProcessor` (dartcv pipeline).
- Modify `lib/features/library/auto_enhancer.dart` — make the six tuning constants public so the native pipeline reuses them verbatim.
- Modify `lib/features/library/drift/drift_document_repository.dart` — inject `PageProcessor`; route full-frame enhance (~L83-87) and `_enhancedFlat` (~L135) through it.
- Modify `lib/features/library/library_dependencies.dart` — inject `FallbackPageProcessor(NativePageProcessor(), DartPageProcessor(HybridWarper()))`.
- Tests: `test/features/library/dart_page_processor_test.dart`, `test/features/library/fallback_page_processor_test.dart`, `integration_test/np1_native_pipeline_test.dart`, `integration_test/np2_native_auto_parity_test.dart`, `integration_test/np3_native_color_gray_test.dart`.

---

## Task 1: PageProcessor interface + DartPageProcessor

**Files:**
- Create: `lib/features/library/page_processor.dart`
- Create: `lib/features/library/dart_page_processor.dart`
- Test: `test/features/library/dart_page_processor_test.dart`

**Interfaces:**
- Consumes: `EnhancerMode` (`lib/features/library/enhancer_mode.dart`), `CropCorners` (`lib/features/library/crop_corners.dart`), `warpAndEnhance` + `enhancerModeOf` (`lib/features/library/warp_enhancer.dart`), `ImageWarper` (`lib/features/library/image_warper.dart`), the enhancer classes (`auto_enhancer.dart`, `color_enhancer.dart`, `grayscale_enhancer.dart`, `image_enhancer.dart`), `HybridWarper`/`PerspectiveWarper`/`CoonsWarper`.
- Produces:
  - `abstract interface class PageProcessor { Future<Uint8List?> process(Uint8List bytes, CropCorners corners, EnhancerMode mode); }`
  - `class DartPageProcessor implements PageProcessor { const DartPageProcessor(this.warper); final ImageWarper warper; ... }`

- [ ] **Step 1: Write the failing test**

Create `test/features/library/dart_page_processor_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/dart_page_processor.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/hybrid_warper.dart';

Uint8List _jpeg(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(40, 40, 40));
  img.fillRect(im, x1: w ~/ 5, y1: h ~/ 5, x2: 4 * w ~/ 5, y2: 4 * h ~/ 5,
      color: img.ColorRgb8(220, 215, 205));
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

const _rect = CropCorners(
  topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
  bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9));

void main() {
  const p = DartPageProcessor(HybridWarper());

  test('none + fullFrame → null (nothing to do)', () async {
    final out = await p.process(_jpeg(200, 150), CropCorners.fullFrame, EnhancerMode.none);
    expect(out, isNull);
  });

  test('auto + fullFrame → enhanced JPEG (decodable)', () async {
    final out = await p.process(_jpeg(200, 150), CropCorners.fullFrame, EnhancerMode.auto);
    expect(out, isNotNull);
    expect(img.decodeImage(out!), isNotNull);
  });

  test('auto + straight crop → warped+enhanced JPEG, smaller than source', () async {
    final out = await p.process(_jpeg(400, 300), _rect, EnhancerMode.auto);
    expect(out, isNotNull);
    final d = img.decodeImage(out!)!;
    expect(d.width, lessThan(400)); // 80% crop
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/dart_page_processor_test.dart`
Expected: FAIL — `dart_page_processor.dart` does not exist / `DartPageProcessor` undefined.

- [ ] **Step 3: Create the interface**

Create `lib/features/library/page_processor.dart`:

```dart
import 'dart:typed_data';

import 'crop_corners.dart';
import 'enhancer_mode.dart';

/// Turns a captured JPEG into the stored page bytes: decode → (warp if cropped)
/// → filter(mode) → encode. The single seam for page processing so the native
/// and pure-Dart pipelines are interchangeable and a fallback can wrap them.
abstract interface class PageProcessor {
  /// Returns the processed JPEG, or null when there is nothing to do
  /// (`mode == EnhancerMode.none && corners == CropCorners.fullFrame`) — the
  /// caller then stores the scrubbed input verbatim. Implementations also
  /// return null on failure (corrupt/timeout) so a wrapping fallback can run.
  /// Never throws.
  Future<Uint8List?> process(
      Uint8List bytes, CropCorners corners, EnhancerMode mode);
}
```

- [ ] **Step 4: Implement DartPageProcessor**

Create `lib/features/library/dart_page_processor.dart`:

```dart
import 'dart:typed_data';

import 'auto_enhancer.dart';
import 'color_enhancer.dart';
import 'coons_warper.dart';
import 'crop_corners.dart';
import 'enhancer_mode.dart';
import 'grayscale_enhancer.dart';
import 'hybrid_warper.dart';
import 'image_enhancer.dart';
import 'image_warper.dart';
import 'page_processor.dart';
import 'perspective_warper.dart';
import 'warp_enhancer.dart';

/// The shipped pure-Dart pipeline behind the [PageProcessor] seam. Encapsulates
/// the full-frame enhance and the fused cropped warp+enhance, preserving the
/// existing "real warper → fused, stubbed warper → two-step" behavior so tests
/// that inject a fake warper still exercise it.
class DartPageProcessor implements PageProcessor {
  final ImageWarper warper;
  const DartPageProcessor(this.warper);

  @override
  Future<Uint8List?> process(
      Uint8List bytes, CropCorners corners, EnhancerMode mode) async {
    final isFullFrame = corners == CropCorners.fullFrame;
    if (isFullFrame) {
      if (mode == EnhancerMode.none) return null; // nothing to do
      try {
        return await _enhancerFor(mode).enhance(bytes);
      } catch (_) {
        return null;
      }
    }

    // Cropped: fused fast path for the real warper; two-step for a stubbed one.
    if (warper is HybridWarper ||
        warper is PerspectiveWarper ||
        warper is CoonsWarper) {
      final fused = await warpAndEnhance(bytes, corners, mode);
      if (fused != null) return fused;
      // Warp failed → de-shadow the un-warped frame (never lose the page).
      if (mode == EnhancerMode.none) return null;
      try {
        return await _enhancerFor(mode).enhance(bytes);
      } catch (_) {
        return null;
      }
    }

    Uint8List? warped;
    try {
      warped = await warper.warp(bytes, corners);
    } catch (_) {
      warped = null;
    }
    final base = warped ?? bytes;
    if (mode == EnhancerMode.none) return warped; // null if warp made nothing
    try {
      return await _enhancerFor(mode).enhance(base);
    } catch (_) {
      return base;
    }
  }

  ImageEnhancer _enhancerFor(EnhancerMode mode) => switch (mode) {
        EnhancerMode.auto => const AutoEnhancer(),
        EnhancerMode.color => const ColorEnhancer(),
        EnhancerMode.grayscale => const GrayscaleEnhancer(),
        EnhancerMode.none => const NoneEnhancer(),
      };
}
```

- [ ] **Step 5: Run the tests and make sure they pass**

Run: `cd apps/mobile && flutter test test/features/library/dart_page_processor_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/page_processor.dart apps/mobile/lib/features/library/dart_page_processor.dart apps/mobile/test/features/library/dart_page_processor_test.dart
git commit -m "feat(scan): PageProcessor seam + DartPageProcessor (shipped behavior)"
```

---

## Task 2: FallbackPageProcessor

**Files:**
- Create: `lib/features/library/fallback_page_processor.dart`
- Test: `test/features/library/fallback_page_processor_test.dart`

**Interfaces:**
- Consumes: `PageProcessor`, `CropCorners`, `EnhancerMode`.
- Produces: `class FallbackPageProcessor implements PageProcessor { const FallbackPageProcessor({required PageProcessor primary, required PageProcessor fallback}); }`

- [ ] **Step 1: Write the failing test**

Create `test/features/library/fallback_page_processor_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/fallback_page_processor.dart';
import 'package:mobile/features/library/page_processor.dart';

class _Fake implements PageProcessor {
  _Fake(this._result, {this.throws = false});
  final Uint8List? _result;
  final bool throws;
  int calls = 0;
  @override
  Future<Uint8List?> process(Uint8List b, CropCorners c, EnhancerMode m) async {
    calls++;
    if (throws) throw Exception('boom');
    return _result;
  }
}

final _bytes = Uint8List.fromList([1, 2, 3]);
const _crop = CropCorners(
  topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
  bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9));

void main() {
  test('none + fullFrame short-circuits: neither engine called, returns null', () async {
    final primary = _Fake(Uint8List.fromList([9]));
    final fallback = _Fake(Uint8List.fromList([8]));
    final fp = FallbackPageProcessor(primary: primary, fallback: fallback);
    final out = await fp.process(_bytes, CropCorners.fullFrame, EnhancerMode.none);
    expect(out, isNull);
    expect(primary.calls, 0);
    expect(fallback.calls, 0);
  });

  test('primary succeeds → fallback not called', () async {
    final primary = _Fake(Uint8List.fromList([9]));
    final fallback = _Fake(Uint8List.fromList([8]));
    final fp = FallbackPageProcessor(primary: primary, fallback: fallback);
    final out = await fp.process(_bytes, _crop, EnhancerMode.auto);
    expect(out, [9]);
    expect(fallback.calls, 0);
  });

  test('primary returns null (failure) → fallback runs', () async {
    final primary = _Fake(null);
    final fallback = _Fake(Uint8List.fromList([8]));
    final fp = FallbackPageProcessor(primary: primary, fallback: fallback);
    final out = await fp.process(_bytes, _crop, EnhancerMode.auto);
    expect(out, [8]);
    expect(primary.calls, 1);
    expect(fallback.calls, 1);
  });

  test('primary throws → fallback runs', () async {
    final primary = _Fake(null, throws: true);
    final fallback = _Fake(Uint8List.fromList([8]));
    final fp = FallbackPageProcessor(primary: primary, fallback: fallback);
    final out = await fp.process(_bytes, _crop, EnhancerMode.auto);
    expect(out, [8]);
    expect(fallback.calls, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/fallback_page_processor_test.dart`
Expected: FAIL — `fallback_page_processor.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/features/library/fallback_page_processor.dart`:

```dart
import 'dart:typed_data';

import 'crop_corners.dart';
import 'enhancer_mode.dart';
import 'page_processor.dart';

/// Tries [primary] (native), transparently running [fallback] (Dart) when
/// primary fails. Distinguishes the legitimate "nothing to do" case
/// (none + full frame) — which both engines would answer null for — by
/// short-circuiting it here, so the fallback is never pointlessly invoked and
/// the caller still gets the correct passthrough (null).
class FallbackPageProcessor implements PageProcessor {
  final PageProcessor primary;
  final PageProcessor fallback;
  const FallbackPageProcessor({required this.primary, required this.fallback});

  @override
  Future<Uint8List?> process(
      Uint8List bytes, CropCorners corners, EnhancerMode mode) async {
    if (mode == EnhancerMode.none && corners == CropCorners.fullFrame) {
      return null; // nothing to do — store scrubbed bytes verbatim
    }
    try {
      final out = await primary.process(bytes, corners, mode);
      if (out != null) return out;
    } catch (_) {
      // fall through to fallback
    }
    return fallback.process(bytes, corners, mode);
  }
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `cd apps/mobile && flutter test test/features/library/fallback_page_processor_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/fallback_page_processor.dart apps/mobile/test/features/library/fallback_page_processor_test.dart
git commit -m "feat(scan): FallbackPageProcessor (native→Dart on failure)"
```

---

## Task 3: Route the repository through PageProcessor

**Files:**
- Modify: `lib/features/library/drift/drift_document_repository.dart` (imports; constructor ~L44-53; full-frame enhance ~L83-87 and ~L531-535 and ~L645-649; `_enhancedFlat` ~L135-171)
- Test: `test/features/library/drift_document_repository_test.dart` (add a fake-processor test; existing tests must stay green)

**Interfaces:**
- Consumes: `PageProcessor`, `DartPageProcessor`, `enhancerModeOf` (`warp_enhancer.dart`).
- Produces: repository accepts `PageProcessor? pageProcessor`, defaulting to `DartPageProcessor(warper)`; all three full-frame enhance sites and `_enhancedFlat` delegate to it.

- [ ] **Step 1: Write the failing test**

Add to `test/features/library/drift_document_repository_test.dart` (inside `main`, after the E2 group). This asserts the injected processor is used for the flat:

```dart
  group('E2b — PageProcessor routing', () {
    test('cropped save uses the injected PageProcessor for the flat', () async {
      final fakeFlat = Uint8List.fromList([0xFF, 0xD8, 0x42]);
      final proc = _FakeProcessor(fakeFlat);
      const corners = CropCorners(
        topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9));
      final doc = await repo(pageProcessor: proc)
          .createFromCapture(capture, corners: corners);
      final flat = File('${base.path}/documents/${doc.id}/page_1_flat.jpg');
      expect(flat.existsSync(), isTrue);
      expect(flat.readAsBytesSync(), fakeFlat);
      expect(proc.calls, greaterThanOrEqualTo(1));
    });
  });
```

Add this fake class near the top of the file (after `_ThrowingEnhancer`):

```dart
class _FakeProcessor implements PageProcessor {
  _FakeProcessor(this._flat);
  final Uint8List _flat;
  int calls = 0;
  @override
  Future<Uint8List?> process(Uint8List b, CropCorners c, EnhancerMode m) async {
    calls++;
    return _flat;
  }
}
```

Add imports to the test file:

```dart
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/page_processor.dart';
```

And extend the `repo(...)` helper signature (Step 3 wires it):

```dart
  DriftDocumentRepository repo({
    ImageMetadataScrubber? scrubber,
    ImageWarper? warper,
    PageProcessor? pageProcessor,
  }) =>
      DriftDocumentRepository(
        db: db,
        scrubber: scrubber ?? const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: clock,
        pdfBuilder: const PdfBuilder(),
        warper: warper ?? FakeImageWarper(),
        pageProcessor: pageProcessor,
      );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart`
Expected: FAIL — `DriftDocumentRepository` has no `pageProcessor` param.

- [ ] **Step 3: Add the field + constructor default**

In `drift_document_repository.dart` add imports:

```dart
import '../dart_page_processor.dart';
import '../page_processor.dart';
```

(Keep the existing `coons_warper.dart`, `hybrid_warper.dart`, `perspective_warper.dart`, `warp_enhancer.dart` imports.)

Add the field and constructor param (the ctor currently sets `_warper = warper`):

```dart
  final PageProcessor _processor;
```

In the constructor parameter list add `PageProcessor? pageProcessor,` and in the initializer list set:

```dart
        _warper = warper,
        _processor = pageProcessor ?? DartPageProcessor(warper),
```

- [ ] **Step 4: Route the full-frame enhance sites through the processor**

There are THREE identical full-frame blocks (in `createFromCapture` ~L83, `addPageToDocument` ~L531, `replacePage` ~L645). Replace each occurrence of:

```dart
          if (enhancer != null && isFullFrame) {
            try {
              bytesToStore = await enhancer.enhance(scrubbed);
            } catch (_) {}
          }
```

with:

```dart
          if (enhancer != null && isFullFrame) {
            final enhanced = await _processor.process(
                scrubbed, CropCorners.fullFrame, enhancerModeOf(enhancer));
            if (enhanced != null) bytesToStore = enhanced;
          }
```

(`_processor.process` never throws; a null means none-mode or failure, in which case the scrubbed bytes stand — same effect as the old silent catch.)

- [ ] **Step 5: Route `_enhancedFlat` through the processor**

Replace the entire body of `_enhancedFlat` (the method added in the fusion commit, ~L135-171) with:

```dart
  Future<Uint8List?> _enhancedFlat(
      Uint8List scrubbed, CropCorners? corners, ImageEnhancer? enhancer) async {
    if (corners == null || corners == CropCorners.fullFrame) return null;
    final out =
        await _processor.process(scrubbed, corners, enhancerModeOf(enhancer));
    if (out != null) return out;
    // Both native and Dart failed → last-ditch: de-shadow the un-warped frame
    // so a failed crop still yields a clean page rather than the raw capture.
    if (enhancer == null) return scrubbed;
    try {
      return await enhancer.enhance(scrubbed);
    } catch (_) {
      return scrubbed;
    }
  }
```

Note: the previous `_warper`-type-dispatch and two-step logic now lives inside `DartPageProcessor`; the default `_processor` (`DartPageProcessor(_warper)`) preserves the exact prior behavior, so the FakeImageWarper tests still pass.

- [ ] **Step 6: Run the full library suite**

Run: `cd apps/mobile && flutter test test/features/library/`
Expected: PASS — all existing repository/warp tests green, plus the new E2b test.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/drift/drift_document_repository.dart apps/mobile/test/features/library/drift_document_repository_test.dart
git commit -m "refactor(scan): route repository save path through PageProcessor"
```

---

## Task 4: NativePageProcessor — decode → warp → encode skeleton

**Files:**
- Modify: `lib/features/library/auto_enhancer.dart` (make tuning constants public)
- Create: `lib/features/library/native_page_processor.dart`
- Test: `integration_test/np1_native_pipeline_test.dart` (device only)

**Interfaces:**
- Consumes: `cv` (`package:opencv_dart/opencv_dart.dart`), `CropCorners`, `EnhancerMode`, `PageProcessor`, `kDefaultFlatMaxDimension` (`perspective_warper.dart`).
- Produces: `class NativePageProcessor implements PageProcessor { const NativePageProcessor({Duration timeout = const Duration(seconds: 5)}); }`. This task handles `EnhancerMode.none` (warp+encode, no filter) and returns null for bent crops / corrupt input / timeout. Later tasks add Auto/Color/Grayscale.

- [ ] **Step 1: Make the Auto constants public (for reuse in the native pipeline)**

In `lib/features/library/auto_enhancer.dart` rename the six private constants to public (used in Task 5). Update their references within the file:

```dart
const int kAutoProxyLongSide = 512;   // was _kProxyLongSide
const int kAutoDilateRadius = 7;      // was _kDilateRadius
const int kAutoBlurRadius = 12;       // was _kBlurRadius
const double kAutoWhiteClip = 0.01;   // was _kWhiteClip
const double kAutoBlackAnchor = 0.55; // was _kBlackAnchor
const double kAutoMaxGain = 6.0;      // was _kMaxGain
```

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart`
Expected: PASS (unchanged behavior — pure rename).

Commit this rename on its own:

```bash
git add apps/mobile/lib/features/library/auto_enhancer.dart
git commit -m "refactor(scan): expose Auto tuning constants for native reuse"
```

- [ ] **Step 2: Write the failing device test**

Create `integration_test/np1_native_pipeline_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/native_page_processor.dart';

Uint8List _cap(int w, int h) {
  final p = img.Image(width: w, height: h, numChannels: 3);
  img.fill(p, color: img.ColorRgb8(70, 70, 70));
  img.fillRect(p, x1: (w * .08).round(), y1: (h * .10).round(),
      x2: (w * .92).round(), y2: (h * .90).round(),
      color: img.ColorRgb8(220, 218, 210));
  return Uint8List.fromList(img.encodeJpg(p, quality: 92));
}

const _straight = CropCorners(
  topLeft: Offset(0.08, 0.10), topRight: Offset(0.92, 0.10),
  bottomRight: Offset(0.92, 0.90), bottomLeft: Offset(0.08, 0.90));
const _bent = CropCorners(
  topLeft: Offset(0.08, 0.10), topRight: Offset(0.92, 0.10),
  bottomRight: Offset(0.92, 0.90), bottomLeft: Offset(0.08, 0.90),
  topMidDev: Offset(0, -0.05));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const p = NativePageProcessor();

  test('none + straight crop → warped JPEG, long side ≤ 3500, fast', () async {
    final s = Stopwatch()..start();
    final out = await p.process(_cap(6000, 4500), _straight, EnhancerMode.none);
    print('NP1 none/straight: ${s.elapsedMilliseconds}ms');
    expect(out, isNotNull);
    final d = img.decodeImage(out!)!;
    expect(d.width <= 3500 && d.height <= 3500, isTrue);
    expect(d.width, greaterThan(2));
  });

  test('bent crop → null (defers to Dart Coons)', () async {
    final out = await p.process(_cap(1200, 900), _bent, EnhancerMode.none);
    expect(out, isNull);
  });

  test('corrupt bytes → null (defers to fallback)', () async {
    final out = await p.process(
        Uint8List.fromList([0xFF, 0xD8, 0x00, 0x01]), _straight, EnhancerMode.none);
    expect(out, isNull);
  });
}
```

- [ ] **Step 3: Run the device test to verify it fails**

Run: `cd apps/mobile && flutter test integration_test/np1_native_pipeline_test.dart -d RZCY51D0T1K`
Expected: FAIL — `native_page_processor.dart` does not exist.

- [ ] **Step 4: Implement the skeleton (warp + encode, mode-dispatch stub)**

Create `lib/features/library/native_page_processor.dart`:

```dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'crop_corners.dart';
import 'enhancer_mode.dart';
import 'page_processor.dart';
import 'perspective_warper.dart' show kDefaultFlatMaxDimension;

/// Native OpenCV (dartcv) page pipeline: imdecode → warpPerspective (straight
/// crops; capped ≤3500) → filter(mode) → imencode. Runs in a [compute] isolate
/// wrapped with a timeout — a wedged native isolate cannot be killed from Dart,
/// so the timeout is the recovery. Returns null for anything it does not handle
/// (bent crop, corrupt input, failure, timeout) so a fallback can take over.
class NativePageProcessor implements PageProcessor {
  final Duration timeout;
  const NativePageProcessor({this.timeout = const Duration(seconds: 5)});

  @override
  Future<Uint8List?> process(
      Uint8List bytes, CropCorners corners, EnhancerMode mode) async {
    if (mode == EnhancerMode.none && corners == CropCorners.fullFrame) {
      return null; // nothing to do
    }
    if (corners != CropCorners.fullFrame && !corners.isStraight) {
      return null; // bent crop → defer to Dart Coons
    }
    try {
      return await compute(_nativeFn, _NativeArgs(bytes, corners, mode))
          .timeout(timeout);
    } catch (_) {
      return null; // TimeoutException or isolate error → fallback
    }
  }
}

class _NativeArgs {
  final Uint8List bytes;
  final CropCorners corners;
  final EnhancerMode mode;
  const _NativeArgs(this.bytes, this.corners, this.mode);
}

Uint8List? _nativeFn(_NativeArgs a) {
  cv.Mat? src, warped;
  try {
    src = cv.imdecode(a.bytes, cv.IMREAD_COLOR);
    if (src.isEmpty) return null;

    // Warp straight crops; full frame passes through unwarped.
    if (a.corners == CropCorners.fullFrame) {
      warped = src.clone();
    } else {
      warped = _warpStraight(src, a.corners);
    }

    // Filter dispatch (Auto/Color/Grayscale added in later tasks).
    final quality = a.mode == EnhancerMode.auto ? 95 : 92;
    final (ok, out) = cv.imencode('.jpg', warped,
        params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]));
    return ok ? out : null;
  } catch (_) {
    return null;
  } finally {
    src?.dispose();
    warped?.dispose();
  }
}

/// Perspective-flatten a straight crop, output size = the longer of each pair
/// of opposite edges (same rule as the Dart warper), capped to
/// [kDefaultFlatMaxDimension].
cv.Mat _warpStraight(cv.Mat src, CropCorners c) {
  final w = src.cols, h = src.rows;
  double dist(Offset a, Offset b) {
    final dx = (a.dx - b.dx) * w, dy = (a.dy - b.dy) * h;
    return math.sqrt(dx * dx + dy * dy);
  }
  final topE = dist(c.topLeft, c.topRight);
  final botE = dist(c.bottomLeft, c.bottomRight);
  final leftE = dist(c.topLeft, c.bottomLeft);
  final rightE = dist(c.topRight, c.bottomRight);
  var pxW = (topE > botE ? topE : botE).round();
  var pxH = (leftE > rightE ? leftE : rightE).round();
  if (pxW < 2) pxW = 2;
  if (pxH < 2) pxH = 2;
  final longest = pxW > pxH ? pxW : pxH;
  if (longest > kDefaultFlatMaxDimension) {
    final s = kDefaultFlatMaxDimension / longest;
    pxW = (pxW * s).round();
    if (pxW < 2) pxW = 2;
    pxH = (pxH * s).round();
    if (pxH < 2) pxH = 2;
  }

  final srcQuad = cv.VecPoint2f.fromList([
    cv.Point2f(c.topLeft.dx * w, c.topLeft.dy * h),
    cv.Point2f(c.topRight.dx * w, c.topRight.dy * h),
    cv.Point2f(c.bottomRight.dx * w, c.bottomRight.dy * h),
    cv.Point2f(c.bottomLeft.dx * w, c.bottomLeft.dy * h),
  ]);
  final dstQuad = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(pxW.toDouble(), 0),
    cv.Point2f(pxW.toDouble(), pxH.toDouble()),
    cv.Point2f(0, pxH.toDouble()),
  ]);
  cv.Mat? m;
  try {
    m = cv.getPerspectiveTransform2f(srcQuad, dstQuad);
    return cv.warpPerspective(src, m, (pxW, pxH), flags: cv.INTER_LINEAR);
  } finally {
    srcQuad.dispose();
    dstQuad.dispose();
    m?.dispose();
  }
}
```

- [ ] **Step 5: Run the device test to verify it passes**

Run: `cd apps/mobile && flutter test integration_test/np1_native_pipeline_test.dart -d RZCY51D0T1K`
Expected: PASS (3 tests). Note the printed `NP1 none/straight` time (should be well under 1 s).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/native_page_processor.dart apps/mobile/integration_test/np1_native_pipeline_test.dart
git commit -m "feat(scan): NativePageProcessor decode+warp+encode skeleton"
```

---

## Task 5: Native Auto flat-field filter

**Files:**
- Modify: `lib/features/library/native_page_processor.dart` (add `_autoFlatField`, dispatch `EnhancerMode.auto`)
- Test: `integration_test/np2_native_auto_parity_test.dart` (device only)

**Interfaces:**
- Consumes: `kAutoProxyLongSide`, `kAutoDilateRadius`, `kAutoBlurRadius`, `kAutoWhiteClip`, `kAutoBlackAnchor`, `kAutoMaxGain` (from `auto_enhancer.dart`), and `autoEnhanceOriented` (Dart reference, for the parity comparison in the test).
- Produces: native Auto output that matches `AutoEnhancer` within tolerance.

- [ ] **Step 1: Write the failing device parity test**

Create `integration_test/np2_native_auto_parity_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/painting.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/auto_enhancer.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/native_page_processor.dart';

Uint8List _doc(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final shade = 1.0 - 0.4 * (x + y) / (w + h);
      var r = (235 * shade).round(), g = (225 * shade).round(), b = (205 * shade).round();
      if (x > w ~/ 8 && x < 7 * w ~/ 8 && (y % 40) < 16 && y > h ~/ 8 && y < 7 * h ~/ 8) {
        r = 35; g = 33; b = 30;
      }
      im.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const p = NativePageProcessor();

  test('native Auto ≈ Dart Auto (full frame)', () async {
    final bytes = _doc(1600, 1200);
    final nativeOut = await p.process(bytes, CropCorners.fullFrame, EnhancerMode.auto);
    expect(nativeOut, isNotNull);

    // Dart reference (bake + autoEnhanceOriented, then encode q95).
    final baked = img.bakeOrientation(img.decodeImage(bytes)!);
    final dartImg = autoEnhanceOriented(baked);
    final nImg = img.decodeImage(nativeOut!)!;
    expect(nImg.width, dartImg.width);
    expect(nImg.height, dartImg.height);

    final nb = nImg.getBytes(order: img.ChannelOrder.rgb);
    final db = dartImg.getBytes(order: img.ChannelOrder.rgb);
    var sum = 0, maxd = 0;
    for (var i = 0; i < nb.length; i++) {
      final d = (nb[i] - db[i]).abs();
      sum += d;
      if (d > maxd) maxd = d;
    }
    final mean = sum / nb.length;
    print('NP2 native-vs-dart Auto: mean=${mean.toStringAsFixed(3)} max=$maxd');
    expect(mean, lessThan(2.0), reason: 'quality parity gate');
  });
}
```

- [ ] **Step 2: Run the device test to verify it fails**

Run: `cd apps/mobile && flutter test integration_test/np2_native_auto_parity_test.dart -d RZCY51D0T1K`
Expected: FAIL — Auto not yet implemented; native returns the un-enhanced warped/cloned image, so `mean` is large.

- [ ] **Step 3: Implement `_autoFlatField` and dispatch it**

In `native_page_processor.dart`, add the import:

```dart
import 'auto_enhancer.dart'
    show
        kAutoProxyLongSide,
        kAutoDilateRadius,
        kAutoBlurRadius,
        kAutoWhiteClip,
        kAutoBlackAnchor,
        kAutoMaxGain;
```

In `_nativeFn`, replace the direct `imencode(... warped ...)` with a filtered Mat:

```dart
    cv.Mat? filtered;
    try {
      filtered = switch (a.mode) {
        EnhancerMode.auto => _autoFlatField(warped),
        _ => warped.clone(), // Color/Grayscale added in Task 6; none = passthrough
      };
      final quality = a.mode == EnhancerMode.auto ? 95 : 92;
      final (ok, out) = cv.imencode('.jpg', filtered,
          params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]));
      return ok ? out : null;
    } finally {
      filtered?.dispose();
    }
```

Add the flat-field function (mirrors `auto_enhancer.dart` exactly; operates on BGR — per-channel ops are channel-order-independent):

```dart
/// Per-channel flat-field + white-point finish — the native mirror of
/// auto_enhancer.dart's autoEnhanceOriented, using the same constants.
cv.Mat _autoFlatField(cv.Mat src) {
  final rows = src.rows, cols = src.cols;
  cv.Mat? proxy, kernel, dilated, blurred, bg, bgFloored, srcF, bgF, flatF,
      flat, lut;
  try {
    // 1. Background estimate on a small proxy: resize → dilate(15×15) → blur.
    final longest = cols > rows ? cols : rows;
    final scale = longest > kAutoProxyLongSide ? kAutoProxyLongSide / longest : 1.0;
    final pw = (cols * scale).round().clamp(1, cols);
    final ph = (rows * scale).round().clamp(1, rows);
    proxy = cv.resize(src, (pw, ph), interpolation: cv.INTER_AREA);
    final k = 2 * kAutoDilateRadius + 1; // 15
    kernel = cv.getStructuringElement(cv.MORPH_RECT, (k, k));
    dilated = cv.dilate(proxy, kernel);
    // Gaussian sigma matched to the Dart radius; kernel auto-sized from sigma.
    blurred = cv.gaussianBlur(dilated, (0, 0), kAutoBlurRadius.toDouble());
    bg = cv.resize(blurred, (cols, rows), interpolation: cv.INTER_LINEAR);

    // 2. Flatten: px * min(255/bg, maxGain) == px*255 / max(bg, 255/maxGain).
    final floorVal = 255.0 / kAutoMaxGain; // 42.5
    bgF = bg.convertTo(cv.MatType.CV_32FC3);
    bgFloored = cv.max(
        bgF, cv.Mat.fromScalar(rows, cols, cv.MatType.CV_32FC3, cv.Scalar.all(floorVal)));
    srcF = src.convertTo(cv.MatType.CV_32FC3);
    flatF = cv.divide(srcF, bgFloored, scale: 255); // srcF*255/bgFloored
    flat = flatF.convertTo(cv.MatType.CV_8UC3); // saturates to [0,255]

    // 3. White-point stretch via a per-channel 3-channel LUT built in Dart.
    lut = _whitePointLut3(flat);
    return cv.LUT(flat, lut);
  } finally {
    for (final m in [proxy, kernel, dilated, blurred, bg, bgFloored, srcF, bgF,
        flatF, flat, lut]) {
      m?.dispose();
    }
  }
}

/// Builds a 1×256 CV_8UC3 LUT reproducing auto_enhancer.dart's per-channel
/// white-point stretch (1% clip, black anchor 0.55, linear). Histograms are
/// computed from the flattened Mat's raw BGR bytes.
cv.Mat _whitePointLut3(cv.Mat flat) {
  final data = flat.data; // interleaved BGR, length rows*cols*3
  final n = flat.rows * flat.cols;
  final hist = [
    List<int>.filled(256, 0),
    List<int>.filled(256, 0),
    List<int>.filled(256, 0),
  ];
  for (var i = 0; i < data.length; i += 3) {
    hist[0][data[i]]++;
    hist[1][data[i + 1]]++;
    hist[2][data[i + 2]]++;
  }
  final clip = (n * kAutoWhiteClip).ceil().clamp(1, n);
  // Flat 768-length list: [b0,g0,r0, b1,g1,r1, ...] to match BGR channel order.
  final lut = List<int>.filled(256 * 3, 0);
  for (var v = 0; v < 256; v++) {
    lut[v * 3] = v;
    lut[v * 3 + 1] = v;
    lut[v * 3 + 2] = v;
  }
  for (var ch = 0; ch < 3; ch++) {
    final hc = hist[ch];
    int hi = 255, cum = 0;
    while (hi > 0 && cum + hc[hi] < clip) {
      cum += hc[hi--];
    }
    if (hi <= 0) continue;
    final anchor = (hi * kAutoBlackAnchor).round();
    if (hi <= anchor) continue;
    final span = hi - anchor;
    for (var v = anchor + 1; v < 256; v++) {
      lut[v * 3 + ch] = (anchor + (v - anchor) * 255 ~/ span).clamp(0, 255);
    }
  }
  return cv.Mat.fromList(1, 256, cv.MatType.CV_8UC3, lut);
}
```

- [ ] **Step 4: Run the device parity test to verify it passes**

Run: `cd apps/mobile && flutter test integration_test/np2_native_auto_parity_test.dart -d RZCY51D0T1K`
Expected: PASS — printed `mean` well under 2.0. If `mean` is high, the most likely cause is the Gaussian sigma↔radius mapping; adjust the `gaussianBlur` sigma so the background estimate matches (the parity number is the guide).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/native_page_processor.dart apps/mobile/integration_test/np2_native_auto_parity_test.dart
git commit -m "feat(scan): native Auto flat-field, parity-gated vs Dart"
```

---

## Task 6: Native Color + Grayscale filters

**Files:**
- Modify: `lib/features/library/native_page_processor.dart` (dispatch color/grayscale)
- Test: `integration_test/np3_native_color_gray_test.dart` (device only)

**Interfaces:**
- Consumes: `cv.cvtColor`, `cv.LUT`, `cv.Mat.fromList`.
- Produces: native Color/Grayscale outputs, visually sane (decodable, right dimensions, grayscale actually gray).

- [ ] **Step 1: Write the failing device test**

Create `integration_test/np3_native_color_gray_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/native_page_processor.dart';

Uint8List _color(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  img.fill(im, color: img.ColorRgb8(200, 120, 60)); // clearly non-gray
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const p = NativePageProcessor();

  test('grayscale: output R==G==B', () async {
    final out = await p.process(_color(300, 200), CropCorners.fullFrame, EnhancerMode.grayscale);
    expect(out, isNotNull);
    final d = img.decodeImage(out!)!;
    final px = d.getPixel(150, 100);
    expect((px.r - px.g).abs() <= 2 && (px.g - px.b).abs() <= 2, isTrue);
  });

  test('color: stays colored (R != B), decodable, same size', () async {
    final out = await p.process(_color(300, 200), CropCorners.fullFrame, EnhancerMode.color);
    expect(out, isNotNull);
    final d = img.decodeImage(out!)!;
    expect(d.width, 300);
    final px = d.getPixel(150, 100);
    expect((px.r - px.b).abs() > 20, isTrue);
  });
}
```

- [ ] **Step 2: Run the device test to verify it fails**

Run: `cd apps/mobile && flutter test integration_test/np3_native_color_gray_test.dart -d RZCY51D0T1K`
Expected: FAIL — grayscale returns the color passthrough (R≠G≠B).

- [ ] **Step 3: Implement color + grayscale dispatch**

In `native_page_processor.dart`, extend the `switch (a.mode)`:

```dart
      filtered = switch (a.mode) {
        EnhancerMode.auto => _autoFlatField(warped),
        EnhancerMode.color => _colorBoost(warped),
        EnhancerMode.grayscale => _grayscale(warped),
        EnhancerMode.none => warped.clone(),
      };
```

Add:

```dart
/// Contrast 1.1 + brightness 1.05 via a LUT (mirrors ColorEnhancer's intent):
/// v' = clamp((v-128)*1.1 + 128, then *1.05). Applied to all 3 channels.
cv.Mat _colorBoost(cv.Mat src) {
  final lut = List<int>.filled(256, 0);
  for (var v = 0; v < 256; v++) {
    final c = (v - 128) * 1.1 + 128;
    lut[v] = (c * 1.05).round().clamp(0, 255);
  }
  cv.Mat? lutMat;
  try {
    lutMat = cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, lut);
    return cv.LUT(src, lutMat); // 1-ch LUT applies to every channel
  } finally {
    lutMat?.dispose();
  }
}

/// Luminance grayscale, re-expanded to 3 channels for a normal JPEG.
cv.Mat _grayscale(cv.Mat src) {
  cv.Mat? gray;
  try {
    gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
    return cv.cvtColor(gray, cv.COLOR_GRAY2BGR);
  } finally {
    gray?.dispose();
  }
}
```

- [ ] **Step 4: Run the device test to verify it passes**

Run: `cd apps/mobile && flutter test integration_test/np3_native_color_gray_test.dart -d RZCY51D0T1K`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/native_page_processor.dart apps/mobile/integration_test/np3_native_color_gray_test.dart
git commit -m "feat(scan): native Color + Grayscale filters"
```

---

## Task 7: Production wiring + on-device end-to-end verification

**Files:**
- Modify: `lib/features/library/library_dependencies.dart` (inject `FallbackPageProcessor`)
- Test: manual on-device build/install + the existing device tests

**Interfaces:**
- Consumes: `FallbackPageProcessor`, `NativePageProcessor`, `DartPageProcessor`, `HybridWarper`.
- Produces: production repository backed by native-with-Dart-fallback.

- [ ] **Step 1: Wire production DI**

In `lib/features/library/library_dependencies.dart`, where the repository is constructed with `warper: const HybridWarper()` (~L44), add:

```dart
      warper: const HybridWarper(),
      pageProcessor: const FallbackPageProcessor(
        primary: NativePageProcessor(),
        fallback: DartPageProcessor(HybridWarper()),
      ),
```

Add imports at the top of the file:

```dart
import 'dart_page_processor.dart';
import 'fallback_page_processor.dart';
import 'native_page_processor.dart';
```

(`hybrid_warper.dart` is presumably already imported; add it if not.)

- [ ] **Step 2: Analyze + run the full host suite**

Run: `cd apps/mobile && dart analyze lib && flutter test`
Expected: `No issues found!` and all host tests pass (the native processor isn't loaded on host; only the Dart path and wiring are exercised).

- [ ] **Step 3: Run all native device tests together**

Run: `cd apps/mobile && flutter test integration_test/np1_native_pipeline_test.dart integration_test/np2_native_auto_parity_test.dart integration_test/np3_native_color_gray_test.dart -d RZCY51D0T1K`
Expected: PASS — note the NP1/NP2 timings (sub-second).

- [ ] **Step 4: Build + install release and eyeball**

```bash
cd apps/mobile
flutter build apk --release
flutter install -d RZCY51D0T1K --use-application-binary build/app/outputs/flutter-apk/app-release.apk
```

On device: capture a real page, adjust edges, press OK with the Auto filter.
Expected: sub-second spinner; the saved page looks identical to the previous (Dart) Auto output — no color shift, shadows removed, text crisp. Re-crop an existing page still works (uses the full-res original).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/library_dependencies.dart
git commit -m "feat(scan): wire native-first page pipeline in production DI"
```

---

## Notes for the executor

- The three `integration_test/np*` files are permanent regression tests (not throwaways) — they are the only coverage of the native path. Keep them.
- If the NP2 parity `mean` exceeds 2.0, the Gaussian sigma↔radius mapping is the first knob (Dart uses `img.gaussianBlur(radius: 12)`; native uses `gaussianBlur((0,0), sigma)`), then confirm the `_isqrt` output-size rounding matches the Dart `_maxEdge().round()`.
- Do NOT change camera resolution, detector, crop UI, or DB schema (out of scope).
- Background/non-blocking processing is sub-project 2 — a separate spec after this ships.
