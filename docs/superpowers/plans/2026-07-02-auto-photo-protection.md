# Auto Filter Photo Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the `Auto` scan filter from blowing out large dark regions (embedded photos, filled blocks) while keeping full shadow removal on paper.

**Architecture:** Gate the existing flat-field division on the local background brightness. A small pure function `correctionWeight(b)` maps background luminance to a 0→1 correction weight (0 = dark content, left untouched; 1 = paper, fully corrected; smooth ramp between). `_divideByBackground` blends original↔divided by that weight. Pure-Dart, inside the existing `compute` isolate. Only `auto_enhancer.dart` changes.

**Tech Stack:** Dart, Flutter, `image` 4.3.0, `compute` isolates, `@visibleForTesting` (from `package:flutter/foundation.dart`), `bdd_widget_test` + `build_runner`.

## Global Constraints

- `ImageEnhancer.enhance` NEVER throws — returns input bytes on any failure (existing try/catch stays).
- Pure-Dart only; no opencv_dart; identical result iOS/Android.
- No bare magic numbers — every tunable is a named, documented `const` (`_kPaperFloor`, `_kGateBand`).
- `AutoEnhancer` stays `const` + `implements ImageEnhancer`; JPEG quality 92.
- "Protect photos" bias: when a region is genuinely dark, err toward preserving it (accept that a very deep shadow over blank paper may be left slightly darker).
- Do NOT modify enhancer_mode.dart, filter_picker_strip.dart, capture_review_screen.dart, or the other enhancers.
- Do NOT change `_estimateBackground`, `_maxFilter`, `_autoLevels`, or the shadow-removal behavior on paper.

---

## File Structure

- **Modify:** `apps/mobile/lib/features/library/auto_enhancer.dart` — add `_kPaperFloor`, `_kGateBand`, and a pure `@visibleForTesting double correctionWeight(int)`; gate `_divideByBackground` with it. Change the `foundation` import to also show `visibleForTesting`.
- **Modify:** `apps/mobile/test/features/library/auto_color_enhancer_test.dart` — add a `correctionWeight` unit group (Task 1) and a photo-preservation behavioral test (Task 2).
- **Modify:** `apps/mobile/integration_test/g3_auto_color.feature` — add the photo-preservation scenario (Task 3).
- **Create:** `apps/mobile/test/step/the_auto_enhancer_preserves_the_photo.dart` (Task 3).
- **Regenerate:** `apps/mobile/integration_test/g3_auto_color_test.dart` via build_runner (Task 3).

---

## Task 1: Correction-weight function + gate wiring

Pure gate math, unit-tested directly, wired into the divide in the same task (so no unused-element lint). The existing shadow-gradient test is the guard that paper-flattening is unchanged.

**Files:**
- Modify: `apps/mobile/lib/features/library/auto_enhancer.dart`
- Test: `apps/mobile/test/features/library/auto_color_enhancer_test.dart`

**Interfaces:**
- Consumes: `_estimateBackground`, `_maxFilter`, `_autoLevels` (unchanged); `img` pkg.
- Produces: `@visibleForTesting double correctionWeight(int backgroundLuminance)` — returns 0.0 for `backgroundLuminance <= _kPaperFloor` (95), 1.0 for `>= _kPaperFloor + _kGateBand` (120), linear ramp between. Consumed by `_divideByBackground` and by Task 2's test.

- [ ] **Step 1: Write the failing unit tests for `correctionWeight`**

Add this group inside `void main() { ... }` in `apps/mobile/test/features/library/auto_color_enhancer_test.dart` (top level, sibling to the existing `group('AutoEnhancer', ...)`). The import `import 'package:mobile/features/library/auto_enhancer.dart';` already exists in the file.

```dart
  group('correctionWeight', () {
    test('is 0 for dark content at or below the paper floor', () {
      expect(correctionWeight(40), 0.0);
      expect(correctionWeight(95), 0.0);
    });
    test('is 1 for paper at or above floor + band', () {
      expect(correctionWeight(120), 1.0);
      expect(correctionWeight(240), 1.0);
    });
    test('ramps linearly across the transition band', () {
      // floor 95, band 25 → (107-95)/25 = 0.48
      expect(correctionWeight(107), closeTo(0.48, 0.02));
      expect(correctionWeight(95 + 25), 1.0);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name correctionWeight`
