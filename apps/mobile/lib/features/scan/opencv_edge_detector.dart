import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../library/crop_corners.dart';
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

/// Returns [tl.dx, tl.dy, tr.dx, tr.dy, br.dx, br.dy, bl.dx, bl.dy, confidence]
/// or null if no convex 4-point quad is found or on any error.
List<double>? _runPipeline(Uint8List bytes) {
  cv.Mat? mat, gray, blurred, edges;
  cv.VecVec4i? hierarchy;
  cv.VecVecPoint? contours;
  cv.VecPoint? best;
  try {
    // Step 1: Decode. imdecode returns empty Mat (NOT an exception) for corrupt bytes.
    mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (mat.isEmpty) return null;

    // Step 1b: Downscale large captures so fine texture doesn't spawn spurious
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

    // Step 2: Grayscale
    gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    mat.dispose();
    mat = null;

    // Step 3: Gaussian blur (5×5 kernel, sigma auto)
    blurred = cv.gaussianBlur(gray, (5, 5), 0);
    gray.dispose();
    gray = null;

    // Step 4: Canny edge detection
    edges = cv.canny(blurred, 75.0, 200.0);
    blurred.dispose();
    blurred = null;

    // Step 5: Find external contours.
    // findContours returns (Contours, VecVec4i) where Contours = VecVecPoint.
    final contoursResult = cv.findContours(
      edges,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    contours = contoursResult.$1;
    hierarchy = contoursResult.$2;
    edges.dispose();
    edges = null;
    // Hierarchy is not used for logic; dispose early.
    hierarchy.dispose();
    hierarchy = null;

    // Step 6: Find the largest convex 4-point approximation.
    // Skip quads whose area is less than 5% of the image — per spec:
    // "Rect occupying < 5% of image → null or confidence < 0.3."
    // Because the confidence formula floors at ~0.4 for any detected rect,
    // the only compliant path is to gate here and return null.
    final minQuadArea = rows * cols * 0.05;
    double bestArea = 0;
    for (int i = 0; i < contours.length; i++) {
      // contours[i] returns a reference owned by contours — do NOT dispose it.
      final contour = contours[i];
      final epsilon = cv.arcLength(contour, true) * 0.02;
      final approx = cv.approxPolyDP(contour, epsilon, true);
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        final area = cv.contourArea(approx);
        if (area >= minQuadArea && area > bestArea) {
          bestArea = area;
          best?.dispose(); // release previous best before replacing
          best = approx;
        } else {
          approx.dispose();
        }
      } else {
        approx.dispose();
      }
    }

    contours.dispose();
    contours = null;

    if (best == null) return null;

    // Step 7: Extract points into pure Dart records before closing the isolate.
    // Extract to a final local so the closure in List.generate sees a non-null
    // binding (Dart flow analysis doesn't propagate nullable promotions into
    // lambda captures).
    final bestPoints = best;
    final pts = List.generate(
      bestPoints.length,
      (i) => (x: bestPoints[i].x.toDouble(), y: bestPoints[i].y.toDouble()),
    );

    best.dispose();
    best = null;

    // Step 8: Sort into canonical corner roles.
    // topLeft = smallest (x + y); bottomRight = largest (x + y)
    pts.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final tl = pts.first;
    final br = pts.last;

    // topRight = smallest (y − x); bottomLeft = largest (y − x)
    pts.sort((a, b) => (a.y - a.x).compareTo(b.y - b.x));
    final tr = pts.first;
    final bl = pts.last;

    // Step 9: Normalize to [0..1] using image dimensions captured before disposal.
    final tlDx = tl.x / cols, tlDy = tl.y / rows;
    final trDx = tr.x / cols, trDy = tr.y / rows;
    final brDx = br.x / cols, brDy = br.y / rows;
    final blDx = bl.x / cols, blDy = bl.y / rows;

    // Step 10: Confidence scoring.
    final areaScore = (bestArea / (rows * cols)).clamp(0.0, 1.0);

    // Compute mean interior angle error vs. ideal 90° for the four corners.
    // Corner order: TL → TR → BR → BL for interior angle measurement.
    final cornersForAngle = [tl, tr, br, bl];
    double totalErr = 0;
    for (int i = 0; i < 4; i++) {
      final prev = cornersForAngle[(i + 3) % 4];
      final curr = cornersForAngle[i];
      final next = cornersForAngle[(i + 1) % 4];
      final v1x = prev.x - curr.x, v1y = prev.y - curr.y;
      final v2x = next.x - curr.x, v2y = next.y - curr.y;
      final m1 = math.sqrt(v1x * v1x + v1y * v1y);
      final m2 = math.sqrt(v2x * v2x + v2y * v2y);
      if (m1 < 1e-6 || m2 < 1e-6) continue;
      final cosA =
          ((v1x * v2x + v1y * v2y) / (m1 * m2)).clamp(-1.0, 1.0);
      totalErr += (math.acos(cosA) * 180 / math.pi - 90).abs();
    }
    final angleScore = (1.0 - totalErr / (4 * 90)).clamp(0.0, 1.0);
    final confidence = (0.6 * areaScore + 0.4 * angleScore).clamp(0.0, 1.0);

    return [tlDx, tlDy, trDx, trDy, brDx, brDy, blDx, blDy, confidence];
  } catch (_) {
    return null;
  } finally {
    // Dispose every native resource that may still be allocated.
    // Setting to null after explicit dispose prevents double-dispose.
    mat?.dispose();
    gray?.dispose();
    blurred?.dispose();
    edges?.dispose();
    hierarchy?.dispose();
    contours?.dispose();
    best?.dispose();
  }
}
