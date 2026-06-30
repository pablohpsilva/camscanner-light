# G1 Grayscale Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a grayscale toggle to the review screen and wire it through the save pipeline so accepted captures are stored as grayscale when the user opts in.

**Architecture:** A new `ImageEnhancer` DIP interface (parallel to `ImageWarper`) with `NoneEnhancer` and `GrayscaleEnhancer` strategies, both const-constructible. The chosen enhancer travels from `CaptureReviewScreen.onAccept` → `SaveController.save()` → `DriftDocumentRepository.createFromCapture()`, where it is applied after the warp and baked into the saved JPEG. No DB schema change; non-destructive re-selection is G4's concern.

**Tech Stack:** Flutter/Dart, `image` ^4.5.0 (resolved 4.9.1, already a dep), `flutter/foundation.dart` `compute()` for isolate offload, `bdd_widget_test` + `build_runner` for BDD.

## Global Constraints

- Flutter/Dart 3.12.2+; `image` package version resolved to 4.9.1 — **no new dependencies**.
- `img.bakeOrientation(image)` and `img.grayscale(src)` take **positional** first args (not named). `img.grayscale()` **mutates in place** and returns the same object.
- JPEG encode quality **92** everywhere (matches `PerspectiveWarper`).
- All CPU-intensive work in **`compute()`** (never on UI thread).
- `NoneEnhancer()` is the default — all existing callers compile without change.
- Toggle button key: **`Key('grayscale-toggle')`**.
- Enhancement failure is **silent** — save proceeds with unenhanced bytes.
- No DB schema change in G1.
- TDD: write the failing test first, observe red, then implement, observe green.

---

## File Map

| Action | Path |
|--------|------|
| Create | `apps/mobile/lib/features/library/image_enhancer.dart` |
| Create | `apps/mobile/lib/features/library/grayscale_enhancer.dart` |
| Create | `apps/mobile/test/features/library/grayscale_enhancer_test.dart` |
| Modify | `apps/mobile/lib/features/library/document_repository.dart` |
| Modify | `apps/mobile/lib/features/library/drift/drift_document_repository.dart` |
| Modify | `apps/mobile/lib/features/library/save_controller.dart` |
| Modify | `apps/mobile/test/support/fake_library.dart` |
| Modify | `apps/mobile/test/features/library/drift_document_repository_test.dart` |
| Modify | `apps/mobile/test/features/library/save_controller_test.dart` |
| Modify | `apps/mobile/lib/features/scan/capture_review_screen.dart` |
| Modify | `apps/mobile/lib/features/scan/camera_screen.dart` |
| Modify | `apps/mobile/test/features/scan/capture_review_screen_test.dart` |
| Create | `apps/mobile/test/features/scan/capture_review_screen_g1_test.dart` |
| Create | `apps/mobile/integration_test/g1_grayscale.feature` |
| Create (generated) | `apps/mobile/integration_test/g1_grayscale_test.dart` |
| Create | `apps/mobile/test/step/the_review_screen_is_open_with_a_captured_image.dart` |
| Create | `apps/mobile/test/step/i_toggle_the_grayscale_filter.dart` |
| Create | `apps/mobile/test/step/the_document_is_saved_with_grayscale_enhancement.dart` |
| Create | `apps/mobile/test/step/the_document_is_saved_without_enhancement.dart` |
| Create | `apps/mobile/scripts/verify/g1.sh` |

---

### Task 1: `ImageEnhancer` interface + `GrayscaleEnhancer` strategy

**Files:**
- Create: `apps/mobile/lib/features/library/image_enhancer.dart`
- Create: `apps/mobile/lib/features/library/grayscale_enhancer.dart`
- Create: `apps/mobile/test/features/library/grayscale_enhancer_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class ImageEnhancer` with `Future<Uint8List> enhance(Uint8List bytes)`
  - `class NoneEnhancer implements ImageEnhancer` — const, pass-through
  - `class GrayscaleEnhancer implements ImageEnhancer` — const, isolate-backed

---

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/features/library/grayscale_enhancer_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';

