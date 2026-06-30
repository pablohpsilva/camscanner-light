# G3 Color & Auto-Magic Filters — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new scan-enhancement filters — Color (gentle contrast lift) and Auto/Magic (per-channel auto-levels + saturation boost) — as strategy classes implementing `ImageEnhancer`, wired into `CaptureReviewScreen` as two new AppBar toggle buttons.

**Architecture:** Each filter is a const-constructible strategy class with a private top-level `compute()` isolate function — identical pattern to `GrayscaleEnhancer` (G1) and `BwEnhancer` (G2). `AutoEnhancer` runs a two-pass per-channel histogram stretch (1% clipping) then a saturation boost. `ColorEnhancer` calls `img.adjustColor()` with a contrast and brightness factor. `_EnhancerMode` enum gains `.auto` and `.color` variants; the Dart 3 exhaustive switch in the Accept handler gains two new arms.

**Tech Stack:** Flutter (Dart 3.12.2+), `image` 4.9.1 (already in pubspec — **do not add any dependency**), `flutter_test`, `bdd_widget_test` (already configured), `build_runner` (already configured).

## Global Constraints

- **JPEG output, quality 92** everywhere — `img.encodeJpg(src, quality: 92)`. Never PNG.
- **`compute()` isolate** for all CPU-bound work — the top-level `_autoFn` / `_colorFn` functions must be top-level (not closures or class methods) to be isolate-sendable.
- **`img.bakeOrientation(decoded)`** before any pixel processing (EXIF orientation safety). Positional first arg.
- **OCP**: `ImageEnhancer`, `NoneEnhancer`, `GrayscaleEnhancer`, `BwEnhancer`, `SaveController`, `DriftDocumentRepository`, `CameraScreen` must not be modified.
- **Error resilience**: any decode/process failure inside the isolate function → return `bytes` unchanged, never throw.
- **Const-constructible**: `const AutoEnhancer()`, `const ColorEnhancer()`.
- **`image` 4.9.1 API facts** (verified from source):
  - `img.bakeOrientation(decoded)` — positional arg, returns a new Image with EXIF baked in.
  - `img.adjustColor(src, {contrast, saturation, brightness, ...})` — mutates `src` in place AND returns `src`. `contrast: 1.1` = 10% boost; `brightness: 1.05` = 5% brighter (scalar, NOT offset — 0.0 = black, 1.0 = unchanged); `saturation: 1.15` = 15% boost.
  - `px.r`, `px.g`, `px.b` — readable as num (call `.toInt()` for histogram buckets); settable as int.
- **BDD step text**: use plain English only — no `&` characters (build_runner mangles `&` in generated function names). Use "auto" and "color" — not "Auto/Magic".
- **Working directory for all `flutter` commands**: `apps/mobile/`
- **Fixture file** for EXIF test (already in repo): `test/fixtures/landscape_exif6.jpg` (200×100 pixels, EXIF orientation=6 → decodes as portrait 100×200 after `bakeOrientation`).

---

## File Map

| Action | Path |
|--------|------|
| Create | `apps/mobile/lib/features/library/auto_enhancer.dart` |
| Create | `apps/mobile/lib/features/library/color_enhancer.dart` |
| Create | `apps/mobile/test/features/library/auto_color_enhancer_test.dart` |
| Modify | `apps/mobile/lib/features/scan/capture_review_screen.dart` |
| Create | `apps/mobile/test/features/scan/capture_review_screen_g3_test.dart` |
| Create | `apps/mobile/integration_test/g3_auto_color.feature` |
| Create (generated) | `apps/mobile/integration_test/g3_auto_color_test.dart` |
| Create | `apps/mobile/test/step/i_toggle_the_auto_filter.dart` |
| Create | `apps/mobile/test/step/the_document_is_saved_with_auto_enhancement.dart` |
| Create | `apps/mobile/test/step/i_toggle_the_color_filter.dart` |
| Create | `apps/mobile/test/step/the_document_is_saved_with_color_enhancement.dart` |
| Create | `scripts/verify/g3.sh` |

---

## Task 1: AutoEnhancer + ColorEnhancer strategy classes + unit tests

**Files:**
- Create: `apps/mobile/lib/features/library/auto_enhancer.dart`
- Create: `apps/mobile/lib/features/library/color_enhancer.dart`
- Create: `apps/mobile/test/features/library/auto_color_enhancer_test.dart`

