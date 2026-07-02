# Auto Filter Region-Level Photo Protection (multi-cue) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Auto` preserve whole photo regions (bright, dark, colorful, or textured) by detecting them with multiple content cues, while paper/text shadow removal is unchanged.

**Architecture:** On the existing 48px proxy, compute a per-pixel photo seed from chroma + local texture + darkness cues, clean it with morphological opening (kill text speckle) then closing + fill-holes (consolidate region + absorb enclosed smooth areas), feather, upscale, and thread it into `_divideByBackground` as the correction alpha. Pure-Dart, one `compute` isolate, only `auto_enhancer.dart` changes.

**Tech Stack:** Dart, Flutter, `image` 4.3.0, `compute` isolates, `@visibleForTesting`, `bdd_widget_test` + `build_runner`.

## Global Constraints

- `ImageEnhancer.enhance` NEVER throws — returns input bytes on any failure (existing try/catch stays).
- Pure-Dart only; no opencv_dart; identical result iOS/Android.
- No bare magic numbers — the 5 new consts named + documented.
- `AutoEnhancer` stays `const` + `implements ImageEnhancer`; JPEG quality 92.
- Bias: **favor text de-shadowing** — when detection is uncertain, treat as paper and de-shadow. Only clearly-photo regions are preserved.
- Preserve-as-captured: a detected photo region is left untouched (alpha 0).
- Do NOT change `_autoLevels`, `correctionWeight`'s signature, `_maxFilter`, the consts `_kPaperFloor`/`_kGateBand`, other enhancers, or enhancer_mode/filter_picker_strip/capture_review_screen.

---

## File Structure

- **Modify:** `apps/mobile/lib/features/library/auto_enhancer.dart` — add `localStdDev`, `fillHoles` (`@visibleForTesting`), `_minFilter`, `buildCorrectionMask` (`@visibleForTesting`), 5 consts; split the background step into `_downscaleProxy` + `_backgroundFromProxy`; thread `alphaMap` into `_divideByBackground`; update `_autoFn`.
- **Modify:** `apps/mobile/test/features/library/auto_color_enhancer_test.dart`.
- **Modify:** `apps/mobile/test/step/the_auto_enhancer_preserves_the_photo.dart` + regenerate `apps/mobile/integration_test/g3_auto_color_test.dart`.

Anchors (current merged file): the `correctionWeight` function, the `_maxFilter` function, `_estimateBackground`, `_autoFn`, `_divideByBackground`. Tasks reference these by name, not line number.

---

## Task 1: Mask primitives — `localStdDev` + `fillHoles`

Two small pure utilities the mask builder needs, each unit-tested directly. Public (`@visibleForTesting`) so they can be tested and referenced ahead of the mask builder without an `unused_element` warning.

**Files:**
- Modify: `apps/mobile/lib/features/library/auto_enhancer.dart`
- Test: `apps/mobile/test/features/library/auto_color_enhancer_test.dart`

**Interfaces:**
- Consumes: `img.Image`, `Pixel.luminance`, `.r`, `setPixelRgb`, `clone`, `dart:math`.
- Produces:
  - `@visibleForTesting double localStdDev(img.Image src, int x, int y)` — std-dev of luminance over the 3×3 window around (x,y), edges clamped.
  - `@visibleForTesting img.Image fillHoles(img.Image mask)` — grayscale mask where foreground = value > 127. Flood-fills background from the border; background pixels not reachable from the border are enclosed holes and become foreground (255). Returns a new image.

- [ ] **Step 1: Write the failing tests**

Add at top level in `apps/mobile/test/features/library/auto_color_enhancer_test.dart` (the file already imports `package:image/image.dart as img` and the enhancer):

