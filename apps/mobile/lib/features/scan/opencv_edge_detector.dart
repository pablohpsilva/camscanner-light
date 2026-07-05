import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../library/crop_corners.dart';
import 'camera_frame.dart';
import 'detector_geometry.dart';
import 'edge_detector.dart';
import 'frame_reducer.dart';
import 'gray_frame.dart';

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
    return _resultFromFlat(raw);
  }

  @override
  Future<DetectionResult?> detectFrame(CameraFrame frame) async {
    try {
      final gray = reduceToGray(frame, maxSide: _kLiveDetectMaxSide);
      final flat = await compute(_segmentGrayFrame, gray).timeout(timeout);
      if (flat == null) return null;
      return _resultFromFlat(flat);
    } catch (_) {
      return null;
    }
  }
}

/// Maps a flat 9-element result list to a [DetectionResult].
DetectionResult _resultFromFlat(List<double> flat) => DetectionResult(
      corners: CropCorners(
        topLeft: Offset(flat[0], flat[1]),
        topRight: Offset(flat[2], flat[3]),
        bottomRight: Offset(flat[4], flat[5]),
        bottomLeft: Offset(flat[6], flat[7]),
      ),
      confidence: flat[8],
    );

// ── Isolate entry point ────────────────────────────────────────────────────
// Must be top-level (not a method) — compute() requires it.
// ALL cv.* calls here are SYNCHRONOUS — never use *Async variants inside compute().
// Every native resource allocated here MUST be disposed in the finally block.

/// Longest side (px) to which a capture is downscaled before edge detection.
/// High-res frames carry fine texture (paper grain, desk grain) that Canny
/// turns into spurious contours; a modest working size is both more robust and
/// much faster. Corners are normalized to [0..1], so this is coordinate-safe.
const int _kDetectMaxSide = 1024;

/// Longest side (px) for LIVE frame detection — coarser than the still path
/// (`_kDetectMaxSide`) because the live overlay is only a guide; the final crop
/// corners come from `detect()` on the full-resolution still.
const int _kLiveDetectMaxSide = 400;

/// Gaussian blur kernel side (odd) applied before Otsu, to suppress text and
/// texture so the whole page reads as one region.
const int _kSegBlur = 7;

/// The morphological-close kernel side is `round(cols / _kSegKernelDivisor)`
/// (odd-ized). Large enough to bridge interior text into a solid page blob,
/// proportional to the working-image width.
const int _kSegKernelDivisor = 30;

/// Ascending fractions of the hull perimeter for the quad-fit ε sweep. The
/// smallest fraction yielding a 4-point convex quad wins; larger fractions
/// simplify away small edge protrusions/nubs. Mirrors detect_probe.py.
const List<double> _kSegEpsFracs = [0.01, 0.02, 0.03, 0.04, 0.05];

/// Returns [tl.dx, tl.dy, tr.dx, tr.dy, br.dx, br.dy, bl.dx, bl.dy, confidence]
/// or null if no plausible page quad is found or on any error.
///
/// Dual-polarity Otsu region segmentation: threshold the blurred grayscale into
/// a bright mask (page brighter than background) and its inverse (page darker),
/// close interior text into a solid blob, take the largest contour, fit a quad,
/// guard against blank/clutter blobs, and keep the highest-confidence survivor.
List<double>? _runPipeline(Uint8List bytes) {
  cv.Mat? mat;
  try {
    // Step 1: Decode. imdecode returns an empty Mat for corrupt bytes.
    mat = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (mat.isEmpty) {
      mat.dispose();
      return null;
    }
    return _runPipelineOnMat(mat); // takes ownership: disposes `mat`
  } catch (_) {
    mat?.dispose();
    return null;
  }
}

/// Isolate entry (top-level, for `compute()`): wraps a [GrayFrame]'s single-channel
/// bytes as a CV_8UC1 Mat and runs the shared segmentation. Returns the flat
/// 9-element result (see [_resultFromFlat]) or null.
List<double>? _segmentGrayFrame(GrayFrame frame) {
  cv.Mat? gray;
  try {
    gray = cv.Mat.fromList(
        frame.height, frame.width, cv.MatType.CV_8UC1, frame.bytes);
    if (gray.isEmpty) {
      gray.dispose();
      return null;
    }
    final out = _segmentGray(gray); // takes ownership: disposes `gray`
    gray = null;
    return out;
  } catch (_) {
    gray?.dispose();
    return null;
  }
}

/// Still-capture front-end: downscale a large capture to `_kDetectMaxSide`,
/// convert to gray, then segment. Takes ownership of [bgr].
List<double>? _runPipelineOnMat(cv.Mat bgr) {
  cv.Mat? mat = bgr, gray;
  try {
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
    gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    mat.dispose();
    mat = null;
    final out = _segmentGray(gray); // takes ownership: disposes `gray`
    gray = null;
    return out;
  } catch (_) {
    return null;
  } finally {
    mat?.dispose();
    gray?.dispose();
  }
}

/// Shared segmentation core (steps 4-7). Takes ownership of [gray] (single-channel
/// CV_8UC1) and disposes it and all intermediates. Returns the flat 9-element
/// result (see [_resultFromFlat]) or null.
List<double>? _segmentGray(cv.Mat gray) {
  cv.Mat? g = gray, blurred, maskBright, maskDark;
  try {
    final rows = g.rows;
    final cols = g.cols;
    final imageArea = (rows * cols).toDouble();

    // Step 4: Blur so text/texture doesn't fragment the page region.
    blurred = cv.gaussianBlur(g, (_kSegBlur, _kSegBlur), 0);
    g.dispose();
    g = null;

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
    // handles for disposal in `finally`.
    for (final mask in [mb, md]) {
      cv.Mat? kernel, closed, hullMat;
      cv.VecVec4i? hierarchy;
      cv.VecVecPoint? contours;
      cv.VecPoint? hull;
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

        // Tight quad fit: the convex hull drops interior/text jaggedness, then
        // an ascending ε sweep takes the smallest simplification that yields a
        // 4-point convex quad sitting on the true page edges. minAreaRect is the
        // last resort only when no ε gives a clean quad (it bounds every
        // protrusion, so it reads slightly loose). Mirrors detect_probe.py.
        List<Pt>? quadPts;
        // hull/hullMat are disposed in the per-polarity `finally` so a throw
        // from any native call below cannot leak them in the isolate.
        hullMat = cv.convexHull(contour);
        hull = cv.VecPoint.fromMat(hullMat);
        final peri = cv.arcLength(hull, true);
        for (final frac in _kSegEpsFracs) {
          final approx = cv.approxPolyDP(hull, peri * frac, true);
          if (approx.length == 4) {
            final cand = List<Pt>.generate(
              4,
              (j) => (x: approx[j].x.toDouble(), y: approx[j].y.toDouble()),
            );
            approx.dispose();
            if (isConvexQuad(cand)) {
              quadPts = cand;
              break;
            }
          } else {
            approx.dispose();
          }
        }
        if (quadPts == null) {
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
        hull?.dispose();
        hullMat?.dispose();
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
    g?.dispose();
    blurred?.dispose();
    maskBright?.dispose();
    maskDark?.dispose();
  }
}
