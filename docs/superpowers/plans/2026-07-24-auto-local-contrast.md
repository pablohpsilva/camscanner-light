# Auto Filter Local Adaptive Contrast — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Auto filter's global white-point stretch with a color-preserving *local* luminance contrast stretch so faded text stays readable on bright-white backgrounds.

**Architecture:** `autoEnhanceOriented` keeps Stage 1 (per-channel flat-field). Stage 2 becomes `_localContrast`: build local black/white luminance reference fields on a proxy (min/max filter + blur), then per full-res pixel do a local linear stretch on luminance and scale RGB by the luma ratio (color preserved), with a blank-region guard and a strength blend. The native path (`autoFlatField`) mirrors this with OpenCV Mat ops; `np2` parity gate (`mean < 2.0`) guards the two.

**Tech Stack:** Dart, `package:image` (host path), `package:opencv_dart` 2.1.0 (native path, dartcv FFI), `flutter_test`, `bdd_widget_test`, `build_runner`.

## Global Constraints

- All commands run from `apps/mobile/` unless noted.
- TDD + BDD required; nothing is "done" without host tests + a `.feature` scenario, verified green on a **real Android device AND a real iOS device** (or a named, explicit gap).
- `flutter analyze` must be zero-warning.
- Native and Dart Auto outputs must stay within the `np2` gate: `mean < 2.0` (measured ~0.151 today). Never silently relax; if exceeded, report the number.
- OpenCV does not load under plain `flutter test`; native parity is proven only via `integration_test/*` on a device/sim. Dart-path unit tests run under plain `flutter test`.
- Luminance weights are `0.299 R + 0.587 G + 0.114 B` on both paths (matches `cv.COLOR_BGR2GRAY`).
- Starting constants (tune, then record final values + reasoning in doc-comments): `kAutoLocalWindowRadius = 16`, `kAutoLocalBlurRadius = 24`, `kAutoLocalMinSpan = 40`, `kAutoLocalStrength = 0.8`.
- Commit scope: `git add <named paths>` only — never `git add -A` (repo carries a long-lived WIP pile). Work on branch `feat/auto-local-contrast`.

---

## File Structure

- `lib/features/library/auto_enhancer.dart` — add 4 constants, `_luma`, `_minFilter`, `_estimateLocalRefs`, `_localContrast`; swap the Stage-2 call in `autoEnhanceOriented`. Delete `_whitePointStretch` and its `white_point_lut.dart` import.
- `lib/features/library/native_enhancers.dart` — replace the `whitePointLut3` stretch in `autoFlatField` with the mirrored local-contrast Mat pipeline; import the 4 constants via `show`; drop the `white_point_lut.dart` import and `whitePointLut3`.
- `lib/features/library/white_point_lut.dart` — **delete** (sole consumers were the two Auto files).
- `test/features/library/white_point_lut_test.dart` — **delete** with it.
- `test/features/library/auto_color_enhancer_test.dart` — add local-contrast tests; adjust global-stretch-coupled assertions.
- `test/features/library/local_contrast_fixture.dart` — **create**: shared helper building the synthetic bright-bg + faded-text image (used by host + device tests).
- `integration_test/g3_auto_color.feature` — add the faded-text scenario (regenerates `g3_auto_color_test.dart` via build_runner).
- `test/step/the_auto_enhancer_keeps_the_faded_text_readable.dart` — **create** the new step.
- `integration_test/np2_native_auto_parity_test.dart` — add a bright-bg parity case; threshold unchanged unless measurement forces a documented bump.

---

## Task 0: Finalize formula + constants (blocking, tiny)

This task only edits this plan's shared reference below and adds the constants. It unblocks T1–T3. No behavior change ships yet.

**Files:**
- Modify: `lib/features/library/auto_enhancer.dart` (add constants near the other `kAuto*` constants, ~line 44)

**Interfaces:**
- Produces: four top-level `const` values consumed by the Dart and native paths.

**The shared per-pixel formula (authoritative — copy verbatim into both paths):**

```
// Inputs per full-res pixel: r,g,b (0..255); B,W = bilinearly-sampled local
// black/white luma refs (doubles); constants below.
final y = 0.299 * r + 0.587 * g + 0.114 * b;      // full-res luma (double)
final span = W - B;
double yout;
if (span < kAutoLocalMinSpan) {
  yout = y;                                         // blank/low-contrast: untouched
} else {
  final yPrime = ((y - B) * 255.0 / span).clamp(0.0, 255.0);
  yout = y + kAutoLocalStrength * (yPrime - y);     // strength blend
}
final scale = yout / (y < 1.0 ? 1.0 : y);          // Y>0 guard
r' = (r * scale).round().clamp(0, 255);            // color preserved
g' = (g * scale).round().clamp(0, 255);
b' = (b * scale).round().clamp(0, 255);
```

