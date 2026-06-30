# G4 Filter Picker UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four AppBar icon toggle buttons with a horizontally scrollable filter picker strip (live thumbnails, Auto default) and extract `_EnhancerMode` as the public `EnhancerMode` enum.

**Architecture:** A new `FilterPickerStrip` stateful widget (in `lib/features/scan/widgets/`) generates thumbnails from a downsampled copy of the image using `compute()` + `Future.wait`, then calls `onModeChanged` on tap. `CaptureReviewScreen` reads bytes in `initState`, removes its four AppBar buttons, wraps its body `Stack` in a `Column`, and inserts the strip at the bottom. The private `_EnhancerMode` enum is extracted to the public `EnhancerMode` in `lib/features/library/enhancer_mode.dart` so both files can share it. Existing G1/G2/G3 BDD step defs are updated to tap the new tile keys instead of the removed toggle-button keys.

**Tech Stack:** Flutter/Dart 3.12.2+, `image` 4.9.1 (no new dependencies), `flutter_test`, `bdd_widget_test`, `build_runner`.

## Global Constraints

- **JPEG quality 85** for thumbnails (display-only); JPEG quality 92 for saved images — unchanged everywhere else.
- **`compute()` isolate** for `_thumbFn` (top-level function, not a closure or class method).
- **`img.bakeOrientation(decoded)`** before any pixel processing in `_thumbFn`.
- **OCP**: `ImageEnhancer`, `NoneEnhancer`, `GrayscaleEnhancer`, `BwEnhancer`, `AutoEnhancer`, `ColorEnhancer`, `SaveController`, `DriftDocumentRepository`, `CameraScreen` must not be modified.
- **Error resilience**: any thumbnail failure → that tile shows its icon placeholder; no crash.
- **`image` 4.9.1 API**: `img.copyResize(src, width: w, height: h)` — both named args; `img.bakeOrientation(decoded)` — positional; `img.encodeJpg(img, quality: 85)` — quality 85 for thumbnails.
- **Working directory for flutter commands**: `apps/mobile/`
- **Fixture**: `test/fixtures/landscape_exif6.jpg` (200×100, EXIF orient=6 → 100×200 after bake).

---

## File Map

| Action | Path |
|--------|------|
| **Create** | `apps/mobile/lib/features/library/enhancer_mode.dart` |
| **Create** | `apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart` |
| **Create** | `apps/mobile/test/features/scan/widgets/filter_picker_strip_test.dart` |
| **Modify** | `apps/mobile/lib/features/scan/capture_review_screen.dart` |
| **Delete** | `apps/mobile/test/features/scan/capture_review_screen_g1_test.dart` |
| **Delete** | `apps/mobile/test/features/scan/capture_review_screen_g2_test.dart` |
| **Delete** | `apps/mobile/test/features/scan/capture_review_screen_g3_test.dart` |
| **Create** | `apps/mobile/test/features/scan/capture_review_screen_g4_test.dart` |
| **Modify** | `apps/mobile/test/step/i_toggle_the_grayscale_filter.dart` |
| **Modify** | `apps/mobile/test/step/i_toggle_the_black_and_white_filter.dart` |
| **Modify** | `apps/mobile/test/step/i_toggle_the_auto_filter.dart` |
| **Modify** | `apps/mobile/test/step/i_toggle_the_color_filter.dart` |
| **Create** | `apps/mobile/integration_test/g4_filter_picker.feature` |
| **Create (generated)** | `apps/mobile/integration_test/g4_filter_picker_test.dart` |
| **Create** | `apps/mobile/test/step/i_see_the_filter_picker_strip.dart` |
| **Create** | `apps/mobile/test/step/i_tap_the_grayscale_filter_tile.dart` |
| **Create** | `apps/mobile/test/step/i_tap_the_original_filter_tile.dart` |
| **Create** | `scripts/verify/g4.sh` |

---

## Task 1: `EnhancerMode` enum + `FilterPickerStrip` widget + tests

**Files:**
- Create: `apps/mobile/lib/features/library/enhancer_mode.dart`
- Create: `apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart`
- Create: `apps/mobile/test/features/scan/widgets/filter_picker_strip_test.dart`

