import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../core/async/with_isolate_timeout.dart';
import 'crop_corners.dart';
import 'enhancer_mode.dart';
import 'native_enhancers.dart';
import 'native_perspective_warper.dart';
import 'page_processor.dart';
import 'perspective_warper.dart' show kDefaultFlatMaxDimension;
import 'work_resolution.dart';

/// Runs the native page pipeline for one image, returning the encoded JPEG or
/// null. Injectable so tests can exercise the timeout/fallback handoff without
/// the native OpenCV library — mirrors [OpenCvEdgeDetector]'s `PipelineRunner`.
typedef NativeProcessRunner =
    Future<Uint8List?> Function(
      Uint8List bytes,
      CropCorners corners,
      EnhancerMode mode,
    );

/// Default runner: offloads the synchronous OpenCV pipeline ([_nativeFn]) to an
/// isolate. The timeout is applied by [NativePageProcessor.process], not here,
/// so the runner is a clean injection seam.
Future<Uint8List?> _computeRunner(
  Uint8List bytes,
  CropCorners corners,
  EnhancerMode mode,
) => compute(_nativeFn, _NativeArgs(bytes, corners, mode));

/// Native OpenCV (dartcv) page pipeline: imdecode → warpPerspective (straight
/// crops; capped ≤3500) → filter(mode) → imencode. A thin orchestrator (P08):
/// isolate + timeout + dispatch, delegating the warp to
/// `native_perspective_warper` and the filters to `native_enhancers` (mirroring
/// the Dart module layout). Runs in a [compute] isolate wrapped with a timeout —
/// a wedged native isolate cannot be killed from Dart, so the timeout is the
/// recovery. Returns null for anything it does not handle (bent crop, corrupt
/// input, failure, timeout) so a fallback can take over.
class NativePageProcessor implements PageProcessor {
  final Duration timeout;
  final NativeProcessRunner _runner;

  const NativePageProcessor({this.timeout = const Duration(seconds: 5)})
    : _runner = _computeRunner;

  /// Test-only: inject a custom [runner] (e.g. a slow/never-completing or
  /// failing stub) to exercise the timeout/fallback handoff without loading
  /// libdartcv. Mirrors [OpenCvEdgeDetector.withRunner].
  @visibleForTesting
  NativePageProcessor.withRunner(
    NativeProcessRunner runner, {
    this.timeout = const Duration(seconds: 5),
  }) : _runner = runner;

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
      return await withIsolateTimeout(
        () => _runner(bytes, corners, mode),
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
        warped = cv.resize(src, (
          wr.targetW,
          wr.targetH,
        ), interpolation: cv.INTER_AREA);
      }
    } else {
      warped = warpStraight(src, a.corners);
    }

    // Filter dispatch mirrors the Dart `*_enhancer` modules (P08 split).
    // For `none` we encode `warped` directly (no redundant full-res clone); it
    // is owned by the outer finally, so `filtered` stays null and is NOT
    // disposed here. Every other mode returns a newly-allocated Mat that this
    // inner finally owns and disposes exactly once.
    final warpedMat = warped;
    cv.Mat? filtered;
    try {
      filtered = switch (a.mode) {
        EnhancerMode.auto => autoFlatField(warpedMat),
        EnhancerMode.color => colorBoost(warpedMat),
        EnhancerMode.grayscale => grayscale(warpedMat),
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
    // Invariant: `warped` is ALWAYS a distinct Mat from `src` — a clone (equal-
    // res full frame), a resize (downscaled full frame), or a fresh warp — never
    // an alias. Disposing both is therefore exactly one free each. A future
    // "drop the redundant clone" optimization that set `warped = src` would
    // double-free; this assert locks the invariant in debug builds.
    assert(warped == null || !identical(warped, src));
    src?.dispose();
    warped?.dispose();
  }
}