```dart
  group('localStdDev', () {
    test('is 0 on a uniform region', () {
      final im = img.Image(width: 5, height: 5);
      for (final px in im) { px..r = 120..g = 120..b = 120; }
      expect(localStdDev(im, 2, 2), lessThan(0.5));
    });
    test('is high on a varied region', () {
      final im = img.Image(width: 5, height: 5);
      var i = 0;
      for (final px in im) { final v = (i++ % 2 == 0) ? 20 : 220; px..r = v..g = v..b = v; }
      expect(localStdDev(im, 2, 2), greaterThan(50));
    });
  });

  group('fillHoles', () {
    test('fills a background hole fully enclosed by foreground', () {
      // 7x7: foreground ring (255) with a single-pixel background hole at centre.
      final m = img.Image(width: 7, height: 7);
      for (final px in m) { px..r = 0..g = 0..b = 0; }
      for (var y = 2; y <= 4; y++) {
        for (var x = 2; x <= 4; x++) { m.getPixel(x, y)..r = 255..g = 255..b = 255; }
      }
      m.getPixel(3, 3)..r = 0..g = 0..b = 0; // the enclosed hole

      final filled = fillHoles(m);

      expect(filled.getPixel(3, 3).r, 255, reason: 'enclosed hole becomes foreground');
      expect(filled.getPixel(0, 0).r, 0, reason: 'border background stays background');
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name localStdDev`
Expected: FAIL — `localStdDev` undefined.

- [ ] **Step 3: Implement the two helpers**

In `apps/mobile/lib/features/library/auto_enhancer.dart`, add these two functions immediately AFTER the existing `correctionWeight` function:

```dart

/// Standard deviation of luminance over the 3x3 window around ([x], [y])
/// (edges clamped). A texture cue: flat paper ~0, continuous-tone photo detail
/// is high. Exposed for tests.
@visibleForTesting
double localStdDev(img.Image src, int x, int y) {
  var sum = 0.0, sumSq = 0.0, n = 0.0;
  for (var dy = -1; dy <= 1; dy++) {
    final yy = (y + dy).clamp(0, src.height - 1);
    for (var dx = -1; dx <= 1; dx++) {
      final xx = (x + dx).clamp(0, src.width - 1);
      final l = src.getPixel(xx, yy).luminance.toDouble();
      sum += l;
      sumSq += l * l;
      n += 1;
    }
  }
  final mean = sum / n;
  final variance = (sumSq / n) - mean * mean;
  return variance <= 0 ? 0 : math.sqrt(variance);
}

/// Marks enclosed background holes as foreground. Foreground = channel > 127.
/// Flood-fills background reachable from the border; any background pixel NOT
/// reached is enclosed (a hole) and is set to foreground (255). Absorbs a
/// smooth/bright sub-area enclosed by detected photo content into the region.
/// Exposed for tests.
@visibleForTesting
img.Image fillHoles(img.Image mask) {
  final w = mask.width, h = mask.height;
  final reachable = List.generate(h, (_) => List<bool>.filled(w, false));
  final stack = <int>[]; // packed y*w + x
  void tryPush(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    if (reachable[y][x]) return;
    if (mask.getPixel(x, y).r.toInt() > 127) return; // foreground blocks fill
    reachable[y][x] = true;
    stack.add(y * w + x);
  }
  for (var x = 0; x < w; x++) { tryPush(x, 0); tryPush(x, h - 1); }
  for (var y = 0; y < h; y++) { tryPush(0, y); tryPush(w - 1, y); }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % w, y = p ~/ w;
    tryPush(x + 1, y);
    tryPush(x - 1, y);
    tryPush(x, y + 1);
    tryPush(x, y - 1);
  }
  final out = mask.clone();
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mask.getPixel(x, y).r.toInt() <= 127 && !reachable[y][x]) {
        out.setPixelRgb(x, y, 255, 255, 255);
      }
    }
  }
  return out;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name localStdDev` → PASS
Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name fillHoles` → PASS

- [ ] **Step 5: Full-file regression + commit**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart`
Expected: PASS — nothing wired into the pipeline yet, existing tests untouched.

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/lib/features/library/auto_enhancer.dart apps/mobile/test/features/library/auto_color_enhancer_test.dart
git commit -m "feat(auto): add mask primitives localStdDev + fillHoles

Texture cue (3x3 luminance std-dev) and enclosed-hole fill for the
upcoming multi-cue photo-region mask. Not yet wired.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `buildCorrectionMask` (multi-cue seed → clean region mask)

**Files:**
- Modify: `apps/mobile/lib/features/library/auto_enhancer.dart`
- Test: `apps/mobile/test/features/library/auto_color_enhancer_test.dart`

