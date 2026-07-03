import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../library/crop_corners.dart';
import 'detector_geometry.dart';
import 'edge_detector.dart';

/// Runs the native detection pipeline for [bytes], returning the flat result
/// list (see [_runPipeline]) or null. Injectable so tests can exercise the
/// timeout guard without the native OpenCV library.
typedef PipelineRunner = Future<List<double>?> Function(Uint8List bytes);

/// Default runner: offloads the synchronous OpenCV pipeline to an isolate.
Future<List<double>?> _computeRunner(Uint8List bytes) =>
    compute(_runPipeline, bytes);

class OpenCvEdgeDetector implements EdgeDetector {
  /// Upper bound on a single [detect] call. If the native pipeline wedges
  /// (an isolate blocked in native C++ cannot be killed by Dart), the timeout
  /// lets [detect] return null instead of hanging its caller forever.
  final Duration timeout;
  final PipelineRunner _runner;

  const OpenCvEdgeDetector({this.timeout = const Duration(seconds: 5)})
      : _runner = _computeRunner;

  /// Test-only: inject a custom [runner] (e.g. a slow/never-completing stub) to
  /// exercise the timeout guard without loading libdartcv.
  @visibleForTesting
  OpenCvEdgeDetector.withRunner(
    PipelineRunner runner, {
    this.timeout = const Duration(seconds: 5),
  }) : _runner = runner;

  @override
  Future<DetectionResult?> detect(Uint8List bytes) async {
    final List<double>? raw;
    try {
      raw = await _runner(bytes).timeout(timeout);
    } on TimeoutException {
      // Native pipeline wedged — return null rather than hang the caller.
      return null;
    }
    if (raw == null) return null;
    return DetectionResult(
      corners: CropCorners(
        topLeft: Offset(raw[0], raw[1]),
        topRight: Offset(raw[2], raw[3]),
        bottomRight: Offset(raw[4], raw[5]),
        bottomLeft: Offset(raw[6], raw[7]),
      ),
      confidence: raw[8],
    );
  }
}

// ── Isolate entry point ────────────────────────────────────────────────────
// Must be top-level (not a method) — compute() requires it.
// ALL cv.* calls here are SYNCHRONOUS — never use *Async variants inside compute().
// Every native resource allocated here MUST be disposed in the finally block.

/// Longest side (px) to which a capture is downscaled before edge detection.
/// High-res frames carry fine texture (paper grain, desk grain) that Canny
/// turns into spurious contours; a modest working size is both more robust and
/// much faster. Corners are normalized to [0..1], so this is coordinate-safe.
const int _kDetectMaxSide = 1024;

/// Longest side (px) of the proxy used to estimate background illumination.
/// A small proxy makes the heavy blur cheap enough for the live sampling loop.
const int _kIllumProxySide = 256;

/// Gaussian sigma (in proxy pixels) for the illumination estimate. Large
/// relative to the proxy so only the low-frequency light field survives.
const double _kIllumSigma = 12.0;