**Interfaces:**
- Consumes: `ImageEnhancer` from `lib/features/library/image_enhancer.dart` (abstract interface class with `Future<Uint8List> enhance(Uint8List bytes)`)
- Produces:
  - `class AutoEnhancer implements ImageEnhancer { const AutoEnhancer(); }` — used by Task 2 switch arm
  - `class ColorEnhancer implements ImageEnhancer { const ColorEnhancer(); }` — used by Task 2 switch arm

- [ ] **Step 1: Write the failing unit tests**

Create `apps/mobile/test/features/library/auto_color_enhancer_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/auto_enhancer.dart';
import 'package:mobile/features/library/color_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';

void main() {
  group('AutoEnhancer', () {
    test('stretches contrast: max channel value reaches near-255 after enhancement', () async {
      // 4×4 image with compressed R range [80, 120] — after auto-levels max R → ~255.
      final src = img.Image(width: 4, height: 4);
      final rVals = [80, 93, 107, 120];
      int i = 0;
      for (final px in src) {
        px.r = rVals[i % 4];
        px.g = rVals[i % 4] - 20;
        px.b = rVals[i % 4] + 10;
        i++;
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);

      final decoded = img.decodeImage(output)!;
      int maxR = 0;
      for (final px in decoded) {
        if (px.r.toInt() > maxR) maxR = px.r.toInt();
      }
      expect(maxR, greaterThan(220),
          reason: 'Auto-levels should stretch R to near-255');
    });

    test('preserves color: output is not grayscale (R channel differs from G)', () async {
      // Half-red, half-green pixels — per-channel stretch preserves the relative difference.
      final src = img.Image(width: 4, height: 4);
      int i = 0;
      for (final px in src) {
        if (i < 8) { px.r = 200; px.g = 50; px.b = 50; }
        else        { px.r = 50;  px.g = 200; px.b = 50; }
        i++;
      }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);

      final decoded = img.decodeImage(output)!;
      bool hasColorVariation = false;
      for (final px in decoded) {
        if ((px.r.toInt() - px.g.toInt()).abs() > 30) {
          hasColorVariation = true;
          break;
        }
      }
      expect(hasColorVariation, isTrue,
          reason: 'AutoEnhancer must not convert image to grayscale');
    });

    test('returns bytes unchanged when decoding fails (corrupt data)', () async {
      final corrupt = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      final output = await const AutoEnhancer().enhance(corrupt);
      expect(output, same(corrupt));
    });

    test('bakes EXIF orientation: landscape_exif6 (200×100, orient=6) becomes portrait (100×200)',
        () async {
      final bytes = Uint8List.fromList(
          await File('test/fixtures/landscape_exif6.jpg').readAsBytes());
      final output = await const AutoEnhancer().enhance(bytes);
      final decoded = img.decodeImage(output)!;
      expect(decoded.width, 100);
      expect(decoded.height, 200);
    });

    test('uniform image (all same color) returns valid JPEG without crash', () async {
      final src = img.Image(width: 4, height: 4);
      for (final px in src) { px.r = 128; px.g = 128; px.b = 128; }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const AutoEnhancer().enhance(input);

      expect(img.decodeImage(output), isNotNull,
          reason: 'Uniform image must not crash; degenerate auto-levels should be a no-op');
    });
  });

  group('ColorEnhancer', () {
    test('preserves color: output is not grayscale (R channel differs from G)', () async {
      final src = img.Image(width: 4, height: 4);
      for (final px in src) { px.r = 180; px.g = 80; px.b = 60; }
      final input = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final output = await const ColorEnhancer().enhance(input);

      final decoded = img.decodeImage(output)!;
      bool allGrayscale = true;
      for (final px in decoded) {
        if ((px.r.toInt() - px.g.toInt()).abs() > 20) {
          allGrayscale = false;
          break;
        }
      }
      expect(allGrayscale, isFalse,
          reason: 'ColorEnhancer must not convert image to grayscale');
    });

    test('returns bytes unchanged when decoding fails (corrupt data)', () async {
      final corrupt = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      final output = await const ColorEnhancer().enhance(corrupt);
      expect(output, same(corrupt));
    });

    test('bakes EXIF orientation: landscape_exif6 (200×100, orient=6) becomes portrait (100×200)',
        () async {
      final bytes = Uint8List.fromList(
          await File('test/fixtures/landscape_exif6.jpg').readAsBytes());
      final output = await const ColorEnhancer().enhance(bytes);
      final decoded = img.decodeImage(output)!;
      expect(decoded.width, 100);
      expect(decoded.height, 200);
    });
  });

  group('NoneEnhancer (regression)', () {
    test('returns the exact same bytes object unchanged', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = await const NoneEnhancer().enhance(bytes);
      expect(identical(result, bytes), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests — verify they fail (classes not yet defined)**

```bash
cd apps/mobile
flutter test test/features/library/auto_color_enhancer_test.dart --no-pub
```

Expected: FAIL — `Target of URI doesn't exist: 'package:mobile/features/library/auto_enhancer.dart'`