**Interfaces:**
- Consumes: `localStdDev`, `fillHoles` (Task 1), `correctionWeight`, `_maxFilter` (existing), `img.gaussianBlur`, `dart:math`.
- Produces:
  - `_minFilter(img.Image src, int radius) → img.Image` — grayscale erosion (min over (2r+1)²).
  - `@visibleForTesting img.Image buildCorrectionMask(img.Image colorProxy)` — grayscale mask at proxy resolution: channel = alpha*255, where alpha=0 over detected photo regions and 255 over paper. Consumed by Task 3.

- [ ] **Step 1: Write the failing mask tests**

Add at top level in `auto_color_enhancer_test.dart`:

```dart
  group('buildCorrectionMask', () {
    test('colorful patch on neutral paper is detected as photo (alpha ~0)', () {
      final proxy = img.Image(width: 30, height: 30);
      for (final px in proxy) { px..r = 235..g = 233..b = 230; } // neutral paper
      for (var y = 8; y < 22; y++) {
        for (var x = 8; x < 22; x++) { proxy.getPixel(x, y)..r = 200..g = 40..b = 40; } // saturated red
      }
      final mask = buildCorrectionMask(proxy);
      expect(mask.getPixel(15, 15).r, lessThan(80), reason: 'colorful region → preserved');
      expect(mask.getPixel(1, 1).r, greaterThan(200), reason: 'paper → full correction');
    });

    test('sparse thin dark strokes (text) are NOT detected as photo (bias)', () {
      final proxy = img.Image(width: 30, height: 30);
      for (final px in proxy) { px..r = 232..g = 232..b = 232; } // bright neutral paper
      // isolated single-pixel dark "strokes" scattered — thin, sparse.
      for (final p in [[5,5],[9,5],[13,5],[5,9],[9,9],[20,20],[24,20]]) {
        proxy.getPixel(p[0], p[1])..r = 35..g = 35..b = 35;
      }
      final mask = buildCorrectionMask(proxy);
      // After opening, isolated speckles are erased → paper weight everywhere.
      expect(mask.getPixel(9, 5).r, greaterThan(180),
          reason: 'thin text must remain paper so it still gets de-shadowed');
      expect(mask.getPixel(1, 1).r, greaterThan(200));
    });

    test('bright patch enclosed by a dark photo body is absorbed (alpha ~0)', () {
      final proxy = img.Image(width: 30, height: 30);
      for (final px in proxy) { px..r = 235..g = 235..b = 235; }
      for (var y = 6; y < 24; y++) {
        for (var x = 6; x < 24; x++) { proxy.getPixel(x, y)..r = 40..g = 40..b = 40; } // dark body
      }
      for (var y = 12; y < 18; y++) {
        for (var x = 12; x < 18; x++) { proxy.getPixel(x, y)..r = 200..g = 200..b = 200; } // bright hole
      }
      final mask = buildCorrectionMask(proxy);
      expect(mask.getPixel(15, 15).r, lessThan(80),
          reason: 'bright area enclosed by the photo must be preserved too');
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name buildCorrectionMask`
Expected: FAIL — `buildCorrectionMask` undefined.

- [ ] **Step 3: Add the 5 consts, `_minFilter`, and `buildCorrectionMask`**

3a. Add the consts immediately after the existing `_kGateBand` const:
```dart

/// Min chroma (0-255) for a proxy pixel to seed as photo (color cue).
const int _kChromaThresh = 25;

/// Min local luminance std-dev for a proxy pixel to seed as photo (texture cue).
const int _kTextureThresh = 18;

/// Opening radius (proxy px) that removes thin/sparse text-edge speckle from the
/// photo seed — enforces the "favor text de-shadowing" bias.
const int _kSpeckleRadius = 1;

/// Closing radius (proxy px) that merges surviving seed into a solid region.
const int _kConsolidateRadius = 2;

/// Feather radius on the final mask — softens edges so there is no seam.
const int _kMaskFeather = 2;
```