**Interfaces:**
- Consumes:
  - `ImageEnhancer`, `NoneEnhancer` from `lib/features/library/image_enhancer.dart`
  - `AutoEnhancer` from `lib/features/library/auto_enhancer.dart`
  - `BwEnhancer` from `lib/features/library/bw_enhancer.dart`
  - `ColorEnhancer` from `lib/features/library/color_enhancer.dart`
  - `GrayscaleEnhancer` from `lib/features/library/grayscale_enhancer.dart`
- Produces:
  - `enum EnhancerMode { none, grayscale, bw, auto, color }` in `enhancer_mode.dart`
  - `class FilterPickerStrip extends StatefulWidget` — used by Task 2

---

- [ ] **Step 1: Write the failing widget tests**

Create `apps/mobile/test/features/scan/widgets/filter_picker_strip_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/scan/widgets/filter_picker_strip.dart';

Future<void> _pump(
  WidgetTester tester, {
  EnhancerMode selectedMode = EnhancerMode.auto,
  void Function(EnhancerMode)? onModeChanged,
  Uint8List? sourceBytes,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FilterPickerStrip(
        selectedMode: selectedMode,
        onModeChanged: onModeChanged ?? (_) {},
        sourceBytes: sourceBytes,
      ),
    ),
  ));
}

void main() {
  group('FilterPickerStrip', () {
    testWidgets('shows all five filter tiles when sourceBytes is null',
        (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('filter-tile-auto')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-original')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-color')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-grayscale')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-bw')), findsOneWidget);
    });

    testWidgets('tapping Grayscale tile calls onModeChanged with .grayscale',
        (tester) async {
      EnhancerMode? captured;
      await _pump(tester, onModeChanged: (m) => captured = m);

      await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
      await tester.pump();

      expect(captured, EnhancerMode.grayscale);
    });

    testWidgets(
        'tapping Original tile calls onModeChanged with .none (no enhancement)',
        (tester) async {
      EnhancerMode? captured;
      await _pump(tester, onModeChanged: (m) => captured = m);

      await tester.tap(find.byKey(const Key('filter-tile-original')));
      await tester.pump();

      expect(captured, EnhancerMode.none);
    });

    testWidgets('selected tile has a border decoration', (tester) async {
      await _pump(tester, selectedMode: EnhancerMode.grayscale);

      final container = tester
          .widget<Container>(find.byKey(const Key('filter-tile-grayscale')));
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.border, isNotNull,
          reason: 'Selected tile must have a border');
    });

    testWidgets('unselected tile has no border', (tester) async {
      await _pump(tester, selectedMode: EnhancerMode.auto);

      final container =
          tester.widget<Container>(find.byKey(const Key('filter-tile-bw')));
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.border, isNull,
          reason: 'Unselected tile must not have a border');
    });

    testWidgets('does not crash when sourceBytes is corrupt', (tester) async {
      final corrupt = Uint8List.fromList([0, 1, 2, 3, 99]);
      await _pump(tester, sourceBytes: corrupt);
      await tester.pumpAndSettle();
      // All 5 tiles still present after failed generation
      expect(find.byKey(const Key('filter-tile-auto')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-bw')), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
cd apps/mobile
flutter test test/features/scan/widgets/filter_picker_strip_test.dart --no-pub
```

Expected: FAIL — `Target of URI doesn't exist: 'package:mobile/features/library/enhancer_mode.dart'`

- [ ] **Step 3: Create `enhancer_mode.dart`**

Create `apps/mobile/lib/features/library/enhancer_mode.dart`:

```dart
/// Enhancement filter modes for the scan pipeline.
enum EnhancerMode { none, grayscale, bw, auto, color }
```

- [ ] **Step 4: Create `filter_picker_strip.dart`**

