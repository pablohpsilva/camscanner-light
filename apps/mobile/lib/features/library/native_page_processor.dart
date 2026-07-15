import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../core/async/with_isolate_timeout.dart';
import 'auto_enhancer.dart'
    show
        kAutoProxyLongSide,
        kAutoDilateRadius,
        kAutoBlurRadius,
        kAutoWhiteClip,
        kAutoBlackAnchor,
        kAutoMaxGain;
import 'crop_corners.dart';
import 'enhancer_mode.dart';
import 'page_processor.dart';
import 'perspective_warper.dart' show kDefaultFlatMaxDimension;
import 'work_resolution.dart';

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
    Uint8List bytes,
    CropCorners corners,
    EnhancerMode mode,
  ) async {
    if (mode == EnhancerMode.none && corners == CropCorners.fullFrame) {
      return null; // nothing to do
    }
    if (corners != CropCorners.fullFrame && !corners.isStraight) {
      return null; // bent crop → defer to Dart Coons
    }
    try {
      return await computeWithTimeout(
        _nativeFn,
        _NativeArgs(bytes, corners, mode),
        timeout: timeout,
      );
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

    // Warp straight crops; full frame passes through unwarped but is downscaled
    // to a bounded working resolution (still ≥ kDefaultFlatMaxDimension) so the
    // float passes in _autoFlatField don't allocate against an ultra-high-res
    // Mat. Normal-sized inputs (longest ≤ cap) are cloned unchanged.
    if (a.corners == CropCorners.fullFrame) {
      final wr = computeWorkResolution(
        src.cols,
        src.rows,
        kDefaultFlatMaxDimension,
      );
      if (wr.scale == 1.0) {
        warped = src.clone();
      } else {
        warped = cv.resize(
          src,
          (wr.targetW, wr.targetH),
          interpolation: cv.INTER_AREA,
        );
      }
    } else {
      warped = _warpStraight(src, a.corners);
    }

    // Filter dispatch: auto → flat-field; Color/Grayscale added in Task 6.
    // For `none` we encode `warped` directly (no redundant full-res clone); it
    // is owned by the outer finally, so `filtered` stays null and is NOT
    // disposed here. Every other mode returns a newly-allocated Mat that this
    // inner finally owns and disposes exactly once.
    final warpedMat = warped;
    cv.Mat? filtered;
    try {
      filtered = switch (a.mode) {
        EnhancerMode.auto => _autoFlatField(warpedMat),
        EnhancerMode.color => _colorBoost(warpedMat),
        EnhancerMode.grayscale => _grayscale(warpedMat),
        EnhancerMode.none => null,
      };
      final toEncode = filtered ?? warpedMat;
      final quality = a.mode == EnhancerMode.auto ? 95 : 92;
      final vecParams = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, quality]);
      try {
        final (ok, out) = cv.imencode('.jpg', toEncode, params: vecParams);
        return ok ? out : null;
      } finally {
        vecParams.dispose();
      }
    } finally {
      filtered?.dispose();
    }
  } catch (_) {
    return null;
  } finally {
    src?.dispose();
    warped?.dispose();
  }
}

/// Per-channel flat-field + white-point finish — the native mirror of
/// [autoEnhanceOriented] in auto_enhancer.dart, using the same constants.
/// Input [src] is a BGR CV_8UC3 Mat (OpenCV native order). Returns a new
/// CV_8UC3 BGR Mat owned by the caller.
cv.Mat _autoFlatField(cv.Mat src) {
  final rows = src.rows, cols = src.cols;
  // Explicit kernel size matches Dart's img.gaussianBlur(radius: kAutoBlurRadius)
  // which uses a (2*radius+1) × (2*radius+1) kernel with sigma = radius*(2/3).
  final blurKernel = 2 * kAutoBlurRadius + 1;
  final blurSigma = kAutoBlurRadius * 2.0 / 3.0;

  cv.Mat? proxy,
      kernel,
      dilated,
      blurred,
      bg,
      bgF,
      bgFloored,
      floorMat,
      srcF,
      flatF,
      flat,
      lut;
  try {
    // 1. Background estimate: resize to proxy → dilate(15×15) → blur.
    final longest = cols > rows ? cols : rows;
    final scale = longest > kAutoProxyLongSide
        ? kAutoProxyLongSide / longest
        : 1.0;
    final pw = (cols * scale).round().clamp(1, cols);
    final ph = (rows * scale).round().clamp(1, rows);
    proxy = cv.resize(src, (pw, ph), interpolation: cv.INTER_AREA);
    final k = 2 * kAutoDilateRadius + 1; // 15
    kernel = cv.getStructuringElement(cv.MORPH_RECT, (k, k));
    dilated = cv.dilate(proxy, kernel);
    // Exact match to Dart: same kernel size and sigma derived from radius.
    blurred = cv.gaussianBlur(dilated, (blurKernel, blurKernel), blurSigma);
    bg = cv.resize(blurred, (cols, rows), interpolation: cv.INTER_LINEAR);

    // 2. Flatten: px*255 / max(bg, 255/maxGain) on float Mats (no truncation).
    final floorVal = 255.0 / kAutoMaxGain; // 42.5
    bgF = bg.convertTo(cv.MatType.CV_32FC3);
    floorMat = cv.Mat.fromScalar(
      rows,
      cols,
      cv.MatType.CV_32FC3,
      cv.Scalar.all(floorVal),
    );
    bgFloored = cv.max(bgF, floorMat);
    srcF = src.convertTo(cv.MatType.CV_32FC3);
    flatF = cv.divide(srcF, bgFloored, scale: 255); // srcF*255/bgFloored
    flat = flatF.convertTo(cv.MatType.CV_8UC3); // saturate to [0,255]

    // 3. White-point stretch via per-channel 3-channel LUT (BGR).
    lut = _whitePointLut3(flat);
    return cv.LUT(flat, lut);
  } finally {
    for (final m in [
      proxy,
      kernel,
      dilated,
      blurred,
      bg,
      bgF,
      bgFloored,
      floorMat,
      srcF,
      flatF,
      flat,
      lut,
    ]) {
      m?.dispose();
    }
  }
}