Expected: FAIL — `correctionWeight` is undefined (compile error).

- [ ] **Step 3: Add the consts, the function, and wire it into the divide**

In `apps/mobile/lib/features/library/auto_enhancer.dart`:

3a. Change the foundation import (line 4) from:
```dart
import 'package:flutter/foundation.dart' show compute;
```
to:
```dart
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
```

3b. After the `_kBlurRadius` const (line 19) add:
```dart
/// Background luminance at or below which a region is treated as dark content
/// (an embedded photo or filled block) and left uncorrected — so flat-field
/// division never blows it out to white. "Protect photos" bias: set high enough
/// that a genuine photo (background estimate ~40) is preserved while shadowed
/// paper (estimate typically >= ~110) is still fully corrected.
const int _kPaperFloor = 95;

/// Width of the smooth transition above [_kPaperFloor]. The correction weight
/// ramps 0 -> 1 across this band, avoiding hard seams / halos at content edges.
const int _kGateBand = 25;

/// Correction weight for a pixel whose local background luminance is
/// [backgroundLuminance]: 0.0 for dark content (<= [_kPaperFloor]), 1.0 for
/// paper (>= floor + [_kGateBand]), linear in between. Pure; exposed for tests.
@visibleForTesting
double correctionWeight(int backgroundLuminance) =>
    ((backgroundLuminance - _kPaperFloor) / _kGateBand).clamp(0.0, 1.0);
```

3c. Replace the whole `_divideByBackground` function (currently lines 106-122) with:
```dart
/// Flat-field correction, gated on background brightness. Where the local
/// background [bg] is bright (paper, even under shadow) the pixel is fully
/// divided so shadows flatten to white; where [bg] is genuinely dark (a photo
/// or filled block) the pixel is left untouched, so dark content is never blown
/// out. A smooth ramp between the two (see [correctionWeight]) prevents edge
/// seams. Channels scale proportionally, so hue is preserved. Guards bg == 0.
void _divideByBackground(img.Image src, img.Image bg) {
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final b = bg.getPixel(x, y).r.toInt();
      if (b <= 0) continue;
      final alpha = correctionWeight(b);
      if (alpha <= 0) continue; // dark content — leave the pixel untouched
      // alpha=1 -> multiply by 255/b (full divide); alpha=0 -> unchanged.
      final scale = 1 + alpha * (255 / b - 1);
      final px = src.getPixel(x, y);
      px.r = (px.r.toInt() * scale).clamp(0, 255).toInt();
      px.g = (px.g.toInt() * scale).clamp(0, 255).toInt();
      px.b = (px.b.toInt() * scale).clamp(0, 255).toInt();
    }
  }
}
```