- [ ] **Step 1: Add the constants**

```dart
/// Radius (proxy px) of the min/max window that estimates the LOCAL ink (min)
/// and LOCAL paper white (max) luminance under each region. Large enough to
/// span a text block so the min lands on real ink and the max on real paper.
const int kAutoLocalWindowRadius = 16;

/// Gaussian radius smoothing the local black/white reference fields into soft
/// gradients before they are divided out (avoids blocky contrast transitions).
const int kAutoLocalBlurRadius = 24;

/// Minimum local luminance span (white - black) for a region to be stretched.
/// Below this the region is blank/uniform paper with no real ink — leave it
/// untouched so sensor noise is not amplified into speckle.
const int kAutoLocalMinSpan = 40;

/// Blend of the locally-stretched luma vs the original (0 = off, 1 = full).
/// < 1 keeps already-clean images looking natural while still rescuing faded
/// text on bright backgrounds.
const double kAutoLocalStrength = 0.8;
```

- [ ] **Step 2: Verify it still analyzes (constants unused yet is fine — they are public)**

Run: `flutter analyze lib/features/library/auto_enhancer.dart`
Expected: No new warnings (unused top-level `const` with doc-comments is allowed).

- [ ] **Step 3: Commit**

```bash
git add lib/features/library/auto_enhancer.dart docs/superpowers/plans/2026-07-24-auto-local-contrast.md
git commit -m "feat(auto): add local-contrast constants (T0)"
```

---

## Task 1: Synthetic fixture helper

**Files:**
- Create: `test/features/library/local_contrast_fixture.dart`

**Interfaces:**
- Produces: `Uint8List brightBgFadedTextJpg({int w = 240, int h = 160})` — a JPEG of a uniform bright background (luma ≈ 245) with a faded-gray text block (luma ≈ 170) in the center. Used by T2 tests and the device test (T6).

- [ ] **Step 1: Create the fixture helper**

```dart
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// A uniform bright background (near-white, luma ~245) with a faded-gray text
/// block (luma ~170) centered in it. Models "photo of a document on a bright
/// white desk with light/faded print" — the case the global stretch washed out.
/// [textRect] is (left, top, right, bottom) in pixels.
Uint8List brightBgFadedTextJpg({int w = 240, int h = 160}) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  // Bright neutral background.
  for (final px in im) {
    px
      ..r = 246
      ..g = 245
      ..b = 244;
  }
  // Faded gray text block (low contrast against the bright bg).
  final l = w ~/ 4, t = h ~/ 4, r = 3 * w ~/ 4, b = 3 * h ~/ 4;
  for (var y = t; y < b; y++) {
    for (var x = l; x < r; x++) {
      // Simulate text strokes: every 4th column is "ink", rest is paper.
      if (x % 4 == 0) {
        im.getPixel(x, y)
          ..r = 170
          ..g = 170
          ..b = 170;
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

/// (left, top, right, bottom) of the faded-text block for a given size, so
/// tests can sample ink vs paper regions.
(int, int, int, int) fadedTextRect(int w, int h) =>
    (w ~/ 4, h ~/ 4, 3 * w ~/ 4, 3 * h ~/ 4);
```

- [ ] **Step 2: Sanity-check it builds a decodable JPEG**

Add a throwaway assertion in T2's test file (or run `dart analyze`). Run:
`flutter analyze test/features/library/local_contrast_fixture.dart`
Expected: No warnings.

- [ ] **Step 3: Commit**

```bash
git add test/features/library/local_contrast_fixture.dart
git commit -m "test(auto): synthetic bright-bg faded-text fixture (T1)"
```

---

## Task 2: Dart local-contrast implementation (TDD)

Depends on T0 (constants) + T1 (fixture). Write tests first.

**Files:**
- Modify: `test/features/library/auto_color_enhancer_test.dart`
- Modify: `lib/features/library/auto_enhancer.dart`

**Interfaces:**
- Consumes: `kAutoLocalWindowRadius/BlurRadius/MinSpan/Strength` (T0), `brightBgFadedTextJpg`, `fadedTextRect` (T1).
- Produces: `autoEnhanceOriented(img.Image) -> img.Image` (unchanged signature) now applying local contrast; helper `Uint8List _minFilter(...)` mirroring `_maxFilter`.

- [ ] **Step 1: Write the failing core-fix test**

