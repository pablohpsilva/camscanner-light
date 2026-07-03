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

/// Gaussian blur kernel side (odd) applied before Otsu, to suppress text and
/// texture so the whole page reads as one region.
const int _kSegBlur = 7;

/// The morphological-close kernel side is `round(cols / _kSegKernelDivisor)`
/// (odd-ized). Large enough to bridge interior text into a solid page blob,
/// proportional to the working-image width.
const int _kSegKernelDivisor = 30;

/// Returns [tl.dx, tl.dy, tr.dx, tr.dy, br.dx, br.dy, bl.dx, bl.dy, confidence]
/// or null if no plausible page quad is found or on any error.
///
/// Dual-polarity Otsu region segmentation: threshold the blurred grayscale into
/// a bright mask (page brighter than background) and its inverse (page darker),
/// close interior text into a solid blob, take the largest contour, fit a quad,
/// guard against blank/clutter blobs, and keep the highest-confidence survivor.
List<double>? _runPipeline(Uint8List bytes) {
  cv.Mat? mat, gray, blurred, maskBright, maskDark;
  try {
    // Step 1: Decode. imdecode returns an empty Mat for corrupt bytes.
    mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (mat.isEmpty) return null;

    // Step 2: Downscale large captures (coordinate-safe: corners normalized).
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
    final imageArea = (rows * cols).toDouble();

    // Step 3: Grayscale.
    gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    mat.dispose();
    mat = null;

    // Step 4: Blur so text/texture doesn't fragment the page region.
    blurred = cv.gaussianBlur(gray, (_kSegBlur, _kSegBlur), 0);
    gray.dispose();
    gray = null;

    // Step 5: Otsu → bright mask (page-brighter) + the inverse dark mask
    // (page-darker), so both polarities are considered.
    final (otsuT, mb) =
        cv.threshold(blurred, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
    maskBright = mb;
    final (_, md) = cv.threshold(blurred, otsuT, 255, cv.THRESH_BINARY_INV);
    maskDark = md;
    blurred.dispose();
    blurred = null;

    // Close-kernel side proportional to width, odd.
    var kseg = math.max(3, (cols / _kSegKernelDivisor).round());
    if (kseg.isEven) kseg += 1;

    List<Pt>? bestQuad;
    double bestConfidence = -1;

    // Step 6: For each polarity, close → largest contour → quad → guard → score.
    // Iterate the non-null locals `mb`/`md` (maskBright/maskDark hold the same
    // handles for disposal in `finally`).
    for (final mask in [mb, md]) {
      cv.Mat? kernel, closed;
      cv.VecVec4i? hierarchy;
      cv.VecVecPoint? contours;
      try {
        kernel = cv.getStructuringElement(cv.MORPH_RECT, (kseg, kseg));
        closed = cv.morphologyEx(mask, cv.MORPH_CLOSE, kernel, iterations: 1);

        final contoursResult = cv.findContours(
          closed,
          cv.RETR_EXTERNAL,
          cv.CHAIN_APPROX_SIMPLE,
        );
        contours = contoursResult.$1;
        hierarchy = contoursResult.$2;

        // Largest contour with area ≥ 5% of the image.
        int bestIdx = -1;
        double bestContourArea = 0;
        for (int i = 0; i < contours.length; i++) {
          final a = cv.contourArea(contours[i]);
          if (a >= imageArea * 0.05 && a > bestContourArea) {
            bestContourArea = a;
            bestIdx = i;
          }
        }
        if (bestIdx < 0) continue;
        final contour = contours[bestIdx]; // owned by contours — do not dispose

        // Build a quad: approxPolyDP if 4-pt convex (perspective fit), else
        // the min-area rotated rectangle.
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
        final areaFrac = qArea / imageArea;
        final fill = rectangularityScore(bestContourArea, qArea);
        if (!isPlausiblePage(areaFrac: areaFrac, fill: fill)) continue;

        final conf = detectionConfidence(
          areaScore: areaFrac.clamp(0.0, 1.0),
          angleScore: angleScore(roles),
          rectScore: fill,
        );
        if (conf > bestConfidence) {
          bestConfidence = conf;
          bestQuad = roles;
        }
      } finally {
        kernel?.dispose();
        closed?.dispose();
        hierarchy?.dispose();
        contours?.dispose();
      }
    }

    if (bestQuad == null) return null;

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
    mat?.dispose();
    gray?.dispose();
    blurred?.dispose();
    maskBright?.dispose();
    maskDark?.dispose();
  }
}
