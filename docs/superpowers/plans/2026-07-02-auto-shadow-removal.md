# Auto Filter Shadow Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the default `Auto` scan filter so it removes hand/phone shadows and produces a clean white-paper document (uniform white background, crisp dark text, ink/stamp color preserved).

**Architecture:** Flat-field / background-division inside the existing `AutoEnhancer._autoFn` (pure-Dart `image` package, runs in a `compute` isolate). Estimate the paper-background brightness at every pixel (downscale → grayscale max-filter → blur → upscale), divide it out so every region normalizes to white, then finish with the existing global white-point stretch. Only `Auto`'s internals change — no enum, UI, or mapping changes.

**Tech Stack:** Dart, Flutter, `image: ^4.5.0` (resolved 4.3.0), `compute` isolates, `bdd_widget_test` + `build_runner` for BDD generation.

## Global Constraints

- `ImageEnhancer.enhance` **never throws** — on any failure return the input `bytes` unchanged (wrap the whole body in `try/catch`).
- Pure-Dart only. No OpenCV / `opencv_dart` in the enhancer (breaks host-test story per project memory).
- Identical result on iOS and Android — no native-binary variance.
- No bare magic numbers — every tunable is a named, documented `const`.
- Keep `AutoEnhancer` `const`-constructible and `implements ImageEnhancer`.
- JPEG output at `quality: 92` (matches the other enhancers).
- Do NOT touch `enhancer_mode.dart`, `filter_picker_strip.dart`, `capture_review_screen.dart`, or the other enhancers.

---

## File Structure

- **Modify:** `apps/mobile/lib/features/library/auto_enhancer.dart` — replace the body of top-level `_autoFn`; add isolate-sendable helpers `_estimateBackground`, `_maxFilter`, `_divideByBackground`; keep `_autoLevels` / `_histClip`.
- **Modify:** `apps/mobile/test/features/library/auto_color_enhancer_test.dart` — add shadow-flattening + graceful-degradation tests; keep the existing regression tests.
- **Modify:** `apps/mobile/integration_test/g3_auto_color.feature` — add the shadow scenario.
- **Create:** `apps/mobile/test/step/the_auto_enhancer_flattens_the_shadow.dart` — BDD Then step.
- **Regenerate:** `apps/mobile/integration_test/g3_auto_color_test.dart` — via `build_runner` (generated file, do not hand-edit).

---

## Task 1: Illumination-flattening algorithm (TDD)

**Files:**
- Modify: `apps/mobile/lib/features/library/auto_enhancer.dart`
- Test: `apps/mobile/test/features/library/auto_color_enhancer_test.dart`

**Interfaces:**
- Consumes: `img.decodeImage`, `img.bakeOrientation`, `img.copyResize`, `img.grayscale`, `img.gaussianBlur`, `img.encodeJpg`, `img.Interpolation` (`image` pkg 4.3.0).
- Produces: `AutoEnhancer` (unchanged public API: `const AutoEnhancer()`, `Future<Uint8List> enhance(Uint8List)`). Its `Auto` output now has a shadow-flattened, near-white background.

- [ ] **Step 1: Write the failing shadow-flattening test**

Add these two tests inside the existing `group('AutoEnhancer', ...)` in `apps/mobile/test/features/library/auto_color_enhancer_test.dart`. Add `import 'dart:math' as math;` at the top of the file if not present.

```dart
    test('flattens a shadow gradient: shadowed background becomes near-white, '
        'text stays dark, background variance collapses', () async {
      // 120x40 page: horizontal brightness gradient simulates a shadow
      // (left = dark 120, right = lit 240). Two dark "text" blocks: one in the
      // shadowed left, one in the lit right.
      const w = 120, h = 40;
      final src = img.Image(width: w, height: h);
      int bgVal(int x) => 120 + (x * 120 ~/ (w - 1)); // 120..240
      for (final px in src) {
        final v = bgVal(px.x);
        px..r = v..g = v..b = v;
      }
      // Dark text blocks (value 20) at left (x10-20) and right (x100-110), y15-25.
      for (var y = 15; y <= 25; y++) {
        for (var x = 10; x <= 20; x++) { src.getPixel(x, y)..r = 20..g = 20..b = 20; }
        for (var x = 100; x <= 110; x++) { src.getPixel(x, y)..r = 20..g = 20..b = 20; }
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);
      final out = img.decodeImage(output)!;

      // Background samples at y=5 (no text) across the frame.
      final bgSamples = [2, 30, 60, 90, 117]
          .map((x) => out.getPixel(x, 5).luminance.toDouble())
          .toList();
      for (final s in bgSamples) {
        expect(s, greaterThan(220),
            reason: 'every background sample (incl. the shadowed left) must be near-white');
      }
      final mean = bgSamples.reduce((a, b) => a + b) / bgSamples.length;
      final variance = bgSamples
              .map((s) => (s - mean) * (s - mean))
              .reduce((a, b) => a + b) /
          bgSamples.length;
      expect(variance, lessThan(100),
          reason: 'shadow gradient removed → background brightness is uniform');

      // Text stays dark relative to its now-white background.
      expect(out.getPixel(15, 20).luminance, lessThan(120),
          reason: 'shadowed-side text must remain dark');
      expect(out.getPixel(105, 20).luminance, lessThan(120),
          reason: 'lit-side text must remain dark');
    });

    test('image smaller than the background proxy does not crash', () async {
      final src = img.Image(width: 8, height: 8);
      for (final px in src) { px..r = 200..g = 180..b = 160; }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);

      expect(img.decodeImage(output), isNotNull,
          reason: 'tiny frames skip the downscale and must still produce valid JPEG');
    });
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart -p vm --plain-name "flattens a shadow gradient"`
Expected: FAIL — current global `_autoLevels` cannot flatten a gradient, so the shadowed-left background sample stays well below 220.