Add to the `AutoEnhancer` group in `auto_color_enhancer_test.dart` (add
`import 'local_contrast_fixture.dart';` at top):

```dart
test('local contrast rescues faded text on a bright background: text/bg '
    'contrast increases well beyond the input', () async {
  final input = brightBgFadedTextJpg();
  final decodedIn = img.decodeImage(input)!;
  final (l, t, r, b) = fadedTextRect(decodedIn.width, decodedIn.height);

  // Input contrast: ink column vs paper column inside the block.
  final inInk = decodedIn.getPixel(l + 4, (t + b) ~/ 2).luminance.toDouble();
  final inPaper = decodedIn.getPixel(l + 5, (t + b) ~/ 2).luminance.toDouble();
  final inContrast = (inPaper - inInk).abs();

  final output = await const AutoEnhancer().enhance(input);
  final out = img.decodeImage(output)!;
  final outInk = out.getPixel(l + 4, (t + b) ~/ 2).luminance.toDouble();
  final outPaper = out.getPixel(l + 5, (t + b) ~/ 2).luminance.toDouble();
  final outContrast = (outPaper - outInk).abs();

  expect(outContrast, greaterThan(inContrast * 1.5),
      reason: 'faded text must gain contrast after local enhancement');
  expect(outInk, lessThan(150),
      reason: 'ink darkens toward black locally');
  expect(outPaper, greaterThan(220),
      reason: 'surrounding paper stays near-white');
});
```

- [ ] **Step 2: Write the blank-region guard test**

```dart
test('blank near-white region with noise is not speckled by local contrast',
    () async {
  const w = 120, h = 80;
  final src = img.Image(width: w, height: h, numChannels: 3);
  // Uniform bright paper + tiny deterministic +/-3 noise, NO ink.
  var seed = 7;
  int noise() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return (seed % 7) - 3; // -3..3
  }
  for (final px in src) {
    final n = noise();
    px
      ..r = (245 + n).clamp(0, 255)
      ..g = (245 + n).clamp(0, 255)
      ..b = (245 + n).clamp(0, 255);
  }
  final output = await const AutoEnhancer().enhance(
    Uint8List.fromList(img.encodeJpg(src, quality: 95)),
  );
  final out = img.decodeImage(output)!;
  // Collect luma; std must stay small (no noise amplification).
  final lum = <double>[];
  for (final px in out) {
    lum.add(px.luminance.toDouble());
  }
  final mean = lum.reduce((a, b) => a + b) / lum.length;
  final variance =
      lum.map((s) => (s - mean) * (s - mean)).reduce((a, b) => a + b) /
          lum.length;
  expect(mean, greaterThan(230), reason: 'blank paper stays bright');
  expect(variance, lessThan(80),
      reason: 'guard prevents noise being stretched into speckle');
});
```

- [ ] **Step 3: Run the new tests — expect FAIL**

Run: `flutter test test/features/library/auto_color_enhancer_test.dart --plain-name 'local contrast rescues'`
Expected: FAIL (Stage 2 is still the global stretch; faded text still washes out).

- [ ] **Step 4: Implement the Dart local-contrast Stage 2**

In `auto_enhancer.dart`:

(a) Remove the `white_point_lut.dart` import (line 11) and the `_whitePointStretch` call + method (lines 99, 256-289).

(b) In `autoEnhanceOriented`, replace the Stage-2 line with:

```dart
  _flatten(pixels, w, h, bg, pw, ph); // divide by bilinearly-sampled white
  _localContrast(pixels, w, h);       // local luma stretch, color preserved
```

(c) Add a `_minFilter` beside `_maxFilter` — identical but tracking the min
(initialize accumulators to 255 and use `<`):

```dart
/// Per-channel morphological erosion: each output becomes the MIN over a
/// (2r+1)^2 window. Separable, same structure as [_maxFilter]. Used on the
/// single-channel luma proxy to find the local ink (darkest) reference.
Uint8List _minFilter(Uint8List src, int w, int h, int radius) {
  if (radius <= 0) return Uint8List.fromList(src);
  final tmp = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final lo = x - radius < 0 ? 0 : x - radius;
      final hi = x + radius >= w ? w - 1 : x + radius;
      var m = 255;
      for (var xx = lo; xx <= hi; xx++) {
        final v = src[row + xx];
        if (v < m) m = v;
      }
      tmp[row + x] = m;
    }
  }
  final out = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final lo = y - radius < 0 ? 0 : y - radius;
    final hi = y + radius >= h ? h - 1 : y + radius;
    for (var x = 0; x < w; x++) {
      var m = 255;
      for (var yy = lo; yy <= hi; yy++) {
        final v = src[yy * w + x];
        if (v < m) m = v;
      }
      out[y * w + x] = m;
    }
  }
  return out;
}
```