void main() {
  group('NoneEnhancer', () {
    test('returns the exact same bytes object unchanged', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = await const NoneEnhancer().enhance(bytes);
      expect(identical(result, bytes), isTrue);
    });
  });

  group('GrayscaleEnhancer', () {
    test('converts a color JPEG so every pixel has R == G == B (±5 tolerance)',
        () async {
      // Build a 4×4 solid-red image in memory and encode as JPEG.
      final src = img.Image(width: 4, height: 4, numChannels: 3);
      for (final p in src) {
        p.r = 200;
        p.g = 50;
        p.b = 50;
      }
      final inputBytes =
          Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final resultBytes =
          await const GrayscaleEnhancer().enhance(inputBytes);

      final decoded = img.decodeImage(resultBytes)!;
      for (final p in decoded) {
        expect((p.r - p.g).abs(), lessThanOrEqualTo(5),
            reason: 'R≠G at (${p.x},${p.y})');
        expect((p.g - p.b).abs(), lessThanOrEqualTo(5),
            reason: 'G≠B at (${p.x},${p.y})');
      }
    });

    test('returns input bytes unchanged when decoding fails (corrupt data)',
        () async {
      final garbage = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
      final result = await const GrayscaleEnhancer().enhance(garbage);
      expect(result, equals(garbage));
    });
  });
}
```

- [ ] **Step 2: Run tests — expect red (types not defined yet)**

```bash
cd apps/mobile && flutter test test/features/library/grayscale_enhancer_test.dart
```

Expected: compile error — `ImageEnhancer`, `NoneEnhancer`, `GrayscaleEnhancer` not found.

- [ ] **Step 3: Create `image_enhancer.dart`**

```dart
import 'dart:typed_data';

/// DIP boundary for post-capture image enhancement. Parallel to [ImageWarper].
/// Each filter is its own const-constructible strategy (OCP: add filters by
/// adding classes, never by modifying this file).
abstract interface class ImageEnhancer {
  /// Returns enhanced JPEG bytes. Never throws — on any failure returns
  /// [bytes] unchanged.
  Future<Uint8List> enhance(Uint8List bytes);
}

/// Pass-through: returns [bytes] unchanged. Default when no filter is chosen.
class NoneEnhancer implements ImageEnhancer {
  const NoneEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) async => bytes;
}
```

- [ ] **Step 4: Create `grayscale_enhancer.dart`**

```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';

/// Converts a JPEG to grayscale using luminance-weighted conversion.
/// Runs in a [compute] isolate — never blocks the UI thread.
class GrayscaleEnhancer implements ImageEnhancer {
  const GrayscaleEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_grayscaleFn, bytes);
}

// Top-level function required by compute() (must be isolate-sendable).
Uint8List _grayscaleFn(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes; // corrupt input — return unchanged
  // bakeOrientation: EXIF scrubber keeps the Orientation tag; encodeJpg
  // strips EXIF, so orientation must be baked into pixels first.
  // For already-baked flat bytes (post-warp), this is a safe no-op.
  final oriented = img.bakeOrientation(decoded); // positional arg
  img.grayscale(oriented); // positional arg, mutates in place
  return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
}
```

- [ ] **Step 5: Run tests — expect green**

```bash
cd apps/mobile && flutter test test/features/library/grayscale_enhancer_test.dart
```

Expected: all 3 tests pass.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/image_enhancer.dart \
        apps/mobile/lib/features/library/grayscale_enhancer.dart \
        apps/mobile/test/features/library/grayscale_enhancer_test.dart
git commit -m "feat(g1): ImageEnhancer interface + NoneEnhancer + GrayscaleEnhancer"
```

---

### Task 2: Thread enhancer through the save pipeline