3b. Add `_minFilter` immediately AFTER the existing `_maxFilter` function:
```dart

/// Grayscale morphological erosion: each pixel becomes the min luminance in a
/// (2r+1)^2 window. Input is grayscale (r == g == b), so we read/write r.
img.Image _minFilter(img.Image src, int radius) {
  if (radius <= 0) return src;
  final out = src.clone();
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      var mn = 255;
      for (var dy = -radius; dy <= radius; dy++) {
        final yy = (y + dy).clamp(0, src.height - 1);
        for (var dx = -radius; dx <= radius; dx++) {
          final xx = (x + dx).clamp(0, src.width - 1);
          final v = src.getPixel(xx, yy).r.toInt();
          if (v < mn) mn = v;
        }
      }
      out.setPixelRgb(x, y, mn, mn, mn);
    }
  }
  return out;
}
```

3c. Add `buildCorrectionMask` immediately AFTER the `fillHoles` function (added in Task 1):
```dart

/// Builds the per-pixel correction mask at proxy resolution from the color proxy
/// [colorProxy]. A pixel seeds as PHOTO if it is colorful (chroma), textured
/// (local std-dev), or dark content (low correctionWeight). The binary seed is
/// opened (erase thin text speckle), closed + hole-filled (consolidate the
/// region and absorb enclosed smooth areas), then inverted to a correction
/// weight (photo -> 0, paper -> 255) and feathered. Grayscale out: channel =
/// alpha * 255. Exposed for tests.
@visibleForTesting
img.Image buildCorrectionMask(img.Image colorProxy) {
  final w = colorProxy.width, h = colorProxy.height;
  final seed = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = colorProxy.getPixel(x, y);
      final r = px.r.toInt(), g = px.g.toInt(), b = px.b.toInt();
      final chroma =
          math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
      final isPhoto = chroma > _kChromaThresh ||
          localStdDev(colorProxy, x, y) > _kTextureThresh ||
          correctionWeight(px.luminance.toInt()) <= 0;
      final v = isPhoto ? 255 : 0;
      seed.setPixelRgb(x, y, v, v, v);
    }
  }
  // Opening (erode->dilate) removes thin speckle; closing (dilate->erode) +
  // fill-holes consolidates the region and absorbs enclosed smooth sub-areas.
  final opened = _maxFilter(_minFilter(seed, _kSpeckleRadius), _kSpeckleRadius);
  final closed =
      _minFilter(_maxFilter(opened, _kConsolidateRadius), _kConsolidateRadius);
  final region = fillHoles(closed);
  // Invert: photo (foreground) -> alpha 0; paper -> alpha 255.
  final weight = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final a = region.getPixel(x, y).r.toInt() > 127 ? 0 : 255;
      weight.setPixelRgb(x, y, a, a, a);
    }
  }
  return img.gaussianBlur(weight, radius: _kMaskFeather);
}
```

- [ ] **Step 4: Run the mask tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name buildCorrectionMask`
Expected: PASS (3 tests). If the text-rejection test fails (speckle survived), the opening is the lever — but do NOT weaken the assertion; confirm `_kSpeckleRadius`/`_kChromaThresh`/`_kTextureThresh` are as specified and the seed uses OR of the three cues.

- [ ] **Step 5: Full-file regression + commit**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart`
Expected: PASS — pipeline still untouched, existing tests green.

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/lib/features/library/auto_enhancer.dart apps/mobile/test/features/library/auto_color_enhancer_test.dart
git commit -m "feat(auto): multi-cue photo-region mask (chroma+texture+darkness)

buildCorrectionMask: seed on 3 cues -> opening (kill text speckle) ->
closing + fill-holes (consolidate + absorb enclosed areas) -> feather.
Plus _minFilter. Not yet wired.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Wire the mask into the pipeline

Split the background step so the pipeline keeps the color proxy (for chroma), build the mask, thread it into the divide. Behavioral tests are the load-bearing proof.

**Files:**
- Modify: `apps/mobile/lib/features/library/auto_enhancer.dart`
- Test: `apps/mobile/test/features/library/auto_color_enhancer_test.dart`

**Interfaces:**
- Consumes: `buildCorrectionMask`, `_downscaleProxy`, `_backgroundFromProxy` (new), `correctionWeight`.
- Produces: new `_divideByBackground(img.Image src, img.Image bg, img.Image alphaMap)` signature. `AutoEnhancer.enhance` public API unchanged.