(d) Add a single-channel max filter for the luma proxy (reuse logic, 1 channel):

```dart
/// Single-channel max (local paper white) — 1-ch analogue of [_maxFilter].
Uint8List _maxFilter1(Uint8List src, int w, int h, int radius) {
  if (radius <= 0) return Uint8List.fromList(src);
  final tmp = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final lo = x - radius < 0 ? 0 : x - radius;
      final hi = x + radius >= w ? w - 1 : x + radius;
      var m = 0;
      for (var xx = lo; xx <= hi; xx++) {
        final v = src[row + xx];
        if (v > m) m = v;
      }
      tmp[row + x] = m;
    }
  }
  final out = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final lo = y - radius < 0 ? 0 : y - radius;
    final hi = y + radius >= h ? h - 1 : y + radius;
    for (var x = 0; x < w; x++) {
      var m = 0;
      for (var yy = lo; yy <= hi; yy++) {
        final v = src[yy * w + x];
        if (v > m) m = v;
      }
      out[y * w + x] = m;
    }
  }
  return out;
}
```

(e) Add the field estimator + the per-pixel stretch:

```dart
/// Estimates the LOCAL black (ink) and white (paper) luminance reference
/// fields on a proxy. Returns `(black, white, pw, ph)` as 1-ch proxy buffers.
(Uint8List, Uint8List, int, int) _estimateLocalRefs(
    Uint8List px, int w, int h) {
  // Full-res luma → proxy (average downscale, same discipline as Stage 1).
  final luma = Uint8List(w * h);
  for (var i = 0, j = 0; i < px.length; i += 3, j++) {
    luma[j] = (0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2])
        .round()
        .clamp(0, 255);
  }
  final lumaImg = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: luma.buffer,
    numChannels: 1,
  );
  final longest = math.max(w, h);
  final img.Image proxy;
  if (longest > kAutoProxyLongSide) {
    final scale = kAutoProxyLongSide / longest;
    proxy = img.copyResize(
      lumaImg,
      width: math.max(1, (w * scale).round()),
      height: math.max(1, (h * scale).round()),
      interpolation: img.Interpolation.average,
    );
  } else {
    proxy = lumaImg;
  }
  final pw = proxy.width, ph = proxy.height;
  final pbuf = proxy.getBytes(order: img.ChannelOrder.red); // 1-ch
  final black = _blur1(
    _minFilter(pbuf, pw, ph, kAutoLocalWindowRadius), pw, ph);
  final white = _blur1(
    _maxFilter1(pbuf, pw, ph, kAutoLocalWindowRadius), pw, ph);
  return (black, white, pw, ph);
}

/// Gaussian-blur a 1-ch buffer via the image package (wrap → blur → unwrap),
/// radius [kAutoLocalBlurRadius], matching the native gaussianBlur.
Uint8List _blur1(Uint8List src, int w, int h) {
  final blurred = img.gaussianBlur(
    img.Image.fromBytes(width: w, height: h, bytes: src.buffer, numChannels: 1),
    radius: kAutoLocalBlurRadius,
  );
  return blurred.getBytes(order: img.ChannelOrder.red);
}

/// Stage 2: local luminance contrast stretch that preserves colour. See the
/// plan's authoritative formula. Blank/low-contrast regions (span <
/// [kAutoLocalMinSpan]) are left untouched so noise is not amplified.
void _localContrast(Uint8List px, int w, int h) {
  final (black, white, bw, bh) = _estimateLocalRefs(px, w, h);
  final sx = bw > 1 ? (bw - 1) / (w - 1) : 0.0;
  final sy = bh > 1 ? (bh - 1) / (h - 1) : 0.0;
  for (var y = 0; y < h; y++) {
    final fy = y * sy;
    final y0 = fy.toInt();
    final y1 = y0 + 1 < bh ? y0 + 1 : y0;
    final wy = fy - y0;
    final r0 = y0 * bw, r1 = y1 * bw;
    final o = y * w * 3;
    for (var x = 0; x < w; x++) {
      final fx = x * sx;
      final x0 = fx.toInt();
      final x1 = x0 + 1 < bw ? x0 + 1 : x0;
      final wx = fx - x0;
      // Bilinear sample black & white refs.
      double sample(Uint8List f) {
        final t = f[r0 + x0] + (f[r0 + x1] - f[r0 + x0]) * wx;
        final b = f[r1 + x0] + (f[r1 + x1] - f[r1 + x0]) * wx;
        return t + (b - t) * wy;
      }
      final bRef = sample(black);
      final wRef = sample(white);
      final span = wRef - bRef;
      final oi = o + x * 3;
      final r = px[oi], g = px[oi + 1], b = px[oi + 2];
      final yLuma = 0.299 * r + 0.587 * g + 0.114 * b;
      double yout;
      if (span < kAutoLocalMinSpan) {
        yout = yLuma;
      } else {
        final yPrime = ((yLuma - bRef) * 255.0 / span).clamp(0.0, 255.0);
        yout = yLuma + kAutoLocalStrength * (yPrime - yLuma);
      }
      final scale = yout / (yLuma < 1.0 ? 1.0 : yLuma);
      final nr = (r * scale).round();
      final ng = (g * scale).round();
      final nb = (b * scale).round();
      px[oi] = nr > 255 ? 255 : (nr < 0 ? 0 : nr);
      px[oi + 1] = ng > 255 ? 255 : (ng < 0 ? 0 : ng);
      px[oi + 2] = nb > 255 ? 255 : (nb < 0 ? 0 : nb);
    }
  }
}
```