**Files:**
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/lib/features/library/save_controller.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`
- Modify: `apps/mobile/test/features/library/drift_document_repository_test.dart`
- Modify: `apps/mobile/test/features/library/save_controller_test.dart`

**Interfaces:**
- Consumes: `ImageEnhancer`, `NoneEnhancer`, `GrayscaleEnhancer` from Task 1.
- Produces:
  - `DocumentRepository.createFromCapture(capture, {corners, enhancer})` — updated interface
  - `SaveController.save(image, {corners, enhancer})` — updated signature
  - `FakeDocumentRepository.lastSavedEnhancer` — new field for test assertions

---

- [ ] **Step 1: Write failing tests for the pipeline**

Add to `apps/mobile/test/features/library/drift_document_repository_test.dart`:

First, add imports at the top of the imports section:

```dart
import 'dart:ui' show Offset;
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';
```

Add the two helper classes after the existing `_ThrowingScrubber` class:

```dart
/// Records enhance() calls for assertions; returns bytes unchanged.
class _RecordingEnhancer implements ImageEnhancer {
  int calls = 0;

  @override
  Future<Uint8List> enhance(Uint8List bytes) async {
    calls++;
    return bytes;
  }
}

/// Always throws — tests that enhancement failure is silent.
class _ThrowingEnhancer implements ImageEnhancer {
  @override
  Future<Uint8List> enhance(Uint8List bytes) async =>
      throw Exception('enhance failed');
}
```

Add the three new tests at the end of the `main()` group, after existing tests:

```dart
const _testCorners = CropCorners(
  topLeft: Offset(0.1, 0.1),
  topRight: Offset(0.9, 0.1),
  bottomRight: Offset(0.9, 0.9),
  bottomLeft: Offset(0.1, 0.9),
);

test(
    'createFromCapture applies enhancer to flat bytes on cropped capture',
    () async {
  final enhancer = _RecordingEnhancer();
  // FakeImageWarper with a non-null returnValue simulates a successful warp.
  final r = repo(warper: FakeImageWarper(returnValue: Uint8List.fromList([1, 2, 3])));
  await r.createFromCapture(capture,
      corners: _testCorners, enhancer: enhancer);
  expect(enhancer.calls, 1,
      reason: 'enhancer must be called once on the flat bytes');
});

test(
    'createFromCapture applies enhancer to original bytes on full-frame capture',
    () async {
  final enhancer = _RecordingEnhancer();
  // No corners → full-frame path; FakeImageWarper(returnValue: null) → no warp.
  final r = repo(warper: FakeImageWarper());
  await r.createFromCapture(capture, enhancer: enhancer);
  expect(enhancer.calls, 1,
      reason: 'enhancer must be called once on the scrubbed original');
});

test('createFromCapture proceeds silently when enhancer throws', () async {
  final r = repo(
      warper: FakeImageWarper(returnValue: Uint8List.fromList([1, 2, 3])));
  await expectLater(
    r.createFromCapture(capture,
        corners: _testCorners, enhancer: const _ThrowingEnhancer()),
    completes,
    reason: 'enhancement failure must not abort the save',
  );
});
```

Add to `apps/mobile/test/features/library/save_controller_test.dart` at end of `main()`:

First add the import at the top:

```dart
import 'package:mobile/features/library/grayscale_enhancer.dart';
```

Then add the test:

```dart
test('save() threads the enhancer to the repository', () async {
  final repo = FakeDocumentRepository();
  final c = SaveController(repository: repo);
  await c.save(
    const CapturedImage('/tmp/cap.jpg'),
    enhancer: const GrayscaleEnhancer(),
  );
  expect(repo.lastSavedEnhancer, isA<GrayscaleEnhancer>());
  c.dispose();
});
```

- [ ] **Step 2: Run — expect red**

```bash
cd apps/mobile && flutter test \
  test/features/library/drift_document_repository_test.dart \
  test/features/library/save_controller_test.dart
