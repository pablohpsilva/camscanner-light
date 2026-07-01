# Curved Crop + Coons-Patch Unwarp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 4 edge-midpoint handles (8 total) to the crop overlay that bend edges into smooth curves, and unwarp the curved region to a flat rectangle.

**Architecture:** Extend `CropCorners` with four edge-midpoint *deviations* (default `Offset.zero`, a valid `const` default, so all existing call sites compile unchanged). A `HybridWarper` routes straight crops to the existing homography `PerspectiveWarper` (no perspective regression) and bent crops to a new pure-Dart `CoonsWarper`. The overlay renders 8 handles and Bézier edges.

**Tech Stack:** Flutter 3.44.4, Dart; `package:image` (pure-Dart raster ops in a `compute()` isolate); `flutter_test`; `integration_test`.

**Spec:** `docs/superpowers/specs/2026-07-01-curved-crop-coons-warp-design.md`

## Global Constraints

- Pure-Dart image ops only (`package:image`); heavy work in a `compute()` isolate. No new dependencies.
- `CropCorners` keeps its `const` constructor; deviations default `Offset.zero`. Existing 4-arg call sites must not break.
- Persistence: `toStorage()` emits 16 fixed-precision (6-decimal) numbers; `tryParse()` accepts **8** (legacy → zero deviations) or **16**; fail-soft (never throws, returns null on bad input).
- Warp output JPEG quality **92** (matches `PerspectiveWarper`). `warp()` never throws to callers of the facade except `WarpException`/IO, which the repository already swallows.
- Straight crops (`isStraight`) MUST use the existing homography path — no behavior change.
- Coons control point: `C = center + 2·dev`. Coons patch: `S(u,v) = (1−v)·top(u) + v·bottom(u) + (1−u)·left(v) + u·right(v) − bilinear(corners)`.
- TDD: failing test first, watch it fail, minimal code, watch it pass, commit. Run tests from `apps/mobile/`.

---

### Task 1: `CropCorners` deviation model

**Files:**
- Modify: `apps/mobile/lib/features/library/crop_corners.dart`
- Test: `apps/mobile/test/features/library/crop_corners_test.dart`

**Interfaces:**
- Produces: `CropCorners({required Offset topLeft, topRight, bottomRight, bottomLeft, Offset topMidDev = Offset.zero, rightMidDev = Offset.zero, bottomMidDev = Offset.zero, leftMidDev = Offset.zero})`; getters `Offset get topMid/rightMid/bottomMid/leftMid` and `topCenter/rightCenter/bottomCenter/leftCenter`; `bool get isStraight`; `CropCorners copyWith({...all 8 fields...})`; `CropCorners clamp()`.

- [ ] **Step 1: Write the failing tests** — append to `crop_corners_test.dart`:

```dart
group('deviation model', () {
  const bent = CropCorners(
    topLeft: Offset(0, 0), topRight: Offset(1, 0),
    bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
    topMidDev: Offset(0, 0.1));

  test('defaults: no deviations → isStraight, midpoints at edge centers', () {
    const c = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1));
    expect(c.isStraight, isTrue);
    expect(c.topMid, const Offset(0.5, 0));
    expect(c.leftMid, const Offset(0, 0.5));
  });

  test('a non-zero deviation offsets the midpoint from center and is not straight', () {
    expect(bent.isStraight, isFalse);
    expect(bent.topMid, const Offset(0.5, 0.1)); // center (0.5,0) + dev (0,0.1)
  });

  test('midpoint follows a moved corner (deviation is relative)', () {
    final moved = bent.copyWith(topRight: const Offset(0.8, 0));
    // topCenter = (0,0)+(0.8,0) /2 = (0.4,0); + dev (0,0.1) = (0.4,0.1)
    expect(moved.topMid, const Offset(0.4, 0.1));
  });

  test('copyWith preserves untouched fields (corner drag keeps a bend)', () {
    final moved = bent.copyWith(topLeft: const Offset(0.05, 0.05));
    expect(moved.topMidDev, const Offset(0, 0.1));
    expect(moved.topLeft, const Offset(0.05, 0.05));
  });

  test('== and hashCode include deviations', () {
    const same = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.1));
    expect(bent, same);
    expect(bent.hashCode, same.hashCode);
    expect(bent, isNot(CropCorners.fullFrame));
  });

  test('clamp pulls resolved midpoints into [0,1]', () {
    const c = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, -0.5)); // topMid = (0.5,-0.5) → clamp to (0.5,0)
    expect(c.clamp().topMid.dy, 0.0);
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/library/crop_corners_test.dart`
Expected: FAIL — `topMidDev`, `topMid`, `isStraight`, `copyWith` not defined.