- [ ] **Step 5: Run the new tests — expect PASS**

Run: `flutter test test/features/library/auto_color_enhancer_test.dart`
Expected: the two new tests PASS. Fix any regression in the pre-existing Auto
tests (see Step 6) before moving on.

- [ ] **Step 6: Reconcile pre-existing Auto tests**

The `stretches contrast: max channel value reaches near-255` test and the
shadow/warm-cast tests must still pass. If the 8×8 "stretch to 255" test fails
because the tiny image's local span logic differs, adjust the assertion to
`greaterThan(200)` only if genuinely required by the new algorithm, and add a
one-line comment explaining why. Do NOT weaken the shadow/warm-cast/color/EXIF/
timeout/corrupt tests — they must stay green as-is.

Run: `flutter test test/features/library/auto_color_enhancer_test.dart`
Expected: all PASS.

- [ ] **Step 7: analyze + format**

Run: `flutter analyze lib/features/library/auto_enhancer.dart && dart format lib/features/library/auto_enhancer.dart test/features/library/auto_color_enhancer_test.dart`
Expected: zero warnings.

- [ ] **Step 8: Commit**

```bash
git add lib/features/library/auto_enhancer.dart test/features/library/auto_color_enhancer_test.dart
git commit -m "feat(auto): color-preserving local contrast on the Dart path (T2)"
```

---

## Task 3: Native mirror (parity-driven)

Depends on T0. Can run in parallel with T2. The driving test is `np2`
(runs on a device/sim, not host).

**Files:**
- Modify: `lib/features/library/native_enhancers.dart`
- Modify: `integration_test/np2_native_auto_parity_test.dart`

**Interfaces:**
- Consumes: `kAutoProxyLongSide, kAutoLocalWindowRadius, kAutoLocalBlurRadius, kAutoLocalMinSpan, kAutoLocalStrength, kAutoMaxGain` from `auto_enhancer.dart`.
- Produces: `autoFlatField(cv.Mat) -> cv.Mat` (unchanged signature) now doing local contrast in Stage 2.

- [ ] **Step 1: Add the bright-bg parity case to np2 (failing until native updated)**

In `np2_native_auto_parity_test.dart`, add after the existing full-frame test:

```dart
test('native Auto ≈ Dart Auto (bright bg + faded text)', () async {
  // Bright uniform bg with faded vertical "ink" strokes — the washed-out case.
  const w = 1200, h = 900;
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (final px in im) {
    px..r = 246..g = 245..b = 244;
  }
  for (var y = h ~/ 4; y < 3 * h ~/ 4; y++) {
    for (var x = w ~/ 4; x < 3 * w ~/ 4; x += 4) {
      im.getPixel(x, y)..r = 170..g = 170..b = 170;
    }
  }
  final bytes = Uint8List.fromList(img.encodeJpg(im, quality: 95));

  final nativeOut =
      await p.process(bytes, CropCorners.fullFrame, EnhancerMode.auto);
  expect(nativeOut, isNotNull);
  final baked = img.bakeOrientation(img.decodeImage(bytes)!);
  final dartImg = autoEnhanceOriented(baked);
  final nImg = img.decodeImage(nativeOut!)!;
  final nb = nImg.getBytes(order: img.ChannelOrder.rgb);
  final db = dartImg.getBytes(order: img.ChannelOrder.rgb);
  var sum = 0, maxd = 0;
  for (var i = 0; i < nb.length; i++) {
    final d = (nb[i] - db[i]).abs();
    sum += d;
    if (d > maxd) maxd = d;
  }
  final mean = sum / nb.length;
  // ignore: avoid_print
  print('NP2 bright-bg Auto: mean=${mean.toStringAsFixed(3)} max=$maxd');
  expect(mean, lessThan(2.0), reason: 'quality parity gate');
});
```