- [ ] **Step 3: Rewrite `auto_enhancer.dart` with the flat-field algorithm**

Replace the entire contents of `apps/mobile/lib/features/library/auto_enhancer.dart` with:

```dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';

/// Longest side of the downscaled proxy used to estimate the illumination map.
/// A large blur becomes cheap on a thumbnail, and the paper's shadow gradient
/// is low-frequency, so a tiny proxy captures it faithfully.
const int _kBackgroundProxyPx = 48;

/// Max-filter (grayscale dilation) radius on the proxy — erases dark ink so
/// only paper brightness remains in the background estimate.
const int _kDilateRadius = 1;

/// Gaussian blur radius on the proxy — smooths the estimate into a gradient.
const int _kBlurRadius = 3;

/// "Clean white paper" filter. Flattens uneven illumination (hand/phone
/// shadows) via flat-field background division, then a global white-point
/// stretch. Runs in a [compute] isolate — never blocks the UI thread.
class AutoEnhancer implements ImageEnhancer {
  const AutoEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_autoFn, bytes);
}

// Top-level function required by compute() (must be isolate-sendable).
Uint8List _autoFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    // EXIF scrubber keeps the Orientation tag; encodeJpg strips EXIF, so bake
    // orientation into pixels first. Safe no-op for already-flat bytes.
    final oriented = img.bakeOrientation(decoded);
    final bg = _estimateBackground(oriented);
    _divideByBackground(oriented, bg);
    _autoLevels(oriented); // global white-point + contrast finish
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
  } catch (_) {
    return bytes;
  }
}

/// Full-resolution per-pixel estimate of the paper-background brightness.
/// Downscale -> grayscale max-filter (erase ink) -> blur (smooth) -> upscale.
/// Returned image is grayscale: r == g == b == local background luminance.
img.Image _estimateBackground(img.Image src) {
  // 1. Downscale to a tiny proxy. Skip if the frame is already smaller than
  //    the proxy (tiny/test images) so we never upscale-then-downscale.
  final longest = math.max(src.width, src.height);
  final img.Image proxy;
  if (longest > _kBackgroundProxyPx) {
    final scale = _kBackgroundProxyPx / longest;
    proxy = img.copyResize(
      src,
      width: math.max(1, (src.width * scale).round()),
      height: math.max(1, (src.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  } else {
    proxy = src.clone();
  }

  // 2. Grayscale, then max-filter to remove dark ink from the estimate.
  img.grayscale(proxy);
  final dilated = _maxFilter(proxy, _kDilateRadius);

  // 3. Blur into a smooth illumination gradient (includes the shadow).
  final blurred = img.gaussianBlur(dilated, radius: _kBlurRadius);

  // 4. Upscale back to full resolution.
  return img.copyResize(
    blurred,
    width: src.width,
    height: src.height,
    interpolation: img.Interpolation.linear,
  );
}

/// Grayscale morphological dilation: each pixel becomes the max luminance in a
/// (2r+1)^2 window. Input is grayscale (r == g == b), so we read/write r.
img.Image _maxFilter(img.Image src, int radius) {
  if (radius <= 0) return src;
  final out = src.clone();
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      var mx = 0;
      for (var dy = -radius; dy <= radius; dy++) {
        final yy = (y + dy).clamp(0, src.height - 1);
        for (var dx = -radius; dx <= radius; dx++) {
          final xx = (x + dx).clamp(0, src.width - 1);
          final v = src.getPixel(xx, yy).r.toInt();
          if (v > mx) mx = v;
        }
      }
      out.setPixelRgb(x, y, mx, mx, mx);
    }
  }
  return out;
}

/// Flat-field correction: divide each channel by the local background so every
/// region normalizes to the same white. [bg] is grayscale (read r as the local
/// paper brightness). Shadowed paper (low bg) is boosted to white; ink (far
/// below the local bg) stays dark. Channels scale proportionally, so hue is
/// preserved. Guards bg == 0.
void _divideByBackground(img.Image src, img.Image bg) {
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final b = bg.getPixel(x, y).r.toInt();
      if (b <= 0) continue;
      final px = src.getPixel(x, y);
      px.r = (px.r.toInt() * 255 / b).clamp(0, 255).toInt();
      px.g = (px.g.toInt() * 255 / b).clamp(0, 255).toInt();
      px.b = (px.b.toInt() * 255 / b).clamp(0, 255).toInt();
    }
  }
}

void _autoLevels(img.Image src) {
  final n = src.width * src.height;
  if (n == 0) return;
  final clip = ((n / 100).ceil()).clamp(1, n);

  final rHist = List<int>.filled(256, 0);
  final gHist = List<int>.filled(256, 0);
  final bHist = List<int>.filled(256, 0);
  for (final px in src) {
    rHist[px.r.toInt()]++;
    gHist[px.g.toInt()]++;
    bHist[px.b.toInt()]++;
  }

  final (rLo, rHi) = _histClip(rHist, clip);
  final (gLo, gHi) = _histClip(gHist, clip);
  final (bLo, bHi) = _histClip(bHist, clip);

  for (final px in src) {
    if (rHi > rLo) {
      px.r = ((px.r.toInt() - rLo) * 255 ~/ (rHi - rLo)).clamp(0, 255);
    }
    if (gHi > gLo) {
      px.g = ((px.g.toInt() - gLo) * 255 ~/ (gHi - gLo)).clamp(0, 255);
    }
    if (bHi > bLo) {
      px.b = ((px.b.toInt() - bLo) * 255 ~/ (bHi - bLo)).clamp(0, 255);
    }
  }
}

(int, int) _histClip(List<int> hist, int clip) {
  int lo = 0, cumLo = 0;
  while (lo < 255 && cumLo + hist[lo] < clip) { cumLo += hist[lo++]; }
  int hi = 255, cumHi = 0;
  while (hi > lo && cumHi + hist[hi] < clip) { cumHi += hist[hi--]; }
  return (lo, hi);
}
```