- [ ] **Step 1: Write the failing behavioral tests**

Add inside `group('AutoEnhancer', ...)` in `auto_color_enhancer_test.dart`:

```dart
    test('preserves a COLORFUL photo region (not blown to white), '
        'paper still flattens', () async {
      const w = 240, h = 240;
      final src = img.Image(width: w, height: h);
      int bgVal(int x) => 150 + (x * 95 ~/ (w - 1)); // shadow gradient paper
      for (final px in src) { final v = bgVal(px.x); px..r = v..g = v..b = v; }
      // bright saturated photo block (would blow out under the brightness gate).
      for (var y = 60; y < 180; y++) {
        for (var x = 60; x < 180; x++) { src.getPixel(x, y)..r = 210..g = 60..b = 55; }
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final out = img.decodeImage(await const AutoEnhancer().enhance(input))!;

      final p = out.getPixel(120, 120);
      expect(p.luminance, lessThan(215),
          reason: 'colorful photo must not be whitened');
      expect((p.r.toInt() - p.g.toInt()).abs(), greaterThan(40),
          reason: 'photo keeps its colour');
      expect(out.getPixel(10, 120).luminance, greaterThan(220),
          reason: 'paper around the photo still flattens');
    });

    test('preserves a TEXTURED grayscale photo (multi-tone) region', () async {
      const w = 240, h = 240;
      final src = img.Image(width: w, height: h);
      for (final px in src) { px..r = 235..g = 235..b = 235; } // paper
      // photo = grid of distinct gray tones (survives downscale as texture),
      // with a bright smooth patch enclosed in the middle.
      const tones = [60, 120, 90, 150, 40, 110];
      for (var y = 60; y < 180; y++) {
        for (var x = 60; x < 180; x++) {
          final t = tones[(((x - 60) ~/ 20) + ((y - 60) ~/ 20)) % tones.length];
          src.getPixel(x, y)..r = t..g = t..b = t;
        }
      }
      for (var y = 108; y < 132; y++) {
        for (var x = 108; x < 132; x++) { src.getPixel(x, y)..r = 165..g = 165..b = 165; }
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final out = img.decodeImage(await const AutoEnhancer().enhance(input))!;

      expect(out.getPixel(120, 120).luminance, lessThan(215),
          reason: 'bright patch inside a textured photo must be preserved');
      expect(out.getPixel(10, 10).luminance, greaterThan(220),
          reason: 'paper still flattens');
    });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name "COLORFUL photo"`
Expected: FAIL — current pipeline (per-pixel brightness gate) blows the bright colorful/patch regions past the thresholds.

- [ ] **Step 3: Replace `_estimateBackground` with `_downscaleProxy` + `_backgroundFromProxy`**

Replace the whole `_estimateBackground` function with these two:
```dart
/// Downscales to the tiny COLOR proxy used for both background estimation and
/// photo-region detection. Skips downscale for frames already <= the proxy size.
img.Image _downscaleProxy(img.Image src) {
  final longest = math.max(src.width, src.height);
  if (longest <= _kBackgroundProxyPx) return src.clone();
  final scale = _kBackgroundProxyPx / longest;
  return img.copyResize(
    src,
    width: math.max(1, (src.width * scale).round()),
    height: math.max(1, (src.height * scale).round()),
    interpolation: img.Interpolation.average,
  );
}

/// Paper-background estimate at proxy resolution from the color proxy:
/// grayscale -> max-filter (erase ink) -> blur. Clones so [colorProxy] (still
/// needed for chroma) is not mutated. NOT upscaled — caller upscales.
img.Image _backgroundFromProxy(img.Image colorProxy) {
  final gray = colorProxy.clone();
  img.grayscale(gray);
  final dilated = _maxFilter(gray, _kDilateRadius);
  return img.gaussianBlur(dilated, radius: _kBlurRadius);
}
```

- [ ] **Step 4: Rewire `_autoFn`**