- [ ] **Step 3: Implement `auto_enhancer.dart`**

Create `apps/mobile/lib/features/library/auto_enhancer.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';

/// Enhances a JPEG scan with per-channel auto-levels + saturation boost.
/// Whitens document backgrounds and pops contrast. Runs in a [compute]
/// isolate — never blocks the UI thread.
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
    // bakeOrientation: EXIF scrubber keeps the Orientation tag; encodeJpg
    // strips EXIF, so orientation must be baked into pixels first.
    final oriented = img.bakeOrientation(decoded);
    _autoLevels(oriented);                           // remove color casts, boost contrast
    img.adjustColor(oriented, saturation: 1.15);     // subtle saturation pop; mutates in place
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
  } catch (_) {
    return bytes;
  }
}

// Per-channel histogram auto-levels: clips 1% on each end, then stretches
// each channel to [0, 255]. Two-pass: first builds histograms, then applies
// the stretch. Degenerate (uniform) channels are left unchanged.
void _autoLevels(img.Image src) {
  final n = src.width * src.height;
  if (n == 0) return;
  final clip = ((n / 100).ceil()).clamp(1, n);

  // Pass 1: build per-channel histograms.
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

  // Pass 2: stretch each channel to [0, 255].
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

// Finds the 1%-clipped low and high histogram values (black and white points).
(int, int) _histClip(List<int> hist, int clip) {
  int lo = 0, cumLo = 0;
  while (lo < 255 && cumLo + hist[lo] < clip) { cumLo += hist[lo++]; }
  int hi = 255, cumHi = 0;
  while (hi > lo && cumHi + hist[hi] < clip) { cumHi += hist[hi--]; }
  return (lo, hi);
}
```

- [ ] **Step 4: Implement `color_enhancer.dart`**

Create `apps/mobile/lib/features/library/color_enhancer.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';

/// Enhances a color JPEG scan with a gentle contrast lift and brightness boost.
/// Keeps the image in full color. Runs in a [compute] isolate — never blocks
/// the UI thread.
class ColorEnhancer implements ImageEnhancer {
  const ColorEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_colorFn, bytes);
}

// Top-level function required by compute() (must be isolate-sendable).
Uint8List _colorFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    // bakeOrientation: EXIF scrubber keeps the Orientation tag; encodeJpg
    // strips EXIF, so orientation must be baked into pixels first.
    final oriented = img.bakeOrientation(decoded);
    // contrast: 1.1 = 10% boost (formula: r = 0.5*(1-c) + r*c, c=1.1).
    // brightness: 1.05 = 5% brighter (scalar multiplier; 1.0 = unchanged).
    img.adjustColor(oriented, contrast: 1.1, brightness: 1.05);
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
  } catch (_) {
    return bytes;
  }
}
```

- [ ] **Step 5: Run the unit tests — verify they pass**

```bash
cd apps/mobile
flutter test test/features/library/auto_color_enhancer_test.dart --no-pub
```

Expected: `+9: All tests passed!` (9 tests total — 5 AutoEnhancer, 3 ColorEnhancer, 1 NoneEnhancer regression)

If the test `'stretches contrast'` fails: the contrast test checks `maxR > 220` after auto-levels on a [80-120] input range. If it fails, verify `_autoLevels` is running before `img.adjustColor()`. If there's a `px.r = int_value` type error, replace with `px.rNormalized = v / 255.0`.

- [ ] **Step 6: Run analyze — verify clean**

```bash
cd apps/mobile
flutter analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd apps/mobile
git add lib/features/library/auto_enhancer.dart \
        lib/features/library/color_enhancer.dart \
        test/features/library/auto_color_enhancer_test.dart
git commit -m "feat(g3): AutoEnhancer (auto-levels + saturation) and ColorEnhancer (contrast lift)"
```