/// Builds a 1×256 CV_8UC3 LUT reproducing auto_enhancer.dart's per-channel
/// white-point stretch (kAutoWhiteClip clip, kAutoBlackAnchor, linear). Reads
/// the flattened Mat's raw BGR bytes to build histograms per channel (B/G/R),
/// then returns a disposable LUT Mat for use with [cv.LUT].
cv.Mat _whitePointLut3(cv.Mat flat) {
  final data = flat.data; // interleaved BGR bytes: rows*cols*3
  final n = flat.rows * flat.cols;
  final hist = [
    List<int>.filled(256, 0), // B
    List<int>.filled(256, 0), // G
    List<int>.filled(256, 0), // R
  ];
  for (var i = 0; i < data.length; i += 3) {
    hist[0][data[i]]++;
    hist[1][data[i + 1]]++;
    hist[2][data[i + 2]]++;
  }
  final clip = (n * kAutoWhiteClip).ceil().clamp(1, n);
  // Flat 768-element list: [b0,g0,r0, b1,g1,r1, ...] matching BGR channel order.
  final lut = List<int>.filled(256 * 3, 0);
  // Default: identity for all channels.
  for (var v = 0; v < 256; v++) {
    lut[v * 3] = v;
    lut[v * 3 + 1] = v;
    lut[v * 3 + 2] = v;
  }
  for (var ch = 0; ch < 3; ch++) {
    final hc = hist[ch];
    int hi = 255, cum = 0;
    while (hi > 0 && cum + hc[hi] < clip) {
      cum += hc[hi--];
    }
    if (hi <= 0) continue;
    final anchor = (hi * kAutoBlackAnchor).round();
    if (hi <= anchor) continue;
    final span = hi - anchor;
    for (var v = anchor + 1; v < 256; v++) {
      lut[v * 3 + ch] = (anchor + (v - anchor) * 255 ~/ span).clamp(0, 255);
    }
  }
  return cv.Mat.fromList(1, 256, cv.MatType.CV_8UC3, lut);
}

/// Contrast 1.1 + brightness 1.05 via a 1×256 CV_8UC1 LUT applied to every
/// channel: v' = clamp((v−128)*1.1 + 128, then *1.05, 0..255).
/// The intermediate LUT Mat is disposed before returning.
cv.Mat _colorBoost(cv.Mat src) {
  final lut = List<int>.filled(256, 0);
  for (var v = 0; v < 256; v++) {
    final c = (v - 128) * 1.1 + 128;
    lut[v] = (c * 1.05).round().clamp(0, 255);
  }
  cv.Mat? lutMat;
  try {
    lutMat = cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, lut);
    return cv.LUT(src, lutMat); // 1-ch LUT applies to every channel
  } finally {
    lutMat?.dispose();
  }
}

/// Luminance grayscale, re-expanded to 3 channels so the JPEG encoder sees BGR.
/// The intermediate gray Mat is disposed before returning.
cv.Mat _grayscale(cv.Mat src) {
  cv.Mat? gray;
  try {
    gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
    return cv.cvtColor(gray, cv.COLOR_GRAY2BGR);
  } finally {
    gray?.dispose();
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