- [ ] **Step 2: Implement the native local-contrast Stage 2**

In `native_enhancers.dart` `autoFlatField`, keep steps 1-2 (proxy background
flat-field producing `flat`, a CV_8UC3 BGR Mat). Replace step 3 (the
`whitePointLut3`/`cv.LUT`) with the local-contrast pipeline below. Update the
imports: replace the `white_point_lut.dart` import with the constant `show`, and
remove `whitePointLut3`.

```dart
import 'auto_enhancer.dart'
    show
        kAutoProxyLongSide,
        kAutoDilateRadius,
        kAutoBlurRadius,
        kAutoMaxGain,
        kAutoLocalWindowRadius,
        kAutoLocalBlurRadius,
        kAutoLocalMinSpan,
        kAutoLocalStrength;
```

Replace step 3 with (declare the new Mats in the `try`/`finally` list):

```dart
    // 3. Local luminance contrast, colour preserved. Build local black (erode)
    //    and white (dilate) luma refs on a proxy, blur, upsample, then per-pixel
    //    Y' = (Y-B)*255/span (guarded by kAutoLocalMinSpan) blended by strength,
    //    and scale BGR by Y'/Y. Formula mirrors auto_enhancer.dart _localContrast.
    gray = cv.cvtColor(flat, cv.COLOR_BGR2GRAY);              // CV_8UC1 luma
    grayProxy = cv.resize(gray, (pw, ph), interpolation: cv.INTER_AREA);
    final lwin = 2 * kAutoLocalWindowRadius + 1;
    localKernel = cv.getStructuringElement(cv.MORPH_RECT, (lwin, lwin));
    blackP = cv.erode(grayProxy, localKernel);
    whiteP = cv.dilate(grayProxy, localKernel);
    final lblurK = 2 * kAutoLocalBlurRadius + 1;
    final lblurS = kAutoLocalBlurRadius * 2.0 / 3.0;
    blackPB = cv.gaussianBlur(blackP, (lblurK, lblurK), lblurS);
    whitePB = cv.gaussianBlur(whiteP, (lblurK, lblurK), lblurS);
    blackF = cv.resize(blackPB, (cols, rows), interpolation: cv.INTER_LINEAR)
        .convertTo(cv.MatType.CV_32FC1);
    whiteF = cv.resize(whitePB, (cols, rows), interpolation: cv.INTER_LINEAR)
        .convertTo(cv.MatType.CV_32FC1);
    grayF = gray.convertTo(cv.MatType.CV_32FC1);

    spanF = cv.subtract(whiteF, blackF);                     // W - B
    // yPrime = clamp((Y - B) * 255 / max(span, eps), 0, 255)
    final spanSafe = cv.max(
        spanF, cv.Mat.fromScalar(rows, cols, cv.MatType.CV_32FC1, cv.Scalar.all(1)));
    ynum = cv.subtract(grayF, blackF);
    yprimeRaw = cv.divide(ynum, spanSafe, scale: 255);
    yprime = cv.threshold(yprimeRaw, 255, 255, cv.THRESH_TRUNC).$2; // upper clamp
    yprime = cv.max(yprime, cv.Mat.fromScalar(
        rows, cols, cv.MatType.CV_32FC1, cv.Scalar.all(0)));       // lower clamp
    // blended = Y + strength*(yprime - Y)
    blended = cv.addWeighted(
        grayF, 1 - kAutoLocalStrength, yprime, kAutoLocalStrength, 0);
    // guard: where span < minSpan, use Y unchanged.
    guardMask = cv.compare(
        spanF,
        cv.Mat.fromScalar(rows, cols, cv.MatType.CV_32FC1,
            cv.Scalar.all(kAutoLocalMinSpan.toDouble())),
        cv.CMP_LT);                                          // 255 where blank
    grayF.copyTo(blended, mask: guardMask);                 // restore Y there
    // scale = blended / max(Y, 1); apply to each colour channel.
    graySafe = cv.max(grayF,
        cv.Mat.fromScalar(rows, cols, cv.MatType.CV_32FC1, cv.Scalar.all(1)));
    ratio = cv.divide(blended, graySafe);                   // CV_32FC1
    ratio3 = cv.merge([ratio, ratio, ratio]);               // CV_32FC3
    flatF2 = flat.convertTo(cv.MatType.CV_32FC3);
    outF = cv.multiply(flatF2, ratio3);
    return outF.convertTo(cv.MatType.CV_8UC3);               // saturating cast
```