---

## Task 2: Review screen — Auto + Color toggles + widget tests

**Files:**
- Modify: `apps/mobile/lib/features/scan/capture_review_screen.dart`
- Create: `apps/mobile/test/features/scan/capture_review_screen_g3_test.dart`

**Interfaces:**
- Consumes:
  - `AutoEnhancer` from `lib/features/library/auto_enhancer.dart` (Task 1)
  - `ColorEnhancer` from `lib/features/library/color_enhancer.dart` (Task 1)
  - `_EnhancerMode` enum currently has `{ none, grayscale, bw }` — we extend it to `{ none, grayscale, bw, auto, color }`
  - `Key('review-accept')` — the Accept button already has this key; do not change it
- Produces: wired `onAccept` passes `AutoEnhancer()` / `ColorEnhancer()` to caller

- [ ] **Step 1: Write the failing widget tests**

Create `apps/mobile/test/features/scan/capture_review_screen_g3_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/auto_enhancer.dart';
import 'package:mobile/features/library/color_enhancer.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

Future<void> _pump(
  WidgetTester tester, {
  required void Function(CropCorners, ImageEnhancer) onAccept,
  bool saving = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/g3.jpg'),
      onRetake: () {},
      onAccept: onAccept,
      saving: saving,
      decodeImageSize: (_) async => const Size(100, 100),
      readBytes: (_) async => Uint8List(0),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Auto and Color toggle buttons are present in the AppBar',
      (tester) async {
    await _pump(tester, onAccept: (_, _) {});
    expect(find.byKey(const Key('auto-toggle')), findsOneWidget);
    expect(find.byKey(const Key('color-toggle')), findsOneWidget);
  });

  testWidgets('Tapping Auto changes its tooltip to "Auto on"', (tester) async {
    await _pump(tester, onAccept: (_, _) {});

    final before = tester.widget<IconButton>(find.byKey(const Key('auto-toggle')));
    expect(before.tooltip, equals('Auto off'));

    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();

    final after = tester.widget<IconButton>(find.byKey(const Key('auto-toggle')));
    expect(after.tooltip, equals('Auto on'));
  });

  testWidgets('Tapping Color changes its tooltip to "Color on"', (tester) async {
    await _pump(tester, onAccept: (_, _) {});

    final before = tester.widget<IconButton>(find.byKey(const Key('color-toggle')));
    expect(before.tooltip, equals('Color off'));

    await tester.tap(find.byKey(const Key('color-toggle')));
    await tester.pump();

    final after = tester.widget<IconButton>(find.byKey(const Key('color-toggle')));
    expect(after.tooltip, equals('Color on'));
  });

  testWidgets('Accept with Auto on calls onAccept with AutoEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<AutoEnhancer>());
  });

  testWidgets('Accept with Color on calls onAccept with ColorEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('color-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<ColorEnhancer>());
  });

  testWidgets('Tap Grayscale then Auto — only AutoEnhancer (mutual exclusion)',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<AutoEnhancer>(),
        reason: 'Tapping Auto must deactivate Grayscale');
  });

  testWidgets('Tap Auto then Color — only ColorEnhancer (mutual exclusion)',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('color-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<ColorEnhancer>(),
        reason: 'Tapping Color must deactivate Auto');
  });

  testWidgets('Tapping active Auto again deactivates it — NoneEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('auto-toggle'))); // deactivate
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<NoneEnhancer>(),
        reason: 'Tapping active Auto must toggle it off');
  });

  testWidgets('Tapping active Color again deactivates it — NoneEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('color-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('color-toggle'))); // deactivate
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<NoneEnhancer>(),
        reason: 'Tapping active Color must toggle it off');
  });

  testWidgets('Grayscale toggle still works after G3 (regression)',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<GrayscaleEnhancer>(),
        reason: 'Grayscale toggle must remain functional after G3 changes');
  });

  testWidgets('B&W toggle still works after G3 (regression)', (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    // BwEnhancer is not imported here, but we can verify by enum — just check
    // that b&w-toggle changes accept to something that is NOT NoneEnhancer.
    await tester.tap(find.byKey(const Key('bw-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isNot(isA<NoneEnhancer>()),
        reason: 'B&W toggle must remain functional after G3 changes');
  });
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd apps/mobile
flutter test test/features/scan/capture_review_screen_g3_test.dart --no-pub
```