```

Expected: compile errors — `ImageEnhancer` not in `DocumentRepository`/`SaveController`/`FakeDocumentRepository`.

- [ ] **Step 3: Update `document_repository.dart`**

Add import after existing imports:

```dart
import 'image_enhancer.dart';
```

Change the `createFromCapture` signature in the abstract interface:

```dart
/// Persists [capture] (EXIF-scrubbed) and creates a one-page document with the
/// page's crop [corners] (defaults to full-frame). When [enhancer] is provided
/// it is applied to the saved bytes after the warp (silent on failure).
Future<Document> createFromCapture(
  CapturedImage capture, {
  CropCorners? corners,
  ImageEnhancer? enhancer,
});
```

- [ ] **Step 4: Update `drift_document_repository.dart`**

Add import after existing imports:

```dart
import '../image_enhancer.dart';
```

Change the `createFromCapture` method signature and body. Replace the existing method (the full `createFromCapture` body, lines ~43–94) with:

```dart
@override
Future<Document> createFromCapture(
  CapturedImage capture, {
  CropCorners? corners,
  ImageEnhancer? enhancer,
}) async {
  final now = _clock();
  final createdUtc = now.toUtc();
  final name = _defaultName(now);
  try {
    final doc = await _db.transaction(() async {
      final docId = await _db.into(_db.documents).insert(
            DocumentsCompanion.insert(
                name: name, createdAt: createdUtc, modifiedAt: createdUtc),
          );
      final rel = _fileStore.relativeFor(docId, 1);
      late final Uint8List scrubbed;
      try {
        final raw = await File(capture.path).readAsBytes();
        scrubbed = _scrubber.scrub(Uint8List.fromList(raw));
        // G1: for full-frame (no warp), apply enhancement to the original
        // before writing. bakeOrientation runs inside GrayscaleEnhancer.
        final isFullFrame = corners == null || corners == CropCorners.fullFrame;
        Uint8List bytesToStore = scrubbed;
        if (enhancer != null && isFullFrame) {
          try {
            bytesToStore = await enhancer.enhance(scrubbed);
          } catch (_) {} // silent: use unenhanced scrubbed bytes
        }
        await _fileStore.writeRelative(rel, bytesToStore);
      } catch (e) {
        await _fileStore.deleteDocumentDir(docId); // best-effort cleanup
        rethrow; // rolls back the inserted document row
      }
      // E2 + G1: perspective-flatten, then enhance the flat.
      // Original (rel) is already on disk for the full-frame path.
      String? flatRel;
      if (corners != null && corners != CropCorners.fullFrame) {
        try {
          Uint8List? flat = await _warper.warp(scrubbed, corners);
          if (flat != null) {
            // Orientation already baked by warper — enhancer gets clean bytes.
            if (enhancer != null) {
              try {
                flat = await enhancer.enhance(flat);
              } catch (_) {} // silent: store unenhanced warp result
            }
            flatRel = _fileStore.flatRelativeFor(docId, 1);
            await _fileStore.writeRelative(flatRel, flat);
          }
        } catch (_) {/* WarpException or IO — flat stays null, save proceeds */}
      }
      await _db.into(_db.pages).insert(
            PagesCompanion.insert(
                documentId: docId,
                position: 1,
                relativeImagePath: rel,
                corners: Value(corners?.toStorage()),
                flatRelativePath: Value(flatRel)),
          );
      return Document(
          id: docId,
          name: name,
          createdAt: createdUtc,
          modifiedAt: createdUtc);
    });
    await _deleteTempSource(capture.path);
    return doc;
  } catch (e) {
    throw DocumentSaveException('save failed: $e');
  }
}
```

- [ ] **Step 5: Update `save_controller.dart`**

Add import after existing imports:

```dart
import 'image_enhancer.dart';
```

Change `save()` signature (add `enhancer` parameter with default `NoneEnhancer()`):

```dart
/// Persists [image] with optional crop [corners] and [enhancer].
/// Returns the saved [Document], or null on failure.
Future<Document?> save(
  CapturedImage image, {
  CropCorners corners = CropCorners.fullFrame,
  ImageEnhancer enhancer = const NoneEnhancer(),
}) async {
  if (_disposed || _status == SaveStatus.saving) return null;
  _set(SaveStatus.saving);
  try {
    final doc = await _repository.createFromCapture(image,
        corners: corners, enhancer: enhancer);
    if (_disposed) return null;
    _set(SaveStatus.idle);
    return doc;
  } catch (_) {
    if (_disposed) return null;
    _set(SaveStatus.error);
    return null;
  }
}
```

- [ ] **Step 6: Update `fake_library.dart`**

Add import after existing imports:

```dart
import 'package:mobile/features/library/image_enhancer.dart';
```

Add `lastSavedEnhancer` field to `FakeDocumentRepository` (alongside existing `lastSavedCorners`):

```dart
ImageEnhancer? lastSavedEnhancer;
```

Update the `createFromCapture` override signature and body to record the enhancer:

```dart
@override
Future<Document> createFromCapture(CapturedImage capture,
    {CropCorners? corners, ImageEnhancer? enhancer}) async {
  createCalls++;
  lastSavedCorners = corners;
  lastSavedEnhancer = enhancer;
  if (gate != null) await gate!.future;
  if (throwOnCreate) {
    throw const DocumentSaveException('fake: save failed');
  }
  final doc = Document(
    id: documents.length + 1,
    name: 'Scan 2026-06-27 20.26.42',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
  );
  documents.insert(0, doc);
  return doc;
}
```

- [ ] **Step 7: Run tests — expect green**

```bash
cd apps/mobile && flutter test \
  test/features/library/drift_document_repository_test.dart \
  test/features/library/save_controller_test.dart