Note: the old `img.adjustColor(saturation: 1.15)` step is dropped — the divide already preserves hue and a saturation bump on a now-white background muddies paper. If on-device review wants more pop, re-add it after `_autoLevels`.

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart -p vm --plain-name "flattens a shadow gradient"`
Expected: PASS

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart -p vm --plain-name "smaller than the background proxy"`
Expected: PASS

- [ ] **Step 5: Run the full enhancer suite for regression**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart test/features/library/bw_enhancer_test.dart test/features/library/grayscale_enhancer_test.dart -p vm`
Expected: PASS — all existing AutoEnhancer tests (contrast-stretch `maxR > 220`, color-preservation R≠G, corrupt→unchanged, EXIF-orientation bake, uniform-image no-crash) still pass under the new algorithm.

If the color-preservation test regresses, do NOT loosen it — investigate; the divide preserves channel ratios so it should hold. Report the failure instead of weakening the assertion.

- [ ] **Step 6: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/lib/features/library/auto_enhancer.dart apps/mobile/test/features/library/auto_color_enhancer_test.dart
git commit -m "feat(auto): flat-field shadow removal in Auto filter

Estimate paper-background brightness (downscale -> max-filter -> blur ->
upscale) and divide it out so hand/phone shadows flatten to a uniform
white background. Pure-Dart, runs in the existing compute isolate.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Shadow-removal BDD scenario

**Files:**
- Modify: `apps/mobile/integration_test/g3_auto_color.feature`
- Create: `apps/mobile/test/step/the_auto_enhancer_flattens_the_shadow.dart`
- Regenerate: `apps/mobile/integration_test/g3_auto_color_test.dart` (via build_runner)

**Interfaces:**
- Consumes: `g1Repo.lastSavedEnhancer` (set by the existing review-screen Given step when Accept is tapped), `AutoEnhancer.enhance` from Task 1.
- Produces: BDD proof that selecting `Auto` in the UI yields an enhancer that flattens shadows end-to-end.

- [ ] **Step 1: Add the shadow scenario to the feature file**

Append this scenario to `apps/mobile/integration_test/g3_auto_color.feature` (after the existing "Auto filter applied" scenario):

```gherkin
  Scenario: Auto filter removes the shadow from a shadowed capture
    Given the review screen is open with a captured image
    When I toggle the auto filter
    And I tap Accept
    Then the auto enhancer flattens the shadow