Create `apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../library/auto_enhancer.dart';
import '../../library/bw_enhancer.dart';
import '../../library/color_enhancer.dart';
import '../../library/enhancer_mode.dart';
import '../../library/grayscale_enhancer.dart';
import '../../library/image_enhancer.dart';

// Top-level: downsample to ≤150 px wide for thumbnail generation.
// Called via compute() — must be top-level, not a closure.
// Returns JPEG bytes (quality 85, display-only) or null on any failure.
Uint8List? _thumbFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final w = oriented.width > 150 ? 150 : oriented.width;
    final h = (w * oriented.height / oriented.width).round();
    final small = img.copyResize(oriented, width: w, height: h);
    return Uint8List.fromList(img.encodeJpg(small, quality: 85));
  } catch (_) {
    return null;
  }
}

// Fixed display order: Auto first (it's the default), then Original, Color,
// Grayscale, B&W. Each entry is (mode, display label, fallback icon, tile key).
final _kFilters = [
  (
    mode: EnhancerMode.auto,
    label: 'Auto',
    icon: Icons.auto_fix_high,
    tileKey: 'filter-tile-auto',
  ),
  (
    mode: EnhancerMode.none,
    label: 'Original',
    icon: Icons.image_outlined,
    tileKey: 'filter-tile-original',
  ),
  (
    mode: EnhancerMode.color,
    label: 'Color',
    icon: Icons.color_lens_outlined,
    tileKey: 'filter-tile-color',
  ),
  (
    mode: EnhancerMode.grayscale,
    label: 'Grayscale',
    icon: Icons.filter_b_and_w_outlined,
    tileKey: 'filter-tile-grayscale',
  ),
  (
    mode: EnhancerMode.bw,
    label: 'B&W',
    icon: Icons.contrast,
    tileKey: 'filter-tile-bw',
  ),
];

class FilterPickerStrip extends StatefulWidget {
  final EnhancerMode selectedMode;
  final void Function(EnhancerMode) onModeChanged;
  final Uint8List? sourceBytes;

  const FilterPickerStrip({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
    this.sourceBytes,
  });

  @override
  State<FilterPickerStrip> createState() => _FilterPickerStripState();
}

class _FilterPickerStripState extends State<FilterPickerStrip> {
  Map<EnhancerMode, Uint8List?> _thumbs = {};
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _maybeGenerate(widget.sourceBytes);
  }

  @override
  void didUpdateWidget(FilterPickerStrip old) {
    super.didUpdateWidget(old);
    // Trigger generation the first time sourceBytes becomes available.
    if (old.sourceBytes == null && widget.sourceBytes != null) {
      _maybeGenerate(widget.sourceBytes);
    }
  }

  Future<void> _maybeGenerate(Uint8List? bytes) async {
    if (_generating || bytes == null || bytes.isEmpty) return;
    _generating = true;

    // Step 1: downsample in a compute isolate (avoids blocking UI thread).
    final small = await compute(_thumbFn, bytes);
    if (!mounted || small == null) {
      _generating = false;
      return;
    }

    // Step 2: apply all 5 enhancers concurrently on the downsampled bytes.
    final results = await Future.wait([
      const AutoEnhancer().enhance(small),
      const NoneEnhancer().enhance(small),
      const ColorEnhancer().enhance(small),
      const GrayscaleEnhancer().enhance(small),
      const BwEnhancer().enhance(small),
    ]);

    if (!mounted) return;
    setState(() {
      _thumbs = {
        EnhancerMode.auto:      results[0],
        EnhancerMode.none:      results[1],
        EnhancerMode.color:     results[2],
        EnhancerMode.grayscale: results[3],
        EnhancerMode.bw:        results[4],
      };
    });
    _generating = false;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: 100,
      color: Colors.black,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: _kFilters.map((f) {
          final isSelected = f.mode == widget.selectedMode;
          final thumb = _thumbs[f.mode];
          return GestureDetector(
            onTap: () => widget.onModeChanged(f.mode),
            child: Container(
              key: Key(f.tileKey),
              width: 68,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: isSelected
                    ? Border.all(color: primary, width: 2)
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 52,
                    height: 68,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: thumb != null
                          ? Image.memory(thumb, fit: BoxFit.cover)
                          : _generating
                              ? const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : Icon(f.icon, size: 28, color: Colors.white54),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    f.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? Colors.white : Colors.white60,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests — verify they pass**

```bash
cd apps/mobile
flutter test test/features/scan/widgets/filter_picker_strip_test.dart --no-pub
```

Expected: `+6: All tests passed!`

If the "selected tile has a border" test fails: `tester.widget<Container>(find.byKey(const Key('filter-tile-grayscale')))` may not work if `find.byKey` returns multiple Containers (the `Column` inside has a Container too). Fix: use `find.byKey(const Key('filter-tile-grayscale')).first` or wrap the check in `find.descendant`.

- [ ] **Step 6: Run analyze**

```bash
cd apps/mobile
flutter analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/enhancer_mode.dart \
        apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart \
        apps/mobile/test/features/scan/widgets/filter_picker_strip_test.dart