- [ ] **Step 3: Implement** — replace the class body of `crop_corners.dart` (keep the file's existing `import`, `fullFrame`, `toStorage`/`tryParse` for now — those change in Task 2):

```dart
class CropCorners {
  final Offset topLeft, topRight, bottomRight, bottomLeft;
  final Offset topMidDev, rightMidDev, bottomMidDev, leftMidDev;
  const CropCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
    this.topMidDev = Offset.zero,
    this.rightMidDev = Offset.zero,
    this.bottomMidDev = Offset.zero,
    this.leftMidDev = Offset.zero,
  });

  static const CropCorners fullFrame = CropCorners(
    topLeft: Offset(0, 0),
    topRight: Offset(1, 0),
    bottomRight: Offset(1, 1),
    bottomLeft: Offset(0, 1),
  );

  static Offset _mid(Offset a, Offset b) =>
      Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

  Offset get topCenter => _mid(topLeft, topRight);
  Offset get rightCenter => _mid(topRight, bottomRight);
  Offset get bottomCenter => _mid(bottomRight, bottomLeft);
  Offset get leftCenter => _mid(bottomLeft, topLeft);

  Offset get topMid => topCenter + topMidDev;
  Offset get rightMid => rightCenter + rightMidDev;
  Offset get bottomMid => bottomCenter + bottomMidDev;
  Offset get leftMid => leftCenter + leftMidDev;

  static const double _straightEps = 1e-9;
  bool get isStraight =>
      topMidDev.distanceSquared < _straightEps &&
      rightMidDev.distanceSquared < _straightEps &&
      bottomMidDev.distanceSquared < _straightEps &&
      leftMidDev.distanceSquared < _straightEps;

  CropCorners copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
    Offset? topMidDev,
    Offset? rightMidDev,
    Offset? bottomMidDev,
    Offset? leftMidDev,
  }) =>
      CropCorners(
        topLeft: topLeft ?? this.topLeft,
        topRight: topRight ?? this.topRight,
        bottomRight: bottomRight ?? this.bottomRight,
        bottomLeft: bottomLeft ?? this.bottomLeft,
        topMidDev: topMidDev ?? this.topMidDev,
        rightMidDev: rightMidDev ?? this.rightMidDev,
        bottomMidDev: bottomMidDev ?? this.bottomMidDev,
        leftMidDev: leftMidDev ?? this.leftMidDev,
      );

  /// Clamps corners to `[0,1]`, then pulls each resolved midpoint into `[0,1]`
  /// by adjusting its deviation.
  CropCorners clamp() {
    final tl = _clamp(topLeft), tr = _clamp(topRight);
    final br = _clamp(bottomRight), bl = _clamp(bottomLeft);
    Offset dev(Offset a, Offset b, Offset d) =>
        _clamp(_mid(a, b) + d) - _mid(a, b);
    return CropCorners(
      topLeft: tl,
      topRight: tr,
      bottomRight: br,
      bottomLeft: bl,
      topMidDev: dev(tl, tr, topMidDev),
      rightMidDev: dev(tr, br, rightMidDev),
      bottomMidDev: dev(br, bl, bottomMidDev),
      leftMidDev: dev(bl, tl, leftMidDev),
    );
  }

  String toStorage() => [
        topLeft.dx, topLeft.dy,
        topRight.dx, topRight.dy,
        bottomRight.dx, bottomRight.dy,
        bottomLeft.dx, bottomLeft.dy,
      ].map((d) => d.toStringAsFixed(6)).join(',');

  static CropCorners? tryParse(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(',');
    if (parts.length != 8) return null;
    final v = <double>[];
    for (final p in parts) {
      final d = double.tryParse(p);
      if (d == null || !d.isFinite) return null;
      v.add(d);
    }
    return CropCorners(
      topLeft: Offset(v[0], v[1]),
      topRight: Offset(v[2], v[3]),
      bottomRight: Offset(v[4], v[5]),
      bottomLeft: Offset(v[6], v[7]),
    );
  }

  static Offset _clamp(Offset o) =>
      Offset(o.dx.clamp(0.0, 1.0), o.dy.clamp(0.0, 1.0));

  @override
  bool operator ==(Object other) =>
      other is CropCorners &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft &&
      other.topMidDev == topMidDev &&
      other.rightMidDev == rightMidDev &&
      other.bottomMidDev == bottomMidDev &&
      other.leftMidDev == leftMidDev;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft,
      topMidDev, rightMidDev, bottomMidDev, leftMidDev);

  @override
  String toString() =>
      'CropCorners($topLeft, $topRight, $bottomRight, $bottomLeft; '
      'devs $topMidDev,$rightMidDev,$bottomMidDev,$leftMidDev)';
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/library/crop_corners_test.dart`
Expected: PASS (existing round-trip + fail-soft tests still green; new group green).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/crop_corners.dart apps/mobile/test/features/library/crop_corners_test.dart
git commit -m "feat(crop): CropCorners edge-midpoint deviations, copyWith, isStraight"
```

---

### Task 2: `CropCorners` 16-number persistence

**Files:**
- Modify: `apps/mobile/lib/features/library/crop_corners.dart` (`toStorage`, `tryParse`)
- Test: `apps/mobile/test/features/library/crop_corners_test.dart`

**Interfaces:**
- Produces: `toStorage()` → 16 numbers; `tryParse(String?)` accepts 8 (legacy) or 16.

- [ ] **Step 1: Write the failing tests** — append:

```dart
group('16-number persistence', () {
  const bent = CropCorners(
    topLeft: Offset(0.1, 0.2), topRight: Offset(0.9, 0.15),
    bottomRight: Offset(0.85, 0.95), bottomLeft: Offset(0.05, 0.9),
    topMidDev: Offset(0.0, 0.07), rightMidDev: Offset(-0.03, 0.0));

  test('toStorage emits 16 numbers and round-trips deviations', () {
    expect(bent.toStorage().split(',').length, 16);
    expect(CropCorners.tryParse(bent.toStorage()), bent);
  });

  test('legacy 8-number string parses as zero-deviation (straight)', () {
    final parsed = CropCorners.tryParse('0.1,0.2,0.9,0.15,0.85,0.95,0.05,0.9');
    expect(parsed, isNotNull);
    expect(parsed!.isStraight, isTrue);
    expect(parsed.topLeft, const Offset(0.1, 0.2));
  });

  test('rejects a 12-number string (neither 8 nor 16)', () {
    expect(CropCorners.tryParse(List.filled(12, '0').join(',')), isNull);
  });

  test('rejects a 16-number string with a non-finite token', () {
    final t = List.filled(16, '0.1')..[15] = 'NaN';
    expect(CropCorners.tryParse(t.join(',')), isNull);
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/library/crop_corners_test.dart -n "16-number persistence"`
Expected: FAIL — `toStorage` emits 8, `tryParse` of 16 returns null.

- [ ] **Step 3: Implement** — replace `toStorage` and `tryParse` in `crop_corners.dart`:

```dart
  String toStorage() => [
        topLeft.dx, topLeft.dy,
        topRight.dx, topRight.dy,
        bottomRight.dx, bottomRight.dy,
        bottomLeft.dx, bottomLeft.dy,
        topMidDev.dx, topMidDev.dy,
        rightMidDev.dx, rightMidDev.dy,
        bottomMidDev.dx, bottomMidDev.dy,
        leftMidDev.dx, leftMidDev.dy,
      ].map((d) => d.toStringAsFixed(6)).join(',');

  static CropCorners? tryParse(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(',');
    if (parts.length != 8 && parts.length != 16) return null;
    final v = <double>[];
    for (final p in parts) {
      final d = double.tryParse(p);
      if (d == null || !d.isFinite) return null;
      v.add(d);
    }
    final corners = CropCorners(
      topLeft: Offset(v[0], v[1]),
      topRight: Offset(v[2], v[3]),
      bottomRight: Offset(v[4], v[5]),
      bottomLeft: Offset(v[6], v[7]),
    );
    if (parts.length == 8) return corners;
    return corners.copyWith(
      topMidDev: Offset(v[8], v[9]),
      rightMidDev: Offset(v[10], v[11]),
      bottomMidDev: Offset(v[12], v[13]),
      leftMidDev: Offset(v[14], v[15]),
    );
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/library/crop_corners_test.dart`
Expected: PASS (including the original `toStorage <-> tryParse round-trips` — now 16 numbers, still `==`).

- [ ] **Step 5: Run the repository/migration suites (back-compat gate)**

Run: `flutter test test/features/library/drift_document_repository_test.dart test/features/library/drift/migration_test.dart`
Expected: PASS (they read corners back via `==`; zero-deviation shapes are unchanged).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/crop_corners.dart apps/mobile/test/features/library/crop_corners_test.dart
git commit -m "feat(crop): 16-number CropCorners storage, 8-number legacy parse"
```

---

### Task 3: `CoonsWarper`

**Files:**
- Create: `apps/mobile/lib/features/library/coons_warper.dart`
- Test: `apps/mobile/test/features/library/coons_warper_test.dart`

**Interfaces:**
- Consumes: `ImageWarper` (`lib/features/library/image_warper.dart`), `WarpException`, `CropCorners`.
- Produces: `class CoonsWarper implements ImageWarper` with `const CoonsWarper({int maxDimension = 2000})`; `Future<Uint8List?> warp(Uint8List bytes, CropCorners corners)`.

- [ ] **Step 1: Write the failing tests** — new file `coons_warper_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/coons_warper.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_warper.dart';

Uint8List _rectJpeg(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(10, 20, 30));
  img.fillRect(image, x1: w ~/ 4, y1: h ~/ 4, x2: 3 * w ~/ 4, y2: 3 * h ~/ 4,
      color: img.ColorRgb8(200, 200, 200));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  const warper = CoonsWarper();

  test('fullFrame → null (no-op)', () async {
    expect(await warper.warp(_rectJpeg(80, 60), CropCorners.fullFrame), isNull);
  });

  test('straight full-frame corners → identity-sized output (decodable JPEG)',
      () async {
    // Straight edges over the whole image: output ≈ source dimensions.
    const straight = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.0001)); // tiny dev so it's not == fullFrame
    final out = await warper.warp(_rectJpeg(120, 90), straight);
    expect(out, isNotNull);
    final decoded = img.decodeImage(out!);
    expect(decoded, isNotNull);
    expect(decoded!.width, closeTo(120, 8));
    expect(decoded.height, closeTo(90, 8));
  });

  test('bent top edge produces a decodable output of sane size', () async {
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9),
      topMidDev: Offset(0, -0.08)); // top edge bows upward
    final out = await warper.warp(_rectJpeg(200, 160), bent);
    expect(out, isNotNull);
    final decoded = img.decodeImage(out!)!;
    expect(decoded.width, greaterThan(2));
    expect(decoded.height, greaterThan(2));
  });

  test('output dimensions are capped by maxDimension', () async {
    const warperSmall = CoonsWarper(maxDimension: 50);
    const bent = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.05));
    final out = await warperSmall.warp(_rectJpeg(400, 300), bent);
    final decoded = img.decodeImage(out!)!;
    expect(decoded.width, lessThanOrEqualTo(50));
    expect(decoded.height, lessThanOrEqualTo(50));
  });

  test('corrupt bytes → WarpException', () async {
    expect(
      () => warper.warp(Uint8List.fromList([0xFF, 0xD8, 0x00]),
          const CropCorners(
              topLeft: Offset(0, 0), topRight: Offset(1, 0),
              bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
              topMidDev: Offset(0, 0.05))),
      throwsA(isA<WarpException>()),
    );
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/library/coons_warper_test.dart`
Expected: FAIL — `coons_warper.dart` does not exist.

- [ ] **Step 3: Implement** — new file `coons_warper.dart`:

```dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'crop_corners.dart';
import 'image_warper.dart';

/// Unwarps a curved 8-point crop (4 corners + 4 edge-midpoint deviations) to a
/// flat rectangle via a bilinearly-blended Coons patch. Pure Dart, runs in a
/// compute() isolate. Straight crops are handled upstream by [HybridWarper];
/// this class assumes at least one bent edge.
class CoonsWarper implements ImageWarper {
  final int maxDimension;
  const CoonsWarper({this.maxDimension = 2000});

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) {
    if (corners == CropCorners.fullFrame) return Future.value(null);
    return compute(
        _coonsFn, _CoonsArgs(bytes: bytes, corners: corners, maxDim: maxDimension));
  }
}

class _CoonsArgs {
  final Uint8List bytes;
  final CropCorners corners;
  final int maxDim;
  const _CoonsArgs(
      {required this.bytes, required this.corners, required this.maxDim});
}

Uint8List? _coonsFn(_CoonsArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) throw WarpException('failed to decode JPEG');
  final src = img.bakeOrientation(decoded);
  final w = src.width, h = src.height;
  final c = args.corners;

  Offset px(Offset n) => Offset(n.dx * w, n.dy * h);
  final tl = px(c.topLeft), tr = px(c.topRight);
  final br = px(c.bottomRight), bl = px(c.bottomLeft);

  // Control point in pixels: C = center + 2·dev.
  Offset ctrl(Offset a, Offset b, Offset devNorm) {
    final center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    return center + Offset(devNorm.dx * w, devNorm.dy * h) * 2.0;
  }

  final cTop = ctrl(tl, tr, c.topMidDev);
  final cRight = ctrl(tr, br, c.rightMidDev);
  final cBottom = ctrl(br, bl, c.bottomMidDev);
  final cLeft = ctrl(bl, tl, c.leftMidDev);

  Offset qbez(Offset p0, Offset ci, Offset p1, double t) {
    final mt = 1 - t, a = (1 - t) * (1 - t), b = 2 * mt * t, cc = t * t;
    return Offset(a * p0.dx + b * ci.dx + cc * p1.dx,
        a * p0.dy + b * ci.dy + cc * p1.dy);
  }

  Offset top(double u) => qbez(tl, cTop, tr, u);
  Offset bottom(double u) => qbez(bl, cBottom, br, u);
  Offset left(double v) => qbez(tl, cLeft, bl, v);
  Offset right(double v) => qbez(tr, cRight, br, v);

  double arc(Offset Function(double) curve) {
    double len = 0;
    Offset prev = curve(0);
    for (int i = 1; i <= 16; i++) {
      final p = curve(i / 16);
      len += (p - prev).distance;
      prev = p;
    }
    return len;
  }

  int outW = math.max(arc(top), arc(bottom)).round();
  int outH = math.max(arc(left), arc(right)).round();
  if (outW < 2 || outH < 2) {
    throw WarpException('degenerate quad: output too small');
  }
  final cap = args.maxDim;
  if (outW > cap || outH > cap) {
    final s = cap / math.max(outW, outH);
    outW = math.max(2, (outW * s).round());
    outH = math.max(2, (outH * s).round());
  }

  final output = img.Image(width: outW, height: outH, numChannels: src.numChannels);
  for (int dy = 0; dy < outH; dy++) {
    final v = dy / (outH - 1);
    final lc = left(v), rc = right(v);
    for (int dx = 0; dx < outW; dx++) {
      final u = dx / (outW - 1);
      final tc = top(u), bc = bottom(u);
      final bx = (1 - u) * (1 - v) * tl.dx + u * (1 - v) * tr.dx +
          (1 - u) * v * bl.dx + u * v * br.dx;
      final by = (1 - u) * (1 - v) * tl.dy + u * (1 - v) * tr.dy +
          (1 - u) * v * bl.dy + u * v * br.dy;
      final sx = (1 - v) * tc.dx + v * bc.dx + (1 - u) * lc.dx + u * rc.dx - bx;
      final sy = (1 - v) * tc.dy + v * bc.dy + (1 - u) * lc.dy + u * rc.dy - by;
      output.setPixel(dx, dy,
          src.getPixelInterpolate(sx, sy, interpolation: img.Interpolation.linear));
    }
  }
  return Uint8List.fromList(img.encodeJpg(output, quality: 92));
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/library/coons_warper_test.dart`
Expected: PASS (all 6).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/coons_warper.dart apps/mobile/test/features/library/coons_warper_test.dart
git commit -m "feat(crop): CoonsWarper — curved-boundary unwarp via Coons patch"
```

---

### Task 4: `HybridWarper` facade + wiring

**Files:**
- Create: `apps/mobile/lib/features/library/hybrid_warper.dart`
- Modify: `apps/mobile/lib/features/library/library_dependencies.dart:34`
- Test: `apps/mobile/test/features/library/hybrid_warper_test.dart`

**Interfaces:**
- Consumes: `ImageWarper`, `PerspectiveWarper`, `CoonsWarper`, `CropCorners`.
- Produces: `class HybridWarper implements ImageWarper` with `const HybridWarper({ImageWarper perspective = const PerspectiveWarper(), ImageWarper coons = const CoonsWarper()})`.

- [ ] **Step 1: Write the failing tests** — new file `hybrid_warper_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/image_warper.dart';

class _RecordingWarper implements ImageWarper {
  final String tag;
  final List<String> log;
  _RecordingWarper(this.tag, this.log);
  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) async {
    log.add(tag);
    return Uint8List(0);
  }
}

void main() {
  late List<String> log;
  late HybridWarper warper;
  setUp(() {
    log = [];
    warper = HybridWarper(
      perspective: _RecordingWarper('perspective', log),
      coons: _RecordingWarper('coons', log),
    );
  });

  final bytes = Uint8List(0);

  test('fullFrame → null, neither warper invoked', () async {
    expect(await warper.warp(bytes, CropCorners.fullFrame), isNull);
    expect(log, isEmpty);
  });

  test('straight crop → perspective path', () async {
    const straight = CropCorners(
      topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9));
    await warper.warp(bytes, straight);
    expect(log, ['perspective']);
  });

  test('bent crop → coons path', () async {
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9),
      topMidDev: Offset(0, -0.05));
    await warper.warp(bytes, bent);
    expect(log, ['coons']);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/library/hybrid_warper_test.dart`
Expected: FAIL — `hybrid_warper.dart` does not exist.

- [ ] **Step 3: Implement** — new file `hybrid_warper.dart`:

```dart
import 'dart:typed_data';

import 'coons_warper.dart';
import 'crop_corners.dart';
import 'image_warper.dart';
import 'perspective_warper.dart';

/// Routes a crop to the right unwarp engine: no-op for the full frame, exact
/// homography for straight crops (no perspective regression), and the Coons
/// patch only when an edge is bent.
class HybridWarper implements ImageWarper {
  final ImageWarper perspective;
  final ImageWarper coons;
  const HybridWarper({
    this.perspective = const PerspectiveWarper(),
    this.coons = const CoonsWarper(),
  });

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) {
    if (corners == CropCorners.fullFrame) return Future.value(null);
    return corners.isStraight
        ? perspective.warp(bytes, corners)
        : coons.warp(bytes, corners);
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/library/hybrid_warper_test.dart`
Expected: PASS (all 3).

- [ ] **Step 5: Wire it into the composition root** — in `library_dependencies.dart`, add the import and change the warper:

```dart
import 'hybrid_warper.dart';
```

Change line 34 from `warper: const PerspectiveWarper(),` to:

```dart
      warper: const HybridWarper(),
```

- [ ] **Step 6: Verify wiring compiles and library suite is green**

Run: `flutter test test/features/library/`
Expected: PASS (repository still uses `ImageWarper`; `perspective_warper_test` untouched).

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/hybrid_warper.dart apps/mobile/lib/features/library/library_dependencies.dart apps/mobile/test/features/library/hybrid_warper_test.dart
git commit -m "feat(crop): HybridWarper routes straight→homography, bent→coons; wire it"
```

---

### Task 5: `CropOverlay` — 8 draggable handles

**Files:**
- Modify: `apps/mobile/lib/features/scan/widgets/crop_overlay.dart` (`emitNew`, handle list)
- Test: `apps/mobile/test/features/scan/widgets/crop_overlay_test.dart`

**Interfaces:**
- Consumes: `CropCorners.copyWith`, `topCenter/rightCenter/bottomCenter/leftCenter`, `topMid/rightMid/bottomMid/leftMid`.
- Produces: handles keyed `crop-handle-{tl,tr,br,bl,top,right,bottom,left}`; midpoint drag emits a `CropCorners` with that edge's deviation set; corner drag preserves deviations.

- [ ] **Step 1: Write the failing tests** — append to `crop_overlay_test.dart` (reuse the file's existing pump helper if present; otherwise this self-contained form):

```dart
group('8 handles', () {
  CropCorners? emitted;
  Widget harness(CropCorners corners) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300, height: 300,
            child: CropOverlay(
              imageSize: const Size(300, 300),
              image: const SizedBox.expand(),
              corners: corners,
              onCornersChanged: (c) => emitted = c,
            ),
          ),
        ),
      );

  const straight = CropCorners(
    topLeft: Offset(0, 0), topRight: Offset(1, 0),
    bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1));

  testWidgets('renders 8 handles by key', (tester) async {
    await tester.pumpWidget(harness(straight));
    for (final r in ['tl', 'tr', 'br', 'bl', 'top', 'right', 'bottom', 'left']) {
      expect(find.byKey(Key('crop-handle-$r')), findsOneWidget, reason: r);
    }
  });

  testWidgets('dragging the top midpoint sets topMidDev, leaves corners', (tester) async {
    emitted = null;
    await tester.pumpWidget(harness(straight));
    await tester.drag(find.byKey(const Key('crop-handle-top')), const Offset(0, 30));
    await tester.pump();
    expect(emitted, isNotNull);
    expect(emitted!.topMidDev.dy, greaterThan(0));
    expect(emitted!.topLeft, straight.topLeft);
    expect(emitted!.bottomMidDev, Offset.zero);
  });

  testWidgets('dragging a corner preserves an existing bend', (tester) async {
    emitted = null;
    const bent = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.1));
    await tester.pumpWidget(harness(bent));
    await tester.drag(find.byKey(const Key('crop-handle-bl')), const Offset(15, -15));
    await tester.pump();
    expect(emitted, isNotNull);
    expect(emitted!.topMidDev, const Offset(0, 0.1)); // bend survives
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/features/scan/widgets/crop_overlay_test.dart -n "8 handles"`
Expected: FAIL — only 4 handles exist; midpoint keys not found.

- [ ] **Step 3: Implement** — in `crop_overlay.dart`, replace the `emitNew` function and the handle list.

Replace the whole `emitNew` closure (currently the `switch (role)` with 4 cases) with:

```dart
        void emitNew(String role, Offset newNorm) {
          switch (role) {
            case 'tl':
              onCornersChanged(corners.copyWith(topLeft: newNorm));
            case 'tr':
              onCornersChanged(corners.copyWith(topRight: newNorm));
            case 'br':
              onCornersChanged(corners.copyWith(bottomRight: newNorm));
            case 'bl':
              onCornersChanged(corners.copyWith(bottomLeft: newNorm));
            case 'top':
              onCornersChanged(
                  corners.copyWith(topMidDev: newNorm - corners.topCenter));
            case 'right':
              onCornersChanged(
                  corners.copyWith(rightMidDev: newNorm - corners.rightCenter));
            case 'bottom':
              onCornersChanged(corners.copyWith(
                  bottomMidDev: newNorm - corners.bottomCenter));
            case 'left':
              onCornersChanged(
                  corners.copyWith(leftMidDev: newNorm - corners.leftCenter));
          }
        }
```

Replace the four `buildHandle(...)` children in the returned `Stack` (the lines `buildHandle('tl', ...)` … `buildHandle('bl', ...)`) with midpoints FIRST, then corners (Stack order → corners hit-tested first):

```dart
            // Midpoints first so corners (added last) win overlapping hit-tests.
            buildHandle('top', 'Top edge midpoint', corners.topMid),
            buildHandle('right', 'Right edge midpoint', corners.rightMid),
            buildHandle('bottom', 'Bottom edge midpoint', corners.bottomMid),
            buildHandle('left', 'Left edge midpoint', corners.leftMid),
            buildHandle('tl', 'Top-left crop corner', corners.topLeft),
            buildHandle('tr', 'Top-right crop corner', corners.topRight),
            buildHandle('br', 'Bottom-right crop corner', corners.bottomRight),
            buildHandle('bl', 'Bottom-left crop corner', corners.bottomLeft),
```

(No change needed to `_DragHandle`: it already emits an absolute normalized position via `onNewNorm`; `emitNew` converts midpoint positions to deviations.)

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/scan/widgets/crop_overlay_test.dart`
Expected: PASS (new group green; existing corner-drag tests still green).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/scan/widgets/crop_overlay.dart apps/mobile/test/features/scan/widgets/crop_overlay_test.dart
git commit -m "feat(crop): CropOverlay renders 8 handles; midpoint drag bends edges"
```

---

### Task 6: `CropOverlay` — curved edge + mask rendering

**Files:**
- Modify: `apps/mobile/lib/features/scan/widgets/crop_overlay.dart` (`_QuadPainter`)
- Test: `apps/mobile/test/features/scan/widgets/crop_overlay_test.dart`

**Interfaces:**
- Consumes: `CropCorners.topMid/…` (resolved midpoints for control points).

- [ ] **Step 1: Write the failing test** — append (a golden-free structural check that the painter repaints on deviation change):

```dart
group('curved painter', () {
  testWidgets('painter repaints when a deviation changes', (tester) async {
    const straight = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1));
    const bent = CropCorners(
      topLeft: Offset(0, 0), topRight: Offset(1, 0),
      bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
      topMidDev: Offset(0, 0.1));
    Widget h(CropCorners c) => MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 200, height: 200,
                child: CropOverlay(
                    imageSize: const Size(200, 200),
                    image: const SizedBox.expand(),
                    corners: c,
                    onCornersChanged: (_) {}))));
    await tester.pumpWidget(h(straight));
    await tester.pumpWidget(h(bent)); // must not throw; painter picks up new shape
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('crop-overlay')), findsOneWidget);
  });
});
```

- [ ] **Step 2: Run to verify failure or baseline**

Run: `flutter test test/features/scan/widgets/crop_overlay_test.dart -n "curved painter"`
Expected: PASS structurally IF the painter still uses straight lines (this test guards against a repaint/throw regression). Proceed to make edges curved; keep this green.

- [ ] **Step 3: Implement** — replace `_QuadPainter`'s `paint` method and `shouldRepaint` so edges are quadratic Béziers through the resolved midpoints:

```dart
  Offset _ctrl(Offset a, Offset b, Offset devNorm) {
    final center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    return _p(center + devNorm * 2.0); // C = center + 2·dev, in pixels
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tl = _p(corners.topLeft), tr = _p(corners.topRight);
    final br = _p(corners.bottomRight), bl = _p(corners.bottomLeft);
    final cTop = _ctrl(corners.topLeft, corners.topRight, corners.topMidDev);
    final cRight =
        _ctrl(corners.topRight, corners.bottomRight, corners.rightMidDev);
    final cBottom =
        _ctrl(corners.bottomRight, corners.bottomLeft, corners.bottomMidDev);
    final cLeft = _ctrl(corners.bottomLeft, corners.topLeft, corners.leftMidDev);

    final quad = Path()
      ..moveTo(tl.dx, tl.dy)
      ..quadraticBezierTo(cTop.dx, cTop.dy, tr.dx, tr.dy)
      ..quadraticBezierTo(cRight.dx, cRight.dy, br.dx, br.dy)
      ..quadraticBezierTo(cBottom.dx, cBottom.dy, bl.dx, bl.dy)
      ..quadraticBezierTo(cLeft.dx, cLeft.dy, tl.dx, tl.dy)
      ..close();

    final outside = Path.combine(
        PathOperation.difference, Path()..addRect(Offset.zero & size), quad);
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawPath(
        quad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = highlightColor);
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.rect != rect ||
      old.corners != corners ||
      old.highlightColor != highlightColor;
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/features/scan/widgets/crop_overlay_test.dart`
Expected: PASS (curved painter test + all prior overlay tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/scan/widgets/crop_overlay.dart apps/mobile/test/features/scan/widgets/crop_overlay_test.dart
git commit -m "feat(crop): CropOverlay draws Bézier edges and curved dim mask"
```

---

### Task 7: On-device curved-warp integration test

**Files:**
- Create: `apps/mobile/integration_test/e4_curved_warp_test.dart`
- Modify: `docs/superpowers/plans/00-plans-index.md` (add this plan)

**Interfaces:**
- Consumes: `HybridWarper`, `CropCorners`.

- [ ] **Step 1: Write the integration test** — new file `e4_curved_warp_test.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/hybrid_warper.dart';

Uint8List _rectJpeg(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(10, 10, 10));
  img.fillRect(image, x1: w ~/ 5, y1: h ~/ 5, x2: 4 * w ~/ 5, y2: 4 * h ~/ 5,
      color: img.ColorRgb8(230, 230, 230));
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const warper = HybridWarper();

  testWidgets('bent-edge crop flattens to a decodable image on-device',
      (tester) async {
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.12), topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.88),
      topMidDev: Offset(0, -0.06), bottomMidDev: Offset(0, 0.05));
    final out = await warper.warp(_rectJpeg(1200, 900), bent);
    expect(out, isNotNull);
    expect(img.decodeImage(out!), isNotNull);
  });

  testWidgets('large curved image flattens within budget', (tester) async {
    const bent = CropCorners(
      topLeft: Offset(0.05, 0.05), topRight: Offset(0.95, 0.05),
      bottomRight: Offset(0.95, 0.95), bottomLeft: Offset(0.05, 0.95),
      leftMidDev: Offset(-0.04, 0));
    final bytes = _rectJpeg(3000, 2000);
    final start = DateTime.now();
    final out = await warper.warp(bytes, bent);
    final ms = DateTime.now().difference(start).inMilliseconds;
    expect(out, isNotNull);
    expect(ms, lessThan(4000), reason: 'curved warp budget; took ${ms}ms');
  });

  testWidgets('straight crop still routes through homography', (tester) async {
    const straight = CropCorners(
      topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9));
    final out = await warper.warp(_rectJpeg(800, 600), straight);
    expect(out, isNotNull); // non-null flat; perspective path exercised
  });
}
```

- [ ] **Step 2: Run on the connected device**

Run: `flutter test integration_test/e4_curved_warp_test.dart -d RZCY51D0T1K`
Expected: PASS (3/3). If the large-image budget fails, lower `CoonsWarper.maxDimension` (e.g. 1500) in `hybrid_warper.dart`'s `coons:` default and re-run.

- [ ] **Step 3: Update the plans index** — add a bullet under the current plans in `docs/superpowers/plans/00-plans-index.md` linking `2026-07-01-curved-crop-coons-warp.md` (follow the existing bullet format in that file).

- [ ] **Step 4: Full host suite regression gate**

Run: `flutter test`
Expected: no NEW failures vs. baseline (the pre-existing OpenCV host skips remain; everything else green).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/integration_test/e4_curved_warp_test.dart docs/superpowers/plans/00-plans-index.md
git commit -m "test(crop): on-device curved-warp integration; index the plan"
```

---

## Self-Review

**Spec coverage:**
- Data model (deviations, getters, isStraight, copyWith, clamp) → Task 1. Persistence (16/8) → Task 2. CoonsWarper → Task 3. Hybrid facade + wiring → Task 4. Overlay 8 handles + copyWith drag + hit order → Task 5. Bézier edges + curved mask → Task 6. Device verify + perf cap → Task 7. All spec sections mapped.

**Placeholder scan:** none — every code step contains full code and exact run commands.

**Type consistency:** `copyWith`, `topMidDev/rightMidDev/bottomMidDev/leftMidDev`, `topCenter/…`, `topMid/…`, `isStraight`, `HybridWarper({perspective, coons})`, `CoonsWarper({maxDimension})` are defined in Task 1/3/4 and used consistently in Tasks 5–7. The overlay's `emitNew` role strings match the handle keys (`top/right/bottom/left`).

**Open risk carried from spec:** Coons interior only corrects boundary/mild curl (not strong interior page curl) — a documented non-goal, validated for "decodable, sane size, within budget," not for perfect interior flattening.