```

- [ ] **Step 2: Create the failing Then step**

Create `apps/mobile/test/step/the_auto_enhancer_flattens_the_shadow.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/auto_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the auto enhancer flattens the shadow
///
/// Verifies the enhancer the UI selected (recorded in [g1Repo.lastSavedEnhancer]
/// when Accept was tapped) actually removes a shadow gradient: a synthetic page
/// with a dark-left / lit-right illumination gradient must come out with a
/// uniform near-white background.
Future<void> theAutoEnhancerFlattensTheShadow(WidgetTester tester) async {
  final enhancer = g1Repo.lastSavedEnhancer;
  expect(enhancer, isA<AutoEnhancer>(),
      reason: 'UI must have selected AutoEnhancer');

  const w = 120, h = 40;
  final src = img.Image(width: w, height: h);
  int bgVal(int x) => 120 + (x * 120 ~/ (w - 1)); // 120 (shadow) .. 240 (lit)
  for (final px in src) {
    final v = bgVal(px.x);
    px..r = v..g = v..b = v;
  }
  final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

  final output = await enhancer!.enhance(input);
  final out = img.decodeImage(output)!;

  final left = out.getPixel(2, 20).luminance.toDouble();
  final right = out.getPixel(117, 20).luminance.toDouble();
  expect(left, greaterThan(220),
      reason: 'shadowed-left background must be flattened to near-white');
  expect(right, greaterThan(220),
      reason: 'lit-right background stays near-white');
  expect((left - right).abs(), lessThan(20),
      reason: 'shadow gradient removed → left and right are equally bright');
}
```

- [ ] **Step 3: Regenerate the integration test from the feature**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: regenerates `integration_test/g3_auto_color_test.dart` with the new scenario wired to `theAutoEnhancerFlattensTheShadow`. Confirm the generated file now imports `the_auto_enhancer_flattens_the_shadow.dart` and contains a `testWidgets` block for the shadow scenario.

- [ ] **Step 4: Verify the new step compiles and analyzes clean**

Run: `cd apps/mobile && flutter analyze test/step/the_auto_enhancer_flattens_the_shadow.dart integration_test/g3_auto_color_test.dart`
Expected: No issues (no undefined step, no analyzer errors).

Note: the integration suite runs on device/sim (the host `flutter test` run skips `integration_test/` per project memory). Do not expect it to run under `flutter test`.

- [ ] **Step 5: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/integration_test/g3_auto_color.feature apps/mobile/integration_test/g3_auto_color_test.dart apps/mobile/test/step/the_auto_enhancer_flattens_the_shadow.dart
git commit -m "test(g3): BDD scenario — Auto filter flattens capture shadows

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: On-device verification

**Files:** none (manual verification + tuning).

- [ ] **Step 1: Build and run on Android device RZCY51D0T1K**

Run: `cd apps/mobile && flutter run -d RZCY51D0T1K`
Capture a real document held by hand under a lamp so a clear shadow falls across it. Apply `Auto`.

- [ ] **Step 2: Verify the visual result**

Confirm on-device: (a) the shadow gradient is gone, (b) the page background is uniform white, (c) text is crisp and dark, (d) any colored ink/stamp keeps its hue. Repeat on the iOS simulator to confirm parity.

- [ ] **Step 3: Tune constants if needed**

If shadows partially remain, raise `_kBlurRadius` (smoother/larger illumination estimate) and/or `_kBackgroundProxyPx`. If text edges wash out or halo, lower `_kBlurRadius` or raise `_kDilateRadius`. Re-run Task 1 Step 5 (regression suite) after any change, then re-verify on device. Commit any tuning with a message noting the device-observed reason.

- [ ] **Step 4: Report**

State plainly what was observed on each platform (with the shadowed sample), which constants (if any) were tuned and why. Do not claim "done" while any gap remains open (per project rule: green gate ≠ done).

---

## Notes for the implementer

- The `image` package resolves to 4.3.0 here; `copyResize`, `gaussianBlur(radius:)`, `grayscale`, `Interpolation.{average,linear}`, `Pixel.luminance`, `setPixelRgb`, and `clone()` are all available at that version.
- `_maxFilter` runs on the tiny proxy only (≤ 48px longest side), so its O(n·r²) cost is negligible — do not "optimize" it onto the full frame.
- Every helper is a top-level function so it stays isolate-sendable for `compute`.