```

Expected: all tests pass (new 4 + all existing).

- [ ] **Step 8: Run the full suite to verify no regressions**

```bash
cd apps/mobile && flutter test
```

Expected: all tests pass (existing tests compile because `enhancer` is optional with a default).

- [ ] **Step 9: Commit**

```bash
git add apps/mobile/lib/features/library/document_repository.dart \
        apps/mobile/lib/features/library/drift/drift_document_repository.dart \
        apps/mobile/lib/features/library/save_controller.dart \
        apps/mobile/test/support/fake_library.dart \
        apps/mobile/test/features/library/drift_document_repository_test.dart \
        apps/mobile/test/features/library/save_controller_test.dart
git commit -m "feat(g1): thread ImageEnhancer through save pipeline"
```

---

### Task 3: Grayscale toggle on `CaptureReviewScreen` + `CameraScreen` wiring

**Files:**
- Modify: `apps/mobile/lib/features/scan/capture_review_screen.dart`
- Modify: `apps/mobile/lib/features/scan/camera_screen.dart`
- Modify: `apps/mobile/test/features/scan/capture_review_screen_test.dart`
- Create: `apps/mobile/test/features/scan/capture_review_screen_g1_test.dart`

**Interfaces:**
- Consumes: `ImageEnhancer`, `NoneEnhancer` (Task 1), `SaveController.save(enhancer:)` (Task 2).
- The `onAccept` callback type changes from `ValueChanged<CropCorners>` to
  `void Function(CropCorners corners, ImageEnhancer enhancer)`.

---

- [ ] **Step 1: Write the failing G1 widget tests**

Create `apps/mobile/test/features/scan/capture_review_screen_g1_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