Replace the body of `_autoFn` with:
```dart
Uint8List _autoFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    // EXIF scrubber keeps the Orientation tag; encodeJpg strips EXIF, so bake
    // orientation into pixels first. Safe no-op for already-flat bytes.
    final oriented = img.bakeOrientation(decoded);
    final colorProxy = _downscaleProxy(oriented);
    final bgProxy = _backgroundFromProxy(colorProxy);
    final bg = img.copyResize(bgProxy,
        width: oriented.width,
        height: oriented.height,
        interpolation: img.Interpolation.linear);
    final alphaMap = img.copyResize(buildCorrectionMask(colorProxy),
        width: oriented.width,
        height: oriented.height,
        interpolation: img.Interpolation.linear);
    _divideByBackground(oriented, bg, alphaMap);
    _autoLevels(oriented); // global white-point + contrast finish
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
  } catch (_) {
    return bytes;
  }
}
```

- [ ] **Step 5: Add the `alphaMap` parameter to `_divideByBackground`**

Replace the whole `_divideByBackground` function with:
```dart
/// Flat-field correction gated by a per-pixel correction mask [alphaMap]
/// (grayscale; channel/255 = alpha). alpha ~ 1 (paper) -> full divide by the
/// local background [bg] (shadow removal); alpha ~ 0 (a detected photo region)
/// -> pixel left as captured. Channels scale proportionally, so hue is
/// preserved. Guards bg == 0.
void _divideByBackground(img.Image src, img.Image bg, img.Image alphaMap) {
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final b = bg.getPixel(x, y).r.toInt();
      if (b <= 0) continue;
      final alpha = alphaMap.getPixel(x, y).r / 255;
      if (alpha <= 0) continue; // photo region — leave the pixel untouched
      final scale = 1 + alpha * (255 / b - 1);
      final px = src.getPixel(x, y);
      px.r = (px.r.toInt() * scale).clamp(0, 255).toInt();
      px.g = (px.g.toInt() * scale).clamp(0, 255).toInt();
      px.b = (px.b.toInt() * scale).clamp(0, 255).toInt();
    }
  }
}
```