- [ ] **Step 4: Run the unit tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name correctionWeight`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full enhancer file for regression**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart`
Expected: PASS — all existing tests still green, including the Task-1 shadow-gradient test (thin ink's background estimate is bright paper → alpha=1 → text-on-shadowed-paper still flattens) and the contrast-stretch / color-preservation / corrupt / EXIF / uniform / tiny-frame tests. If the shadow-gradient test regresses, do NOT weaken it — the gate must not fire on thin ink; investigate and report.

- [ ] **Step 6: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/lib/features/library/auto_enhancer.dart apps/mobile/test/features/library/auto_color_enhancer_test.dart
git commit -m "feat(auto): gate flat-field divide on background brightness

Add correctionWeight(b): 0 for dark content, 1 for paper, smooth ramp.
_divideByBackground blends original<->divided by it, so large dark
regions are no longer blown out while paper shadow removal is unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Photo-preservation behavioral test

Locks the end-to-end contract through the public `enhance` API: a large dark block is preserved AND surrounding shadowed paper still flattens. If Task 1's constants are slightly off for this case, tune `_kPaperFloor` / `_kGateBand` here (this is the real behavioral TDD loop).

**Files:**
- Test: `apps/mobile/test/features/library/auto_color_enhancer_test.dart`
- (Only if the test forces tuning) Modify: `apps/mobile/lib/features/library/auto_enhancer.dart` (`_kPaperFloor` / `_kGateBand` values only).

**Interfaces:**
- Consumes: `const AutoEnhancer().enhance(Uint8List) → Future<Uint8List>` (public API), the gate from Task 1.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing photo-preservation test**

Add this test inside the existing `group('AutoEnhancer', ...)` in `apps/mobile/test/features/library/auto_color_enhancer_test.dart`:

```dart
    test('preserves a large dark region (embedded photo) instead of blowing it '
        'out, while still flattening the surrounding shadowed paper', () async {
      const w = 200, h = 200;
      final src = img.Image(width: w, height: h);
      // Paper with a left-to-right shadow gradient: dark-left 150 .. lit-right 245.
      int bgVal(int x) => 150 + (x * 95 ~/ (w - 1));
      for (final px in src) {
        final v = bgVal(px.x);
        px..r = v..g = v..b = v;
      }
      // Large solid-dark block (an embedded photo), luminance ~40, 80x80 px.
      for (var y = 60; y < 140; y++) {
        for (var x = 60; x < 140; x++) {
          src.getPixel(x, y)..r = 40..g = 40..b = 40;
        }
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);
      final out = img.decodeImage(output)!;

      // Block interior must stay dark — NOT blown out to white.
      expect(out.getPixel(100, 100).luminance, lessThan(100),
          reason: 'large dark region (photo) must be preserved, not whitened');
      // Surrounding paper (incl. the shadowed left edge) still flattens to white.
      expect(out.getPixel(10, 100).luminance, greaterThan(220),
          reason: 'shadowed paper around the photo must still be flattened');
    });
```

- [ ] **Step 2: Run the test against the gated code**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart --plain-name "preserves a large dark region"`
Expected: PASS on the gated code (Task 1). This assertion is load-bearing: on the pre-gate code the block interior blew out to ~251 (verified during on-device-style verification), which is `> 100`, so the first assertion would have failed — the gate is what makes it pass. If it FAILS here, proceed to Step 3 to tune the constants (this is the real behavioral TDD loop).

- [ ] **Step 3: If the test fails on the gated code, tune the constants**

If `out.getPixel(100,100).luminance` is not `< 100` (block still lifting) → raise `_kPaperFloor` (e.g. 95→110) so more dark backgrounds are treated as content. If `out.getPixel(10,100).luminance` is not `> 220` (shadowed paper under-corrected) → lower `_kPaperFloor` or narrow `_kGateBand`. Change ONLY the two const values; re-run Step 2 and Task 1 Step 5 (full file) after any change. Do not weaken the assertions.

- [ ] **Step 4: Run the full enhancer file to confirm no regression**

Run: `cd apps/mobile && flutter test test/features/library/auto_color_enhancer_test.dart`
Expected: PASS — photo-preservation test green AND every prior test (shadow-gradient, contrast, color, corrupt, EXIF, uniform, tiny, correctionWeight) still green.

- [ ] **Step 5: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/test/features/library/auto_color_enhancer_test.dart apps/mobile/lib/features/library/auto_enhancer.dart
git commit -m "test(auto): photo preserved + paper still flattened (behavioral gate proof)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Photo-preservation BDD scenario

**Files:**
- Modify: `apps/mobile/integration_test/g3_auto_color.feature`
- Create: `apps/mobile/test/step/the_auto_enhancer_preserves_the_photo.dart`
- Regenerate: `apps/mobile/integration_test/g3_auto_color_test.dart` (build_runner)

**Interfaces:**
- Consumes: `g1Repo.lastSavedEnhancer` (set by the existing review-screen Given step when Accept is tapped), `AutoEnhancer.enhance`.
- Produces: BDD proof that selecting `Auto` in the UI preserves an embedded photo.

- [ ] **Step 1: Add the scenario to the feature file**

Append to `apps/mobile/integration_test/g3_auto_color.feature` (after the existing shadow scenario):

```gherkin
  Scenario: Auto filter preserves an embedded photo in a shadowed capture
    Given the review screen is open with a captured image
    When I toggle the auto filter
    And I tap Accept
    Then the auto enhancer preserves the photo
```

- [ ] **Step 2: Create the Then step**

Create `apps/mobile/test/step/the_auto_enhancer_preserves_the_photo.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/auto_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the auto enhancer preserves the photo
///
/// Verifies the enhancer the UI selected (recorded in [g1Repo.lastSavedEnhancer]
/// when Accept was tapped) does not blow out a large dark region: a synthetic
/// page with an 80x80 dark block must keep that block dark after enhancement,
/// while surrounding paper still brightens.
Future<void> theAutoEnhancerPreservesThePhoto(WidgetTester tester) async {
  final enhancer = g1Repo.lastSavedEnhancer;
  expect(enhancer, isA<AutoEnhancer>(),
      reason: 'UI must have selected AutoEnhancer');

  const w = 200, h = 200;
  final src = img.Image(width: w, height: h);
  for (final px in src) {
    px..r = 235..g = 235..b = 235; // bright paper
  }
  for (var y = 60; y < 140; y++) {
    for (var x = 60; x < 140; x++) {
      src.getPixel(x, y)..r = 40..g = 40..b = 40; // embedded photo
    }
  }
  final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

  final output = await enhancer!.enhance(input);
  final out = img.decodeImage(output)!;

  expect(out.getPixel(100, 100).luminance, lessThan(100),
      reason: 'embedded photo must be preserved, not blown out to white');
  expect(out.getPixel(10, 10).luminance, greaterThan(200),
      reason: 'paper around the photo must still be bright');
}
```

- [ ] **Step 3: Regenerate the integration test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: regenerates `integration_test/g3_auto_color_test.dart` with a `testWidgets` block wiring the new scenario to `theAutoEnhancerPreservesThePhoto` and importing the new step file. Confirm both are present in the generated file.

- [ ] **Step 4: Verify the new step compiles / analyzes clean**

Run: `cd apps/mobile && flutter analyze test/step/the_auto_enhancer_preserves_the_photo.dart integration_test/g3_auto_color_test.dart`
Expected: No issues found. (The integration suite runs on device/sim; the host `flutter test` run skips `integration_test/`.)

- [ ] **Step 5: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/mobile/integration_test/g3_auto_color.feature apps/mobile/integration_test/g3_auto_color_test.dart apps/mobile/test/step/the_auto_enhancer_preserves_the_photo.dart
git commit -m "test(g3): BDD scenario — Auto preserves an embedded photo

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: On-device verification

**Files:** none (manual verification + tuning).

- [ ] **Step 1: Build and run on Android device RZCY51D0T1K**

Run: `cd apps/mobile && flutter run -d RZCY51D0T1K`
Capture two documents: (a) a plain text page held so a hand-shadow falls across it; (b) a page containing a printed photo or a large filled-dark area. Apply `Auto` to each.

- [ ] **Step 2: Verify both outcomes**

Confirm on-device: (a) the text page still has its shadow removed and background white (no regression from the prior shadow feature); (b) the photo/dark block is preserved — natural, NOT blown out to white, and no bright halo at its border. Repeat on the iOS simulator for parity.

- [ ] **Step 3: Tune constants if needed**

If a real photo still washes out → raise `_kPaperFloor` (more backgrounds treated as content). If genuine paper-shadow is left too dark → lower `_kPaperFloor` or narrow `_kGateBand`. Change only the two const values; re-run Task 1 Step 5 + Task 2 Step 4 after any change, then re-verify on device. Commit any tuning with a message noting the device-observed reason.

- [ ] **Step 4: Report**

State plainly what was observed on each platform for both document types, and any constants tuned and why. Do not claim "done" while any gap remains open (per project rule: green gate ≠ done).

---

## Notes for the implementer

- `visibleForTesting` is re-exported by `package:flutter/foundation.dart` — add it to the existing `show` clause, no new import line.
- `correctionWeight` is public (annotated `@visibleForTesting`), so the test file imports it via the existing `import 'package:mobile/features/library/auto_enhancer.dart';`.
- Do not touch `_estimateBackground` / `_maxFilter` / `_autoLevels` — the gate is entirely inside `_divideByBackground` plus the two consts and the helper.