Add every new Mat (`gray, grayProxy, localKernel, blackP, whiteP, blackPB,
whitePB, blackF, whiteF, grayF, spanF, ynum, yprimeRaw, yprime, blended,
guardMask, graySafe, ratio, ratio3, flatF2, outF`) to the nullable declarations
and the `finally` dispose list. Note some `cv.*` calls above create temporaries
(e.g. the inline `cv.Mat.fromScalar`, the `.convertTo` chained on `cv.resize`);
hoist any you cannot otherwise dispose into named locals and add them to the
dispose list so nothing leaks (native OOM crashes the app uncatchably).

- [ ] **Step 3: Verify the OpenCV API names against the installed opencv_dart**

Confirm `cv.erode`, `cv.compare`, `cv.CMP_LT`, `cv.addWeighted`, `cv.threshold`
(returns a record; `.$2` is the Mat), `cv.THRESH_TRUNC`, `cv.merge`,
`cv.multiply`, `Mat.copyTo(dst, mask:)` exist with these signatures.

Run: `grep -rn "erode\|addWeighted\|THRESH_TRUNC\|copyTo\|\bmerge\b\|CMP_LT" ~/.pub-cache/hosted/pub.dev/opencv_dart-2.1.0/lib/ | head -40`
Expected: each symbol resolves. If a signature differs, adapt (e.g. clamp via
`cv.min`/`cv.max` instead of `threshold`) keeping the same math.

- [ ] **Step 4: Run np2 on a device/sim — expect PASS (both new + existing cases)**

Run: `flutter test integration_test/np2_native_auto_parity_test.dart -d <device-id>`
Expected: all cases PASS; note the printed `mean=` for each. If `mean >= 2.0`,
STOP and report the measured number (do not relax the gate without a decision).

- [ ] **Step 5: analyze + format**

Run: `flutter analyze lib/features/library/native_enhancers.dart && dart format lib/features/library/native_enhancers.dart integration_test/np2_native_auto_parity_test.dart`
Expected: zero warnings.

- [ ] **Step 6: Commit**

```bash
git add lib/features/library/native_enhancers.dart integration_test/np2_native_auto_parity_test.dart
git commit -m "feat(auto): mirror local contrast on the native path + np2 bright-bg case (T3)"
```

---

## Task 4: BDD scenario

Depends on T2 (behaviour exists). Can be authored in parallel; regenerate after T2 lands.

**Files:**
- Modify: `integration_test/g3_auto_color.feature`
- Create: `test/step/the_auto_enhancer_keeps_the_faded_text_readable.dart`
- Generated: `integration_test/g3_auto_color_test.dart` (via build_runner)

**Interfaces:**
- Consumes: the existing g3 steps (`the review screen is open with a captured image`, `I toggle the auto filter`, `I tap Accept`).
- Produces: a new step asserting the saved page's faded text gained contrast.

- [ ] **Step 1: Add the scenario**

Append to `g3_auto_color.feature`:

```gherkin
  Scenario: Auto filter keeps faded text readable on a bright background
    Given the review screen is open with a captured image
    When I toggle the auto filter
    And I tap Accept
    Then the auto enhancer keeps the faded text readable
```