git commit -m "feat(g4): FilterPickerStrip widget with live thumbnails; EnhancerMode public enum"
```

---

## Task 2: Modify `CaptureReviewScreen` + replace G1-G3 widget tests + update step defs

**Files:**
- Modify: `apps/mobile/lib/features/scan/capture_review_screen.dart`
- Delete: `apps/mobile/test/features/scan/capture_review_screen_g1_test.dart`
- Delete: `apps/mobile/test/features/scan/capture_review_screen_g2_test.dart`
- Delete: `apps/mobile/test/features/scan/capture_review_screen_g3_test.dart`
- Create: `apps/mobile/test/features/scan/capture_review_screen_g4_test.dart`
- Modify: `apps/mobile/test/step/i_toggle_the_grayscale_filter.dart`
- Modify: `apps/mobile/test/step/i_toggle_the_black_and_white_filter.dart`
- Modify: `apps/mobile/test/step/i_toggle_the_auto_filter.dart`
- Modify: `apps/mobile/test/step/i_toggle_the_color_filter.dart`

**Interfaces:**
- Consumes: `EnhancerMode` from Task 1, `FilterPickerStrip` from Task 1
- Produces: `CaptureReviewScreen` with `_mode = EnhancerMode.auto` default, `FilterPickerStrip` embedded, four old toggle buttons removed

**Why the G1/G2/G3 widget test files are deleted:** Those tests use `Key('grayscale-toggle')`, `Key('bw-toggle')`, `Key('auto-toggle')`, `Key('color-toggle')` which are removed in this task. The G4 test file replaces them with comprehensive tile-based coverage.

**Why the existing step defs are modified:** The G1/G2/G3 BDD integration tests call `iToggleTheGrayscaleFilter()` etc., which currently tap the old toggle keys. After G4 removes those buttons, the BDD tests would fail. Updating the step defs to tap the filter tile keys keeps the BDD tests green with no Gherkin changes.

---

- [ ] **Step 1: Write the failing G4 widget tests**

Create `apps/mobile/test/features/scan/capture_review_screen_g4_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/auto_enhancer.dart';
import 'package:mobile/features/library/bw_enhancer.dart';
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
      image: const CapturedImage('/nonexistent/g4.jpg'),
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
  testWidgets('filter-picker-strip is present in the review screen',
      (tester) async {
    await _pump(tester, onAccept: (_, e) {});
    expect(find.byKey(const Key('filter-picker-strip')), findsOneWidget);
  });

  testWidgets('old AppBar toggle keys are absent', (tester) async {
    await _pump(tester, onAccept: (_, e) {});
    expect(find.byKey(const Key('grayscale-toggle')), findsNothing);
    expect(find.byKey(const Key('bw-toggle')), findsNothing);
    expect(find.byKey(const Key('auto-toggle')), findsNothing);
    expect(find.byKey(const Key('color-toggle')), findsNothing);
  });

  testWidgets(
      'default mode is Auto — Accept without tile tap passes AutoEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<AutoEnhancer>(),
        reason: 'Auto is the default — no tile tap needed');
  });

  testWidgets('tapping Original tile then Accept passes NoneEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('filter-tile-original')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<NoneEnhancer>());
  });

  testWidgets('tapping Grayscale tile then Accept passes GrayscaleEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<GrayscaleEnhancer>());
  });

  testWidgets('tapping B&W tile then Accept passes BwEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('filter-tile-bw')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<BwEnhancer>());
  });

  testWidgets('tapping Color tile then Accept passes ColorEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('filter-tile-color')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<ColorEnhancer>());
  });

  testWidgets('tapping Auto tile then Accept passes AutoEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('filter-tile-original')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-tile-auto')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<AutoEnhancer>());
  });

  testWidgets('saving: true shows spinner and disables Accept', (tester) async {
    await _pump(tester, onAccept: (_, e) {}, saving: true);

    expect(find.byKey(const Key('review-saving')), findsOneWidget);
    final btn = tester
        .widget<FilledButton>(find.byKey(const Key('review-accept')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Retake button still present (regression)', (tester) async {
    await _pump(tester, onAccept: (_, e) {});
    expect(find.byKey(const Key('review-retake')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the new test file — verify it fails**

```bash
cd apps/mobile
flutter test test/features/scan/capture_review_screen_g4_test.dart --no-pub
```

Expected: FAIL — `Key('filter-picker-strip')` not found (not yet wired in `CaptureReviewScreen`).

- [ ] **Step 3: Modify `capture_review_screen.dart`**

Read the file first to confirm line numbers, then apply the following four changes:

**Change 1 — Add two imports and remove the private enum declaration:**

In the import block, add (after the existing `bw_enhancer.dart` import):
```dart
import '../library/enhancer_mode.dart';
```

And (after the existing `crop_overlay.dart` import):
```dart
import 'widgets/filter_picker_strip.dart';
```

Delete the private enum declaration (currently line 35):
```dart
enum _EnhancerMode { none, grayscale, bw, auto, color }
```

**Change 2 — Replace all `_EnhancerMode` with `EnhancerMode` throughout the file:**

Every occurrence of `_EnhancerMode` becomes `EnhancerMode`. This covers:
- The state field declaration (change `_EnhancerMode _mode = _EnhancerMode.none;` → `EnhancerMode _mode = EnhancerMode.auto;` — note: also change `.none` to `.auto` here)
- All `setState(() => _mode = _EnhancerMode.xxx ? ...` references (there are 4 of these — delete the whole AppBar `actions` block in Change 3 instead)
- The switch arms in the Accept button

**Change 3 — Remove four AppBar IconButtons:**

Remove the entire `actions: [...]` list from the AppBar. The AppBar becomes title-only:
```dart
appBar: AppBar(
  title: const Text('Review'),
),
```

(Delete the 4 IconButton widgets and the `actions:` key entirely.)

**Change 4 — Add `_sourceBytes` field and initState read; wrap body in Column with FilterPickerStrip:**

Add after `bool _userInteracted = false;`:
```dart
Uint8List? _sourceBytes;
```

In `initState()`, add a second async read (the existing `decodeImageSize` call stays):
```dart
widget.readBytes(widget.image.path).then((b) {
  if (!mounted) return;
  setState(() => _sourceBytes = b);
}).catchError((_) {});
```

Replace the `body:` Stack with a Column:
```dart
body: Column(
  children: [
    Expanded(
      child: Stack(
        children: [
          ColoredBox(
            color: Colors.black,
            child: SizedBox.expand(
              child: size == null
                  ? Center(child: _imageWidget())
                  : CropOverlay(
                      imageSize: size,
                      image: _imageWidget(),
                      corners: _corners,
                      enabled: !widget.saving,
                      highlightColor: _highlightColor,
                      onCornersChanged: (c) => setState(() {
                        _userInteracted = true;
                        _corners = c;
                      }),
                    ),
            ),
          ),
          if (widget.saving)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                    child:
                        CircularProgressIndicator(key: Key('review-saving'))),
              ),
            ),
        ],
      ),
    ),
    FilterPickerStrip(
      key: const Key('filter-picker-strip'),
      selectedMode: _mode,
      onModeChanged: (m) => setState(() => _mode = m),
      sourceBytes: _sourceBytes,
    ),
  ],
),
```

The Accept button's switch already uses `EnhancerMode` after Change 2:
```dart
switch (_mode) {
  EnhancerMode.grayscale => const GrayscaleEnhancer(),
  EnhancerMode.bw        => const BwEnhancer(),
  EnhancerMode.auto      => const AutoEnhancer(),
  EnhancerMode.color     => const ColorEnhancer(),
  EnhancerMode.none      => const NoneEnhancer(),
},
```

- [ ] **Step 4: Delete the three old widget test files**

```bash
rm apps/mobile/test/features/scan/capture_review_screen_g1_test.dart
rm apps/mobile/test/features/scan/capture_review_screen_g2_test.dart
rm apps/mobile/test/features/scan/capture_review_screen_g3_test.dart
```

- [ ] **Step 5: Update the four existing BDD step defs**

The G1/G2/G3 BDD scenarios use these step functions. They previously tapped the AppBar toggle buttons; now they must tap the filter strip tiles (same semantic action, new key).

Replace the contents of `apps/mobile/test/step/i_toggle_the_grayscale_filter.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the grayscale filter
Future<void> iToggleTheGrayscaleFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
  await tester.pump();
}
```

Replace the contents of `apps/mobile/test/step/i_toggle_the_black_and_white_filter.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the black and white filter
Future<void> iToggleTheBlackAndWhiteFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('filter-tile-bw')));
  await tester.pump();
}
```

Replace the contents of `apps/mobile/test/step/i_toggle_the_auto_filter.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the auto filter
Future<void> iToggleTheAutoFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('filter-tile-auto')));
  await tester.pump();
}
```

Replace the contents of `apps/mobile/test/step/i_toggle_the_color_filter.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the color filter
Future<void> iToggleTheColorFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('filter-tile-color')));
  await tester.pump();
}
```

- [ ] **Step 6: Run the new G4 widget tests — verify they pass**

```bash
cd apps/mobile
flutter test test/features/scan/capture_review_screen_g4_test.dart --no-pub
```

Expected: `+9: All tests passed!`

Common failures and fixes:
- If `FilledButton` is not found for the saving test: try `tester.widget<ButtonStyleButton>(find.byKey(const Key('review-accept')))` instead.
- If `filter-tile-bw` is not found: check `ListView` scroll — use `tester.ensureVisible(find.byKey(const Key('filter-tile-bw')))` before tapping.
- If the `Column`/`Expanded` layout breaks the image display: verify `Expanded` wraps the `Stack` correctly.

- [ ] **Step 7: Run full host test suite — verify no regressions**

```bash
cd apps/mobile
flutter test --no-pub 2>&1 | tail -10
```

Expected: All non-OpenCV tests pass (OpenCV failures are pre-existing). Confirm the G1/G2/G3 BDD host tests still compile (they will now use the updated step defs).

- [ ] **Step 8: Run analyze**

```bash
cd apps/mobile
flutter analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 9: Commit**

```bash
git add apps/mobile/lib/features/scan/capture_review_screen.dart \
        apps/mobile/test/features/scan/capture_review_screen_g4_test.dart \
        apps/mobile/test/step/i_toggle_the_grayscale_filter.dart \
        apps/mobile/test/step/i_toggle_the_black_and_white_filter.dart \
        apps/mobile/test/step/i_toggle_the_auto_filter.dart \
        apps/mobile/test/step/i_toggle_the_color_filter.dart
git rm apps/mobile/test/features/scan/capture_review_screen_g1_test.dart \
       apps/mobile/test/features/scan/capture_review_screen_g2_test.dart \
       apps/mobile/test/features/scan/capture_review_screen_g3_test.dart
git commit -m "feat(g4): filter picker strip in review screen; Auto default; remove AppBar toggles"
```

---

## Task 3: BDD scenarios + step defs + verify script

**Files:**
- Create: `apps/mobile/integration_test/g4_filter_picker.feature`
- Create (generated): `apps/mobile/integration_test/g4_filter_picker_test.dart`
- Create: `apps/mobile/test/step/i_see_the_filter_picker_strip.dart`
- Create: `apps/mobile/test/step/i_tap_the_grayscale_filter_tile.dart`
- Create: `apps/mobile/test/step/i_tap_the_original_filter_tile.dart`
- Create: `scripts/verify/g4.sh`

**Interfaces:**
- Consumes (existing step defs — do NOT recreate or modify):
  - `theReviewScreenIsOpenWithACapturedImage` + `g1Repo` from `the_review_screen_is_open_with_a_captured_image.dart`
  - `iTapAccept` from `i_tap_accept.dart`
  - `theDocumentIsSavedWithAutoEnhancement` from `the_document_is_saved_with_auto_enhancement.dart` (created in G3)
  - `theDocumentIsSavedWithGrayscaleEnhancement` from `the_document_is_saved_with_grayscale_enhancement.dart` (created in G1)
  - `theDocumentIsSavedWithoutEnhancement` from `the_document_is_saved_without_enhancement.dart` (created in G1)

---

- [ ] **Step 1: Verify existing step defs are present**

```bash
ls apps/mobile/test/step/ | grep -E "i_tap_accept|the_review_screen|the_document_is_saved_with_auto|the_document_is_saved_with_grayscale|the_document_is_saved_without"
```

Expected: all five files listed.

- [ ] **Step 2: Create the Gherkin feature file**

Create `apps/mobile/integration_test/g4_filter_picker.feature`:

```gherkin
Feature: G4 Filter picker strip

  Scenario: Filter picker strip is visible on the review screen
    Given the review screen is open with a captured image
    Then I see the filter picker strip

  Scenario: Auto filter is selected by default
    Given the review screen is open with a captured image
    When I tap Accept
    Then the document is saved with auto enhancement

  Scenario: Tapping Grayscale tile saves with GrayscaleEnhancer
    Given the review screen is open with a captured image
    When I tap the grayscale filter tile
    And I tap Accept
    Then the document is saved with grayscale enhancement

  Scenario: Tapping Original tile saves without enhancement
    Given the review screen is open with a captured image
    When I tap the original filter tile
    And I tap Accept
    Then the document is saved without enhancement
```

- [ ] **Step 3: Create the three new step definitions**

Create `apps/mobile/test/step/i_see_the_filter_picker_strip.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the filter picker strip
Future<void> iSeeTheFilterPickerStrip(WidgetTester tester) async {
  expect(find.byKey(const Key('filter-picker-strip')), findsOneWidget,
      reason: 'FilterPickerStrip must be visible on the review screen');
}
```

Create `apps/mobile/test/step/i_tap_the_grayscale_filter_tile.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the grayscale filter tile
Future<void> iTapTheGrayscaleFilterTile(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
  await tester.pump();
}
```

Create `apps/mobile/test/step/i_tap_the_original_filter_tile.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the original filter tile
Future<void> iTapTheOriginalFilterTile(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('filter-tile-original')));
  await tester.pump();
}
```

- [ ] **Step 4: Generate the BDD test file**

```bash
cd apps/mobile
dart run build_runner build --delete-conflicting-outputs
```

Expected: generates `integration_test/g4_filter_picker_test.dart`. Verify:

```bash
ls integration_test/g4_filter_picker_test.dart
```

Open the generated file and confirm it imports:
- `./../test/step/the_review_screen_is_open_with_a_captured_image.dart`
- `./../test/step/i_see_the_filter_picker_strip.dart`
- `./../test/step/i_tap_accept.dart`
- `./../test/step/the_document_is_saved_with_auto_enhancement.dart`
- `./../test/step/i_tap_the_grayscale_filter_tile.dart`
- `./../test/step/the_document_is_saved_with_grayscale_enhancement.dart`
- `./../test/step/i_tap_the_original_filter_tile.dart`
- `./../test/step/the_document_is_saved_without_enhancement.dart`

Also confirm `theReviewScreenIsOpenWithACapturedImage` is referenced (required by the verify script).

If any step has a `// TODO: implement` stub: manually replace that step with the correct import and function call — follow the pattern in `g2_bw_test.dart`.

- [ ] **Step 5: Run the full host test suite**

```bash
cd apps/mobile
flutter test --no-pub 2>&1 | tail -10
```

Expected: all non-OpenCV tests pass.

- [ ] **Step 6: Create `scripts/verify/g4.sh`**

Create `scripts/verify/g4.sh` (at repository root, NOT inside apps/mobile):

```bash
#!/usr/bin/env bash
# Verify G4 (Filter picker UI) acceptance criteria.
# Run from repository root: bash scripts/verify/g4.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== G4 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "EnhancerMode public enum exists" \
  "apps/mobile/lib/features/library/enhancer_mode.dart" \
  "enum EnhancerMode"

assert_file_has "FilterPickerStrip class exists" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "class FilterPickerStrip"

assert_file_has "_thumbFn top-level function present" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "_thumbFn"

assert_file_has "bakeOrientation called in _thumbFn" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "bakeOrientation"

assert_file_has "compute() used in FilterPickerStrip" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "compute"

assert_file_has "filter-tile-auto key present" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "filter-tile-auto"

assert_file_has "filter-tile-original key present" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "filter-tile-original"

assert_file_has "filter-tile-bw key present" \
  "apps/mobile/lib/features/scan/widgets/filter_picker_strip.dart" \
  "filter-tile-bw"

assert_file_has "filter-picker-strip key present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "filter-picker-strip"

assert_file_has "EnhancerMode.auto is default in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "EnhancerMode.auto"

# Negative: old toggle keys must be gone
if grep -qF "grayscale-toggle" "apps/mobile/lib/features/scan/capture_review_screen.dart"; then
  fail "old grayscale-toggle key found in review screen — must be removed"
else
  pass "old AppBar toggle keys absent from review screen"
fi

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/g4_filter_picker.feature" \
  "Filter picker strip"

assert_file_has "BDD test file is generated" \
  "apps/mobile/integration_test/g4_filter_picker_test.dart" \
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

verify_integration_android g4_filter_picker_test.dart
verify_integration_ios g4_filter_picker_test.dart

verify_summary
```

Make it executable:
```bash
chmod +x scripts/verify/g4.sh
```

- [ ] **Step 7: Run the verify script (host-only)**

```bash
VERIFY_SKIP_DEVICE=1 bash scripts/verify/g4.sh
```

Expected: all static assertions PASS, host tests PASS, analyze PASS, coverage ≥ 70%, and exactly one FAIL for `DEVICE CHECKS SKIPPED`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/integration_test/g4_filter_picker.feature \
        apps/mobile/integration_test/g4_filter_picker_test.dart \
        apps/mobile/test/step/i_see_the_filter_picker_strip.dart \
        apps/mobile/test/step/i_tap_the_grayscale_filter_tile.dart \
        apps/mobile/test/step/i_tap_the_original_filter_tile.dart \
        scripts/verify/g4.sh
git commit -m "test(g4): BDD scenarios + step defs + verify script"
```

---

## Self-Review

**Spec coverage:**
- ✅ `FilterPickerStrip` widget — Task 1
- ✅ Five tiles with keys `filter-tile-{auto,original,color,grayscale,bw}` — Task 1
- ✅ `_thumbFn` top-level compute function, `bakeOrientation`, JPEG quality 85 — Task 1
- ✅ Live thumbnail generation via `Future.wait` over all 5 enhancers — Task 1
- ✅ Corrupt bytes → no crash, icon placeholder shown — Task 1 test
- ✅ Default mode `EnhancerMode.auto` — Task 2
- ✅ Old AppBar toggle buttons removed — Task 2
- ✅ `FilterPickerStrip` in body Column — Task 2
- ✅ `_sourceBytes` populated in `initState` — Task 2
- ✅ Existing G1/G2/G3 BDD step defs updated to tile keys — Task 2
- ✅ G1/G2/G3 widget tests replaced with G4 comprehensive test — Task 2
- ✅ BDD scenarios (4) + step defs (3 new, 4 updated) — Task 3
- ✅ `scripts/verify/g4.sh` with static assertions, host tests, analyze, coverage, device gate — Task 3
- ✅ OCP: `ImageEnhancer`, `NoneEnhancer`, all existing enhancers, `SaveController`, `DriftDocumentRepository`, `CameraScreen` untouched

**Placeholder scan:** No TBD/TODO/placeholders found.

**Type consistency:** `EnhancerMode` (public enum) used consistently in Task 1 (`filter_picker_strip.dart`) and Task 2 (`capture_review_screen.dart`). `FilterPickerStrip` signature matches between definition (Task 1) and usage (Task 2). `onModeChanged: (EnhancerMode) → void` consistent throughout.