/// Helper: pumps CaptureReviewScreen with a non-loadable image path,
/// instant size resolution, and the given onAccept callback.
Future<void> _pump(
  WidgetTester tester, {
  required void Function(CropCorners, ImageEnhancer) onAccept,
  bool saving = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/g1.jpg'),
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
  testWidgets('grayscale toggle button is present in the AppBar',
      (tester) async {
    await _pump(tester, onAccept: (_, __) {});
    expect(find.byKey(const Key('grayscale-toggle')), findsOneWidget);
  });

  testWidgets('tapping toggle changes its tooltip', (tester) async {
    await _pump(tester, onAccept: (_, __) {});

    final before = tester.widget<IconButton>(
        find.byKey(const Key('grayscale-toggle')));
    expect(before.tooltip, equals('Grayscale off'));

    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();

    final after = tester.widget<IconButton>(
        find.byKey(const Key('grayscale-toggle')));
    expect(after.tooltip, equals('Grayscale on'));
  });

  testWidgets('Accept with toggle on calls onAccept with GrayscaleEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<GrayscaleEnhancer>());
  });

  testWidgets('Accept with toggle off calls onAccept with NoneEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    // No toggle tap — default is NoneEnhancer.
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<NoneEnhancer>());
  });
}
```

- [ ] **Step 2: Run — expect red**

```bash
cd apps/mobile && flutter test test/features/scan/capture_review_screen_g1_test.dart
```

Expected: compile error — `CaptureReviewScreen.onAccept` still has old type.

- [ ] **Step 3: Update `capture_review_screen.dart`**

Add imports after the existing imports block:

```dart
import '../library/grayscale_enhancer.dart';
import '../library/image_enhancer.dart';
```

Change the `onAccept` field declaration (find `final ValueChanged<CropCorners> onAccept;`):

```dart
final void Function(CropCorners corners, ImageEnhancer enhancer) onAccept;
```

Add `_grayscale` to the `_CaptureReviewScreenState` class fields:

```dart
bool _grayscale = false;
```

In `build()`, update the `AppBar` to add the toggle action:

```dart
appBar: AppBar(
  title: const Text('Review'),
  actions: [
    IconButton(
      key: const Key('grayscale-toggle'),
      icon: Icon(_grayscale ? Icons.filter_b_and_w : Icons.filter_b_and_w_outlined),
      tooltip: _grayscale ? 'Grayscale on' : 'Grayscale off',
      onPressed: () => setState(() => _grayscale = !_grayscale),
    ),
  ],
),
```

Update the Accept `FilledButton.icon` `onPressed`:

```dart
onPressed: widget.saving
    ? null
    : () => widget.onAccept(
          _corners,
          _grayscale ? const GrayscaleEnhancer() : const NoneEnhancer(),
        ),
```

- [ ] **Step 4: Run G1 widget tests — expect green**

```bash
cd apps/mobile && flutter test test/features/scan/capture_review_screen_g1_test.dart
```

Expected: all 4 tests pass.

- [ ] **Step 5: Fix existing `capture_review_screen_test.dart`**

The `subject()` helper and all inline `CaptureReviewScreen` usages use the old `ValueChanged<CropCorners>` type. Update every occurrence:

Add import at the top of the file (after existing imports):
```dart
import 'package:mobile/features/library/image_enhancer.dart';
```

Update the `subject()` helper definition (around line 80):

```dart
CaptureReviewScreen subject({
  required void Function(CropCorners, ImageEnhancer) onAccept,
  VoidCallback? onRetake,
  bool saving = false,
  Future<Size> Function(String)? decode,
}) =>
    CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/cap.jpg'),
      onRetake: onRetake ?? () {},
      onAccept: onAccept,
      saving: saving,
      decodeImageSize: decode ?? (_) async => const Size(1000, 750),
    );
```

Update every `onAccept` lambda in the file — replace the old single-param lambdas with two-param lambdas:

| Old | New |
|-----|-----|
| `onAccept: (corners) => accepted = true` | `onAccept: (corners, _) => accepted = true` |
| `onAccept: (corners) {}` | `onAccept: (corners, _) {}` |
| `onAccept: (_) {}` | `onAccept: (_, __) {}` |
| `onAccept: (c) => accepted = c` | `onAccept: (c, _) => accepted = c` |
| `subject(onAccept: (_) {})` | `subject(onAccept: (_, __) {})` |
| `subject(onAccept: (c) => accepted = c)` | `subject(onAccept: (c, _) => accepted = c)` |
| `onAccept ?? (_) {}` | `onAccept ?? (_, __) {}` |

There are approximately 15 such occurrences throughout the file. Search for `onAccept:` and update each one.

- [ ] **Step 6: Update `camera_screen.dart`**

Add import after existing imports:

```dart
import '../library/image_enhancer.dart';
```

Update `_onAccept` signature to receive `ImageEnhancer`:

```dart
Future<void> _onAccept(
    CapturedImage image, CropCorners corners, ImageEnhancer enhancer) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final doc = await _saveController.save(image,
      corners: corners, enhancer: enhancer);
  if (!mounted) return;
  if (doc == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't save document. Try again.")),
    );
    return;
  }
  navigator.popUntil((route) => route.isFirst);
}
```

Update the `onAccept` lambda in `navigator.push` (inside `_onShutter`):

```dart
onAccept: (corners, enhancer) => _onAccept(image, corners, enhancer),
```

- [ ] **Step 7: Run the full suite — expect green**

```bash
cd apps/mobile && flutter test
```

Expected: all tests pass. If any compile errors remain in `capture_review_screen_test.dart`, they are due to missed `onAccept` lambda updates — fix them now.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/scan/capture_review_screen.dart \
        apps/mobile/lib/features/scan/camera_screen.dart \
        apps/mobile/test/features/scan/capture_review_screen_test.dart \
        apps/mobile/test/features/scan/capture_review_screen_g1_test.dart
git commit -m "feat(g1): grayscale toggle on review screen; onAccept carries ImageEnhancer"
```