- [ ] **Step 2: Regenerate the widget test**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `g3_auto_color_test.dart` now references
`theAutoEnhancerKeepsTheFadedTextReadable`; build fails to find the step until
Step 3 (that's expected).

- [ ] **Step 3: Implement the step**

Look at an existing g3 step (e.g. `test/step/the_auto_enhancer_flattens_the_shadow.dart`) for the exact
pattern used to reach the saved page bytes, then create
`test/step/the_auto_enhancer_keeps_the_faded_text_readable.dart` mirroring it:

```dart
import 'package:flutter_test/flutter_test.dart';
// Mirror the imports/helpers used by the_auto_enhancer_flattens_the_shadow.dart
// to obtain the last saved page image; assert local contrast improved.

Future<void> theAutoEnhancerKeepsTheFadedTextReadable(WidgetTester tester) async {
  // Reuse the same saved-page accessor as the shadow step. Sample an ink
  // column vs an adjacent paper column inside the faded-text block and assert
  // the ink darkened relative to the paper (contrast increased).
  // (Concrete body copies the shadow step's retrieval, then:)
  //   expect(inkLuma, lessThan(paperLuma - 40),
  //       reason: 'faded text is readable after local contrast');
}
```

Fill the body by copying the retrieval logic from the shadow step verbatim
(same fixture-capture mechanism), substituting the faded-text fixture and the
ink-vs-paper contrast assertion above.

- [ ] **Step 4: Regenerate + run the widget test (host)**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test integration_test/g3_auto_color_test.dart`
Expected: the new scenario compiles and PASSES on host (if the step is
host-runnable; if it needs native libs, it is a device test — run under Step 5).

- [ ] **Step 5: analyze + format + commit**

Run: `flutter analyze integration_test/g3_auto_color_test.dart test/step/the_auto_enhancer_keeps_the_faded_text_readable.dart && dart format test/step/the_auto_enhancer_keeps_the_faded_text_readable.dart`

```bash
git add integration_test/g3_auto_color.feature integration_test/g3_auto_color_test.dart test/step/the_auto_enhancer_keeps_the_faded_text_readable.dart
git commit -m "test(auto): BDD scenario for faded text on bright background (T4)"
```

---

## Task 5: Delete the now-orphaned white_point_lut

Depends on T2 + T3 (both must have dropped their `white_point_lut` usage).

**Files:**
- Delete: `lib/features/library/white_point_lut.dart`
- Delete: `test/features/library/white_point_lut_test.dart`

- [ ] **Step 1: Confirm no remaining references**

Run: `grep -rn "white_point_lut\|whitePointLut" lib test integration_test`
Expected: NO matches (confirm with `Read` on a couple of files if grep is
empty — an empty rtk/grep can hide matches). If anything still references it,
STOP and fix that first.

- [ ] **Step 2: Delete both files**

```bash
git rm lib/features/library/white_point_lut.dart test/features/library/white_point_lut_test.dart
```

- [ ] **Step 3: Full host suite + analyze**

Run: `flutter analyze && flutter test`
Expected: zero warnings; host suite green (OpenCV-dependent host failures, if
any, are environmental per CLAUDE.md — confirm none are from this change).

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor(auto): remove orphaned white_point_lut (T5)"
```

---

## Task 6: Device verification, both platforms (gate to "done")

Depends on T2–T5. This is where "done" is earned.

**Files:** none (verification only). Record commands + output.

- [ ] **Step 1: Consolidated host suite**

Run: `flutter test`
Expected: green. Paste the summary line.

- [ ] **Step 2: Real Android device**

Run (with a real Android device attached, `flutter devices` to get the id):
`flutter test integration_test/np2_native_auto_parity_test.dart integration_test/g3_auto_color_test.dart integration_test/np1_native_pipeline_test.dart integration_test/np3_native_color_gray_test.dart integration_test/e2_flatten_test.dart integration_test/e5_edit_filter_test.dart -d <android-id>`
Expected: all PASS. Record the printed `NP2 ... mean=` values.

- [ ] **Step 3: Real iOS device**

Run the same command with `-d <ios-id>`.
Expected: all PASS. Record `mean=` values. Confirm on-device that a captured
bright-bg document's text is legible (smoke check via `flutter run` if practical).

- [ ] **Step 4: Record results in the plan**

Check off T6 with the exact commands and the green summaries + measured parity
means for both platforms. Name any gap explicitly (e.g. if only a simulator was
available for iOS, say so).

- [ ] **Step 5: No code commit** (verification task). If tuning was needed,
those commits belong to T2/T3 with a note.

---

## Self-Review (completed during planning)

- **Spec coverage:** Stage-2 replacement (T2/T3), color preservation (T2 formula + tests), blank-region guard (T2 test + native mask), parity gate (T3/T6), BDD (T4), fixture/named-gap (T1), white_point_lut cleanup (T5), both-platforms (T6). All spec sections mapped.
- **Placeholders:** none — every code step has concrete code; the one "copy the shadow step" instruction (T4 Step 3) points at a named existing file to mirror, with the exact assertion given.
- **Type consistency:** `autoEnhanceOriented`/`autoFlatField` signatures unchanged; new helpers (`_minFilter`, `_maxFilter1`, `_blur1`, `_estimateLocalRefs`, `_localContrast`) are internal to `auto_enhancer.dart`; constants named identically across T0/T2/T3.
- **Known risk:** native `cv.*` signatures (T3 Step 3 verifies them before relying on them); parity mean is empirical (T3 Step 4 / T6 surface the number, no silent relax).
