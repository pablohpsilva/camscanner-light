import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'crop_corners.dart';

/// Pure output-size rule for a straight-crop perspective warp (P08): the longer
/// of each pair of opposite edges (measured in SOURCE pixels for a [w]×[h]
/// image), each dimension at least 2, then scaled down uniformly so the longest
/// side is ≤ [cap]. cv-free so it is host-unit-testable; the native warp
/// (`native_perspective_warper.dart`) calls this, then only does the cv
/// transform/warp. Kept byte-identical to the original inline computation so
/// device parity is unchanged. (P09 may unify this with the Dart geometry.)
(int, int) nativeWarpOutputSize(CropCorners c, int w, int h, int cap) {
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
  if (longest > cap) {
    final s = cap / longest;
    pxW = (pxW * s).round();
    if (pxW < 2) pxW = 2;
    pxH = (pxH * s).round();
    if (pxH < 2) pxH = 2;
  }
  return (pxW, pxH);
}