Expected: FAIL — `Key('auto-toggle')` not found (buttons not yet added).

- [ ] **Step 3: Modify `capture_review_screen.dart`**

In `apps/mobile/lib/features/scan/capture_review_screen.dart`, make the following four changes. Read the existing file first to confirm the current content, then apply each change:

**Change 1 — Add imports** (after the existing `bw_enhancer.dart` import):

```dart
import '../library/auto_enhancer.dart';
import '../library/color_enhancer.dart';
```

**Change 2 — Extend the `_EnhancerMode` enum** (currently at the top of the file, before the class):

Replace:
```dart
enum _EnhancerMode { none, grayscale, bw }
```
With:
```dart
enum _EnhancerMode { none, grayscale, bw, auto, color }
```

**Change 3 — Add two new IconButtons to AppBar actions** (append after the existing `bw-toggle` IconButton, inside the `actions: [...]` list):

```dart
          // Auto/Magic — per-channel auto-levels + saturation boost
          IconButton(
            key: const Key('auto-toggle'),
            icon: Icon(
              Icons.auto_fix_high,
              color: _mode == _EnhancerMode.auto
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: _mode == _EnhancerMode.auto ? 'Auto on' : 'Auto off',
            onPressed: () => setState(() => _mode =
                _mode == _EnhancerMode.auto
                    ? _EnhancerMode.none
                    : _EnhancerMode.auto),
          ),
          // Color — gentle contrast lift, full-color output
          IconButton(
            key: const Key('color-toggle'),
            icon: Icon(
              Icons.color_lens,
              color: _mode == _EnhancerMode.color
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: _mode == _EnhancerMode.color ? 'Color on' : 'Color off',
            onPressed: () => setState(() => _mode =
                _mode == _EnhancerMode.color
                    ? _EnhancerMode.none
                    : _EnhancerMode.color),
          ),
```

**Change 4 — Update the Dart 3 exhaustive switch in the Accept button** (in the `onPressed` handler — the switch that selects the enhancer):

Replace the existing switch:
```dart
switch (_mode) {
  _EnhancerMode.grayscale => const GrayscaleEnhancer(),
  _EnhancerMode.bw        => const BwEnhancer(),
  _EnhancerMode.none      => const NoneEnhancer(),
},
```
With:
```dart
switch (_mode) {
  _EnhancerMode.grayscale => const GrayscaleEnhancer(),
  _EnhancerMode.bw        => const BwEnhancer(),
  _EnhancerMode.auto      => const AutoEnhancer(),
  _EnhancerMode.color     => const ColorEnhancer(),
  _EnhancerMode.none      => const NoneEnhancer(),
},
```

- [ ] **Step 4: Run widget tests — verify they pass**

```bash
cd apps/mobile
flutter test test/features/scan/capture_review_screen_g3_test.dart --no-pub
```

Expected: `+11: All tests passed!`

- [ ] **Step 5: Run full unit test suite — verify no regressions**

```bash
cd apps/mobile
flutter test --no-pub
```

Expected: some OpenCV tests fail (pre-existing; unrelated to this change), all other tests pass. Specifically, `test/features/library/` and `test/features/scan/` must all pass.

- [ ] **Step 6: Run analyze — verify clean**

```bash
cd apps/mobile
flutter analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/scan/capture_review_screen.dart \
        apps/mobile/test/features/scan/capture_review_screen_g3_test.dart
git commit -m "feat(g3): Auto and Color toggles on review screen; _EnhancerMode enum extended"
```

---

## Task 3: BDD scenarios + step definitions + verify script

**Files:**
- Create: `apps/mobile/integration_test/g3_auto_color.feature`
- Create (generated): `apps/mobile/integration_test/g3_auto_color_test.dart`
- Create: `apps/mobile/test/step/i_toggle_the_auto_filter.dart`
- Create: `apps/mobile/test/step/the_document_is_saved_with_auto_enhancement.dart`
- Create: `apps/mobile/test/step/i_toggle_the_color_filter.dart`
- Create: `apps/mobile/test/step/the_document_is_saved_with_color_enhancement.dart`
- Create: `scripts/verify/g3.sh`