- [ ] **Step 6: Run behavioral tests then the full file**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name "COLORFUL photo"` → PASS
Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name "TEXTURED grayscale"` → PASS
Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart`
Expected: PASS — ALL tests green: the two new behavioral tests, the prior shadow-gradient (text) test (paper-ness ≈1 → mask ≈255 → still flattens), the existing solid-dark-block photo-preservation test (`'preserves a large dark region (embedded photo)...'`), `correctionWeight`, `localStdDev`, `fillHoles`, `buildCorrectionMask`, contrast/color/corrupt/EXIF/uniform/tiny. Do NOT weaken any assertion. If the prior shadow-gradient test regresses (paper wrongly detected as photo), the cue thresholds are too low — confirm they match the spec; investigate rather than weaken.

- [ ] **Step 7: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/lib/features/library/auto_enhancer.dart apps/mobile/test/features/library/auto_color_enhancer_test.dart
git commit -m "feat(auto): gate flat-field divide with multi-cue photo-region mask

Detect photo regions by chroma/texture/darkness and preserve them whole
(bright, dark, colourful), not just uniformly-dark blocks. _downscaleProxy
keeps the colour proxy; _autoFn upscales bg + mask; _divideByBackground
takes alphaMap.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: BDD scenario — colourful/textured photo preserved

**Files:**
- Modify: `apps/mobile/test/step/the_auto_enhancer_preserves_the_photo.dart`
- Regenerate: `apps/mobile/integration_test/g3_auto_color_test.dart` (build_runner)

**Interfaces:**
- Consumes: `g1Repo.lastSavedEnhancer`, `AutoEnhancer.enhance`.
- Produces: end-to-end BDD proof a colourful photo region is preserved. The existing scenario already wires `theAutoEnhancerPreservesThePhoto`; only the step body changes (regenerate to be safe).

- [ ] **Step 1: Strengthen the Then step**

Replace the whole body of `apps/mobile/test/step/the_auto_enhancer_preserves_the_photo.dart` with:
```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/auto_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the auto enhancer preserves the photo
///
/// Verifies the UI-selected enhancer ([g1Repo.lastSavedEnhancer]) preserves a
/// colourful embedded photo region (not blown to white, colour kept) while the
/// surrounding paper stays bright.
Future<void> theAutoEnhancerPreservesThePhoto(WidgetTester tester) async {
  final enhancer = g1Repo.lastSavedEnhancer;
  expect(enhancer, isA<AutoEnhancer>(),
      reason: 'UI must have selected AutoEnhancer');

  const w = 240, h = 240;
  final src = img.Image(width: w, height: h);
  for (final px in src) { px..r = 235..g = 235..b = 235; } // paper
  for (var y = 60; y < 180; y++) {
    for (var x = 60; x < 180; x++) { src.getPixel(x, y)..r = 210..g = 60..b = 55; } // colourful photo
  }
  final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

  final out = img.decodeImage(await enhancer!.enhance(input))!;
  final p = out.getPixel(120, 120);

  expect(p.luminance, lessThan(215),
      reason: 'colourful photo must not be blown out to white');
  expect((p.r.toInt() - p.g.toInt()).abs(), greaterThan(40),
      reason: 'photo keeps its colour');
  expect(out.getPixel(10, 10).luminance, greaterThan(200),
      reason: 'paper around the photo must still be bright');
}
```

- [ ] **Step 2: Regenerate the integration test**

Run: `cd apps/mobile && dart run build_runner build`
Expected: regenerates `integration_test/g3_auto_color_test.dart` (scenario wiring unchanged; step body changed). If a removed flag is rejected, run without it.

- [ ] **Step 3: Analyze**

Run: `cd apps/mobile && flutter analyze test/step/the_auto_enhancer_preserves_the_photo.dart integration_test/g3_auto_color_test.dart`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/test/step/the_auto_enhancer_preserves_the_photo.dart apps/mobile/integration_test/g3_auto_color_test.dart
git commit -m "test(g3): BDD — colourful photo region preserved with its colour

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: On-device verification

**Files:** none (manual verification + tuning).

- [ ] **Step 1: Build and run on Android device RZCY51D0T1K**

Run: `cd apps/mobile && flutter run -d RZCY51D0T1K`
Capture FOUR inputs under a hand-shadow where possible: (a) a plain text page; (b) a page with a printed COLOUR photo; (c) a page with a grayscale photo; (d) a text-DENSE page (small font / bold headings).

- [ ] **Step 2: Verify outcomes**

Confirm on-device: (a) text page shadow removed, background white; (b) colour photo preserved — natural, not blown out, no halo; (c) grayscale photo preserved; (d) the text-dense page is STILL fully de-shadowed (no false-positive treating text as a photo). Repeat on the iOS simulator for parity.

- [ ] **Step 3: Tune thresholds if needed**

If a photo washes out → lower `_kChromaThresh` / `_kTextureThresh` (detect more) or raise `_kConsolidateRadius`. If text is wrongly preserved (left shadowed) → raise `_kChromaThresh` / `_kTextureThresh` or raise `_kSpeckleRadius` (stronger speckle removal). If halo/seam at photo borders → raise `_kMaskFeather`. Change only the 5 const values; re-run Task 2 Step 5 + Task 3 Step 6 after any change, then re-verify on device. Commit tuning with a device-observed reason.

- [ ] **Step 4: Report**

State plainly what was observed on each platform for all four inputs, and any thresholds tuned and why. Do not claim "done" while any gap remains open (green gate ≠ done). Note explicitly whether the text-dense page kept full shadow removal (the bias requirement).

---

## Notes for the implementer

- `image` 4.3.0: `copyResize`, `gaussianBlur(radius:)`, `grayscale`, `Interpolation.average/linear`, `Pixel.luminance`/`.r`, `setPixelRgb`, `clone` all exist. `dart:math` (`math.sqrt/max/min`) is already imported in this file.
- All new helpers are top-level (isolate-sendable for `compute`).
- Detection runs only on the ≤48px proxy — never move the per-pixel loops to full resolution.
- `alphaMap.getPixel(x,y).r` is a `num` 0–255; `/255` yields the `double` alpha.
- If any `flutter test` flag (e.g. `--plain-name`) is rejected by the installed Flutter, drop it and run the whole file — not a blocker.
- Texture is computed on the downscaled proxy, so it captures LARGE-scale tonal structure (not fine grain, which averages out) — this is intended for region detection.