---

### Task 4: BDD scenarios + verify script

**Files:**
- Create: `apps/mobile/integration_test/g1_grayscale.feature`
- Create (generated): `apps/mobile/integration_test/g1_grayscale_test.dart`
- Create: `apps/mobile/test/step/the_review_screen_is_open_with_a_captured_image.dart`
- Create: `apps/mobile/test/step/i_toggle_the_grayscale_filter.dart`
- Create: `apps/mobile/test/step/the_document_is_saved_with_grayscale_enhancement.dart`
- Create: `apps/mobile/test/step/the_document_is_saved_without_enhancement.dart`
- Create: `apps/mobile/scripts/verify/g1.sh`

**Interfaces:**
- Consumes: `Key('grayscale-toggle')` (Task 3), `FakeDocumentRepository.lastSavedEnhancer` (Task 2).
- Reuses existing step: `apps/mobile/test/step/i_tap_accept.dart` (`iTapAccept`).

---

- [ ] **Step 1: Create the BDD feature file**

Create `apps/mobile/integration_test/g1_grayscale.feature`:

```gherkin
Feature: G1 grayscale scan enhancement

  Scenario: Grayscale filter applied — document saved with enhancement
    Given the review screen is open with a captured image
    When I toggle the grayscale filter
    And I tap Accept
    Then the document is saved with grayscale enhancement

  Scenario: No filter — document saved without enhancement
    Given the review screen is open with a captured image
    When I tap Accept
    Then the document is saved without enhancement
```

- [ ] **Step 2: Create the step definition files**

Create `apps/mobile/test/step/the_review_screen_is_open_with_a_captured_image.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../test/support/fake_library.dart';

/// Shared repo instance — set by the Given step; read by the Then steps.
FakeDocumentRepository g1Repo = FakeDocumentRepository();

/// Usage: the review screen is open with a captured image
Future<void> theReviewScreenIsOpenWithACapturedImage(
    WidgetTester tester) async {
  g1Repo = FakeDocumentRepository();
  await tester.pumpWidget(MaterialApp(
    home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/g1bdd.jpg'),
      saving: false,
      onRetake: () {},
      // Record the enhancer that CameraScreen would pass to SaveController.
      onAccept: (CropCorners corners, ImageEnhancer enhancer) {
        g1Repo.lastSavedEnhancer = enhancer;
      },
      decodeImageSize: (_) async => const Size(100, 100),
      readBytes: (_) async => Uint8List(0),
    ),
  ));
  await tester.pumpAndSettle();
}
```

Create `apps/mobile/test/step/i_toggle_the_grayscale_filter.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the grayscale filter
Future<void> iToggleTheGrayscaleFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('grayscale-toggle')));
  await tester.pump();
}
```

Create `apps/mobile/test/step/the_document_is_saved_with_grayscale_enhancement.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the document is saved with grayscale enhancement
Future<void> theDocumentIsSavedWithGrayscaleEnhancement(
    WidgetTester tester) async {
  expect(g1Repo.lastSavedEnhancer, isA<GrayscaleEnhancer>(),
      reason: 'expected GrayscaleEnhancer to have been passed to onAccept');
}
```

