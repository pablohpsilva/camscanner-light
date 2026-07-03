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
    final vecParams = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]);
    try {
      final (ok, out) = cv.imencode('.jpg', warped, params: vecParams);
      return ok ? out : null;
    } finally {
      vecParams.dispose();
    }
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