/// Returns [tl.dx, tl.dy, tr.dx, tr.dy, br.dx, br.dy, bl.dx, bl.dy, confidence]
/// or null if no candidate quad is found or on any error.
List<double>? _runPipeline(Uint8List bytes) {
  cv.Mat? mat, gray, proxy, bgSmall, bg, normalized, blurred, otsuOut,
      edges, kernel, closed;
  cv.VecVec4i? hierarchy;
  cv.VecVecPoint? contours;
  try {
    // Step 1: Decode. imdecode returns an empty Mat (not an exception) for
    // corrupt bytes.
    mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (mat.isEmpty) return null;

    // Step 2: Downscale large captures so fine texture doesn't spawn spurious
    // edges. Corners are normalized below, so this does not shift the result.
    final longest = math.max(mat.rows, mat.cols);
    if (longest > _kDetectMaxSide) {
      final scale = _kDetectMaxSide / longest;
      final resized = cv.resize(
        mat,
        ((mat.cols * scale).round(), (mat.rows * scale).round()),
        interpolation: cv.INTER_AREA,
      );
      mat.dispose();
      mat = resized;
    }
    final rows = mat.rows;
    final cols = mat.cols;

    // Step 3: Grayscale.
    gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    mat.dispose();
    mat = null;

    // Step 4: Illumination normalization (flat-field). Estimate the local
    // background light on a small proxy (downscale → heavy blur → upscale),
    // then divide it out. This flattens a soft-shadow gradient so a
    // shadow-dimmed paper edge regains local contrast.
    final proxyLongest = math.max(rows, cols);
    final pScale =
        proxyLongest > _kIllumProxySide ? _kIllumProxySide / proxyLongest : 1.0;
    final pw = math.max(1, (cols * pScale).round());
    final ph = math.max(1, (rows * pScale).round());
    proxy = cv.resize(gray, (pw, ph), interpolation: cv.INTER_AREA);
    bgSmall = cv.gaussianBlur(proxy, (0, 0), _kIllumSigma);
    proxy.dispose();
    proxy = null;
    bg = cv.resize(bgSmall, (cols, rows), interpolation: cv.INTER_LINEAR);
    bgSmall.dispose();
    bgSmall = null;
    // normalized = saturate(gray * 255 / bg), CV_8U. divide() maps a
    // divide-by-zero to 0, so no guard is needed.
    normalized = cv.divide(gray, bg, scale: 255.0);
    gray.dispose();
    gray = null;
    bg.dispose();
    bg = null;

    // Step 5: Gaussian blur (5×5) on the normalized image.
    blurred = cv.gaussianBlur(normalized, (5, 5), 0);
    normalized.dispose();
    normalized = null;

    // Step 6: Adaptive Canny thresholds from Otsu's value on the blurred Mat.
    final (otsuT, oOut) =
        cv.threshold(blurred, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
    otsuOut = oOut;
    otsuOut.dispose();
    otsuOut = null;
    final hi = otsuT.clamp(40.0, 220.0);
    final lo = 0.5 * hi;
    edges = cv.canny(blurred, lo, hi);
    blurred.dispose();
    blurred = null;

    // Step 7: Morphological close to bridge short gaps into loops.
    kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel, iterations: 1);
    edges.dispose();
    edges = null;
    kernel.dispose();
    kernel = null;

    // Step 8: Find external contours.
    final contoursResult = cv.findContours(
      closed,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    contours = contoursResult.$1;
    hierarchy = contoursResult.$2;
    closed.dispose();
    closed = null;
    hierarchy.dispose();
    hierarchy = null;

    // Step 9: Relaxed quad extraction + scored selection. For every contour
    // ≥5% of the image, build a 4-corner quad (approxPolyDP if it yields a
    // convex quad, else the min-area rotated rectangle), score it, and keep
    // the best. Always returns a best-guess when any sizeable contour exists.
    final imageArea = (rows * cols).toDouble();
    final minQuadArea = imageArea * 0.05;
    List<Pt>? bestQuad;
    double bestConfidence = -1;
    for (int i = 0; i < contours.length; i++) {
      // contours[i] returns a reference owned by contours — do NOT dispose it.
      final contour = contours[i];
      final cArea = cv.contourArea(contour);
      if (cArea < minQuadArea) continue;

      List<Pt> quadPts;
      final epsilon = cv.arcLength(contour, true) * 0.02;
      final approx = cv.approxPolyDP(contour, epsilon, true);
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        quadPts = List.generate(
          4,
          (j) => (x: approx[j].x.toDouble(), y: approx[j].y.toDouble()),
        );
        approx.dispose();
      } else {
        approx.dispose();
        final rect = cv.minAreaRect(contour);
        final box = rect.points; // VecPoint2f, 4 corners
        quadPts = List.generate(4, (j) => (x: box[j].x, y: box[j].y));
        box.dispose();
        rect.dispose();
      }

      final roles = sortCornerRoles(quadPts); // [TL, TR, BR, BL]
      final qArea = quadArea(roles);
      if (qArea <= 0) continue;
      final areaScore = (qArea / imageArea).clamp(0.0, 1.0);
      final aScore = angleScore(roles);
      final rScore = rectangularityScore(cArea, qArea);
      final conf = detectionConfidence(
        areaScore: areaScore,
        angleScore: aScore,
        rectScore: rScore,
      );
      if (conf > bestConfidence) {
        bestConfidence = conf;
        bestQuad = roles;
      }
    }

    contours.dispose();
    contours = null;

    if (bestQuad == null) return null;

    // Step 10: Normalize to [0..1] and emit.
    final tl = bestQuad[0], tr = bestQuad[1], br = bestQuad[2], bl = bestQuad[3];
    return [
      tl.x / cols, tl.y / rows,
      tr.x / cols, tr.y / rows,
      br.x / cols, br.y / rows,
      bl.x / cols, bl.y / rows,
      bestConfidence,
    ];
  } catch (_) {
    return null;
  } finally {
    // Dispose every native resource that may still be allocated.
    mat?.dispose();
    gray?.dispose();
    proxy?.dispose();
    bgSmall?.dispose();
    bg?.dispose();
    normalized?.dispose();
    blurred?.dispose();
    otsuOut?.dispose();
    edges?.dispose();
    kernel?.dispose();
    closed?.dispose();
    hierarchy?.dispose();
    contours?.dispose();
  }
}