Create `apps/mobile/test/step/the_document_is_saved_without_enhancement.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/image_enhancer.dart';

import 'the_review_screen_is_open_with_a_captured_image.dart';

/// Usage: the document is saved without enhancement
Future<void> theDocumentIsSavedWithoutEnhancement(
    WidgetTester tester) async {
  expect(g1Repo.lastSavedEnhancer, isA<NoneEnhancer>(),
      reason: 'expected NoneEnhancer to have been passed to onAccept');
}
```

- [ ] **Step 3: Run `build_runner` to generate the test file**

```bash
cd apps/mobile && dart run build_runner build 2>&1 | tail -5
```

Expected output contains: `Built with build_runner`

Verify the generated file exists:

```bash
ls apps/mobile/integration_test/g1_grayscale_test.dart
```

- [ ] **Step 4: Run the full host suite (includes new BDD host test)**

```bash
cd apps/mobile && flutter test
```

Expected: all tests pass.

- [ ] **Step 5: Create the verify script**

Create `apps/mobile/scripts/verify/g1.sh`:

```bash
#!/usr/bin/env bash
# Verify G1 (grayscale filter) acceptance criteria.
# Run: bash scripts/verify/g1.sh
# VERIFY_SKIP_DEVICE=1 skips on-device BDD (reported as FAIL, never silent).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== G1 verification =="

require_tool flutter
require_tool pnpm

# ---- Static assertions ----
assert_file_has "ImageEnhancer interface exists" \
  "apps/mobile/lib/features/library/image_enhancer.dart" \
  "abstract interface class ImageEnhancer"

assert_file_has "NoneEnhancer exists" \
  "apps/mobile/lib/features/library/image_enhancer.dart" \
  "class NoneEnhancer"

assert_file_has "GrayscaleEnhancer exists" \
  "apps/mobile/lib/features/library/grayscale_enhancer.dart" \
  "class GrayscaleEnhancer"

assert_file_has "grayscale-toggle key present in review screen" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" \
  "grayscale-toggle"

assert_file_has "bakeOrientation called in GrayscaleEnhancer (orientation safety)" \
  "apps/mobile/lib/features/library/grayscale_enhancer.dart" \
  "bakeOrientation"

assert_file_has "compute() used in GrayscaleEnhancer (off UI thread)" \
  "apps/mobile/lib/features/library/grayscale_enhancer.dart" \
  "compute"

assert_file_has "ImageEnhancer in DocumentRepository interface" \
  "apps/mobile/lib/features/library/document_repository.dart" \
  "ImageEnhancer"

assert_file_has "enhancer applied in DriftDocumentRepository" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" \
  "enhancer.enhance"

assert_file_has "BDD feature file exists" \
  "apps/mobile/integration_test/g1_grayscale.feature" \
  "Grayscale"

assert_file_has "BDD test file is generated" \
  "apps/mobile/integration_test/g1_grayscale_test.dart" \
  "g1Grayscale"

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

verify_integration_android g1_grayscale_test.dart
verify_integration_ios g1_grayscale_test.dart

verify_summary
```

Make the script executable:

```bash
chmod +x apps/mobile/scripts/verify/g1.sh
```

- [ ] **Step 6: Run the verify script (host gates only)**

```bash
VERIFY_SKIP_DEVICE=1 bash apps/mobile/scripts/verify/g1.sh
```

Expected: static assertions pass (9/9), host tests pass, analyze clean, coverage ≥ 70%, then one intentional FAIL for the device skip gate.

- [ ] **Step 7: Commit everything**

```bash
git add apps/mobile/integration_test/g1_grayscale.feature \
        apps/mobile/integration_test/g1_grayscale_test.dart \
        apps/mobile/test/step/the_review_screen_is_open_with_a_captured_image.dart \
        apps/mobile/test/step/i_toggle_the_grayscale_filter.dart \
        apps/mobile/test/step/the_document_is_saved_with_grayscale_enhancement.dart \
        apps/mobile/test/step/the_document_is_saved_without_enhancement.dart \
        apps/mobile/scripts/verify/g1.sh
git commit -m "test(g1): BDD scenarios + verify script"
```