**Interfaces:**
- Consumes:
  - `g1Repo` (FakeDocumentRepository) and `theReviewScreenIsOpenWithACapturedImage` from `test/step/the_review_screen_is_open_with_a_captured_image.dart` (already exists — do not modify)
  - `iTapAccept` from `test/step/i_tap_accept.dart` (already exists — do not modify; if it doesn't exist, the `And I tap Accept` step will be auto-generated as a stub in the .feature — check first with `ls test/step/`)
  - `theDocumentIsSavedWithoutEnhancement` from `test/step/the_document_is_saved_without_enhancement.dart` (already exists — do not modify)
  - `AutoEnhancer` from `lib/features/library/auto_enhancer.dart` (Task 1)
  - `ColorEnhancer` from `lib/features/library/color_enhancer.dart` (Task 1)

**Important: BDD step names must use plain English only — no `&` characters in any step text.** The step function name for "I toggle the auto filter" will be `iToggleTheAutoFilter`, and for "I toggle the color filter" will be `iToggleTheColorFilter`.

- [ ] **Step 1: Check which step definitions already exist**

```bash
ls apps/mobile/test/step/
```

Note: `the_review_screen_is_open_with_a_captured_image.dart`, `the_document_is_saved_without_enhancement.dart`, and `i_tap_accept.dart` must all be present. Do not recreate them.

- [ ] **Step 2: Create the Gherkin feature file**

Create `apps/mobile/integration_test/g3_auto_color.feature`:

```gherkin
Feature: G3 Color and Auto scan enhancement

  Scenario: Auto filter applied — document saved with auto enhancement
    Given the review screen is open with a captured image
    When I toggle the auto filter
    And I tap Accept
    Then the document is saved with auto enhancement

  Scenario: Color filter applied — document saved with color enhancement
    Given the review screen is open with a captured image
    When I toggle the color filter
    And I tap Accept
    Then the document is saved with color enhancement

  Scenario: No filter — document saved without enhancement
    Given the review screen is open with a captured image
    When I tap Accept
    Then the document is saved without enhancement
```

- [ ] **Step 3: Create the new step definitions**

Create `apps/mobile/test/step/i_toggle_the_auto_filter.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the auto filter
Future<void> iToggleTheAutoFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('auto-toggle')));
  await tester.pump();
}
```

Create `apps/mobile/test/step/the_document_is_saved_with_auto_enhancement.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/auto_enhancer.dart';

import '../step/the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the document is saved with auto enhancement
Future<void> theDocumentIsSavedWithAutoEnhancement(WidgetTester tester) async {
  expect(g1Repo.lastSavedEnhancer, isA<AutoEnhancer>(),
      reason: 'expected AutoEnhancer to have been passed to onAccept');
}
```

Create `apps/mobile/test/step/i_toggle_the_color_filter.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the color filter
Future<void> iToggleTheColorFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('color-toggle')));
  await tester.pump();
}
```

Create `apps/mobile/test/step/the_document_is_saved_with_color_enhancement.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/color_enhancer.dart';

import '../step/the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the document is saved with color enhancement
Future<void> theDocumentIsSavedWithColorEnhancement(WidgetTester tester) async {
  expect(g1Repo.lastSavedEnhancer, isA<ColorEnhancer>(),
      reason: 'expected ColorEnhancer to have been passed to onAccept');
}
```

- [ ] **Step 4: Generate the BDD test file from the feature file**

```bash
cd apps/mobile
dart run build_runner build --delete-conflicting-outputs
```

Expected: generates `integration_test/g3_auto_color_test.dart`. Verify it was created:

```bash
ls integration_test/g3_auto_color_test.dart
```

Open the generated file and confirm:
- It imports the 4 new step definitions
- It contains the function name `theReviewScreenIsOpenWithACapturedImage` (used to verify generation in g3.sh)
- If any step is missing (build_runner generates a stub with `// TODO: implement`), wire it to the correct step def manually.

- [ ] **Step 5: Run the full host test suite one final time**

```bash
cd apps/mobile
flutter test --no-pub
```

Expected: all non-OpenCV tests pass. Note the total number of passing tests (should be ≥ previous count + 9 unit + 11 widget).

- [ ] **Step 6: Create the verify script**

Create `scripts/verify/g3.sh` at the **repository root** (not inside apps/mobile):

```bash
#!/usr/bin/env bash
# Verify G3 (Color & Auto-Magic filters) acceptance criteria.
# Run from repository root: bash scripts/verify/g3.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== G3 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "AutoEnhancer class exists" \
  "apps/mobile/lib/features/library/auto_enhancer.dart" \
  "class AutoEnhancer"

assert_file_has "ColorEnhancer class exists" \
  "apps/mobile/lib/features/library/color_enhancer.dart" \
  "class ColorEnhancer"

assert_file_has "_autoLevels function present in AutoEnhancer" \
  "apps/mobile/lib/features/library/auto_enhancer.dart" \
  "_autoLevels"

assert_file_has "bakeOrientation called in AutoEnhancer" \
  "apps/mobile/lib/features/library/auto_enhancer.dart" \
  "bakeOrientation"

assert_file_has "compute() used in AutoEnhancer (off UI thread)" \
  "apps/mobile/lib/features/library/auto_enhancer.dart" \
  "compute"

assert_file_has "bakeOrientation called in ColorEnhancer" \
  "apps/mobile/lib/features/library/color_enhancer.dart" \
  "bakeOrientation"

assert_file_has "compute() used in ColorEnhancer (off UI thread)" \
  "apps/mobile/lib/features/library/color_enhancer.dart" \
  "compute"

assert_file_has "auto-toggle key present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "auto-toggle"

assert_file_has "color-toggle key present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "color-toggle"

assert_file_has "_EnhancerMode.auto present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "_EnhancerMode.auto"

assert_file_has "_EnhancerMode.color present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "_EnhancerMode.color"

assert_file_has "AutoEnhancer wired in review screen accept" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "AutoEnhancer"

assert_file_has "ColorEnhancer wired in review screen accept" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "ColorEnhancer"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/g3_auto_color.feature" \
  "Auto scan enhancement"

assert_file_has "BDD test file is generated" \
  "apps/mobile/integration_test/g3_auto_color_test.dart" \
  "theReviewScreenIsOpenWithACapturedImage"

# ---- OpenCV host library (scan tests in shared suite need it) ----
bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

# ---- Host tests + analyze + coverage ----
assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device gate (BDD integration test) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android g3_auto_color_test.dart
verify_integration_ios g3_auto_color_test.dart

verify_summary
```

Make the script executable:
```bash
chmod +x scripts/verify/g3.sh
```

- [ ] **Step 7: Run the verify script (host-only)**

```bash
VERIFY_SKIP_DEVICE=1 bash scripts/verify/g3.sh
```

Expected: all static assertions PASS, host tests PASS, analyze PASS, coverage ≥ 70%, and one FAIL line for `DEVICE CHECKS SKIPPED` (intentional — device gate requires a connected device).

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/integration_test/g3_auto_color.feature \
        apps/mobile/integration_test/g3_auto_color_test.dart \
        apps/mobile/test/step/i_toggle_the_auto_filter.dart \
        apps/mobile/test/step/the_document_is_saved_with_auto_enhancement.dart \
        apps/mobile/test/step/i_toggle_the_color_filter.dart \
        apps/mobile/test/step/the_document_is_saved_with_color_enhancement.dart \
        scripts/verify/g3.sh
git commit -m "test(g3): BDD scenarios + step defs + verify script"
```

---

## Self-Review

**Spec coverage check:**
- ✅ `AutoEnhancer` in `lib/features/library/auto_enhancer.dart` — Task 1
- ✅ `ColorEnhancer` in `lib/features/library/color_enhancer.dart` — Task 1
- ✅ `_autoLevels` private top-level function — Task 1
- ✅ Per-channel auto-levels, runs off UI thread, bakes EXIF — Task 1 unit tests
- ✅ Error resilience: corrupt bytes → unchanged, no throw — Task 1 unit tests
- ✅ `Key('auto-toggle')` and `Key('color-toggle')` in AppBar — Task 2 widget tests
- ✅ All five modes mutually exclusive via enum — Task 2 widget tests
- ✅ Accept with Auto → `AutoEnhancer`, Color → `ColorEnhancer`, off → `NoneEnhancer` — Task 2 widget tests
- ✅ G1/G2 regression tests — Task 2
- ✅ BDD scenarios (Auto, Color, no filter) — Task 3
- ✅ Step defs (4 new) — Task 3
- ✅ Verify script with 14 static assertions + host + analyze + coverage + device gate — Task 3
- ✅ OCP: no modifications to `ImageEnhancer`, `NoneEnhancer`, `GrayscaleEnhancer`, `BwEnhancer`, `SaveController`, `DriftDocumentRepository`, `CameraScreen`
