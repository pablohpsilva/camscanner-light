import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;

import '../../core/async/with_isolate_timeout.dart';
import 'bilinear_sampler.dart';
import 'crop_corners.dart';
import 'image_warper.dart';
import 'work_resolution.dart';

/// Super-sampling headroom for the SOURCE buffer that feeds the warp sampling
/// loop. The rectified OUTPUT is already capped at [kDefaultFlatMaxDimension];
/// this bounds the SOURCE we sample from to this multiple of that cap so a
/// ~19 MP capture no longer materializes a ~57 MB full-res RGB buffer for a
/// small output. 2× keeps enough oversampling that output sharpness (bilinear
/// down-tap) is visually indistinguishable from sampling the full-res source.
const int kWarpSourceCapMultiplier = 2;

/// Test-only: the `(width, height)` of the source buffer the last
/// [warpPerspectiveToImage] call actually sampled — the bounded size when the
/// source exceeded `kWarpSourceCapMultiplier × maxDim`, else the original size.
@visibleForTesting
(int, int)? lastSampledSourceSize;

/// Default cap on the rectified page's long side (px). A document scan is crisp
/// and fully legible well below the raw sensor resolution, so capping the flat
/// output makes warp+enhance+encode cost scale with a bounded size instead of
/// the ~19 MP capture. The full-res original is kept separately for re-cropping.
const int kDefaultFlatMaxDimension = 3500;

class PerspectiveWarper implements ImageWarper {
  final int maxDimension;

  /// Cap on the full-image warp isolate. A wedged `compute()` isolate cannot be
  /// killed from Dart; this bounds how long [warp] waits before de-shadowing to
  /// the un-warped frame (returns null). Generous — a 12.5 MP capture warp on a
  /// slow device still finishes well inside it.
  final Duration timeout;

  /// Test-only seam: when non-null, [warp] routes through this instead of the
  /// real `compute()` isolate, so a never-completing runner can exercise the
  /// timeout branch deterministically. Production leaves it null and the byte
  /// output is identical to calling `compute(_warpFn, …)` directly.
  @visibleForTesting
  final Future<Uint8List?> Function(Uint8List bytes, CropCorners corners)?
  runnerOverride;

  const PerspectiveWarper({
    this.maxDimension = kDefaultFlatMaxDimension,
    this.timeout = const Duration(seconds: 12),
    @visibleForTesting this.runnerOverride,
  });

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) {
    if (corners == CropCorners.fullFrame) return Future.value(null);
    final run =
        runnerOverride ??
        (b, c) => compute(
          _warpFn,
          _WarpArgs(bytes: b, corners: c, maxDim: maxDimension),
        );
    return withIsolateTimeout(
      () => run(bytes, corners),
      timeout: timeout,
      onTimeout: () => null,
    );
  }
}

// ── Isolate entry point ────────────────────────────────────────────────────

Uint8List? _warpFn(_WarpArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) throw WarpException('failed to decode JPEG');
  // bakeOrientation rotates pixels into the EXIF-applied display frame.
  // Corners are normalized against THIS frame; skipping bake misaligns them.
  final src = img.bakeOrientation(decoded);
  return Uint8List.fromList(
    img.encodeJpg(
      warpPerspectiveToImage(src, args.corners, args.maxDim),
      quality: 92,
    ),
  );
}

/// Perspective-flattens [corners] out of an already-oriented image and returns
/// the rectified [img.Image] (no JPEG encode — the caller encodes, so a fused
/// warp+enhance pass pays a single decode/encode). Throws [WarpException] on a
/// self-crossing or degenerate quad.
///
/// The inverse-mapped sampling runs on the raw interleaved-RGB byte buffer with
/// hand-rolled bilinear interpolation instead of `getPixelInterpolate` per
/// pixel — the same interpolation, ~5-10x faster on a multi-megapixel warp.
img.Image warpPerspectiveToImage(
  img.Image src,
  CropCorners corners,
  int maxDim,
) {
  final w = src.width, h = src.height;
  final tl = Offset(corners.topLeft.dx * w, corners.topLeft.dy * h);
  final tr = Offset(corners.topRight.dx * w, corners.topRight.dy * h);
  final br = Offset(corners.bottomRight.dx * w, corners.bottomRight.dy * h);
  final bl = Offset(corners.bottomLeft.dx * w, corners.bottomLeft.dy * h);

  if (!_isConvex([tl, tr, br, bl])) {
    throw WarpException('self-crossing or degenerate quad');
  }

  var outW = _maxEdge(tl, tr, bl, br).round();
  var outH = _maxEdge(tl, bl, tr, br).round();
  if (outW < 2 || outH < 2) {
    throw WarpException('degenerate quad: output too small');
  }

  // Cap the long side: solving the homography to the reduced rectangle makes
  // the warp sample fewer points (and enhance/encode run smaller) with no loss
  // of geometric accuracy — every output pixel still maps across the full quad.
  final longest = outW > outH ? outW : outH;
  if (maxDim > 0 && longest > maxDim) {
    final s = maxDim / longest;
    outW = (outW * s).round();
    if (outW < 2) outW = 2;
    outH = (outH * s).round();
    if (outH < 2) outH = 2;
  }

  // Bound the SOURCE we sample from. The output is already capped above; a
  // full-res RGB buffer (~57 MB at 19 MP) is wasteful when the output is small.
  // Corners are normalized (0..1), so resizing the source needs no corner
  // adjustment — we just re-denormalize against the bounded dims. Output dims
  // (outW/outH) come from the ORIGINAL src above, so geometry is unchanged;
  // scale==1.0 (source already ≤ cap) leaves normal inputs byte-identical.
  final wr = computeWorkResolution(w, h, kWarpSourceCapMultiplier * maxDim);
  final sampleSrc = wr.scale == 1.0
      ? src
      : img.copyResize(src, width: wr.targetW, height: wr.targetH);
  final sw = sampleSrc.width, sh = sampleSrc.height;
  lastSampledSourceSize = (sw, sh);

  // Denormalize corners against the (possibly bounded) source dims so the
  // homography maps sampled-source pixels → the output rect.
  final stl = Offset(corners.topLeft.dx * sw, corners.topLeft.dy * sh);
  final str = Offset(corners.topRight.dx * sw, corners.topRight.dy * sh);
  final sbr = Offset(corners.bottomRight.dx * sw, corners.bottomRight.dy * sh);
  final sbl = Offset(corners.bottomLeft.dx * sw, corners.bottomLeft.dy * sh);

  // Src → dst homography; invert for inverse mapping (dst pixel → src pixel).
  final hMat = _solveHomography(
    [stl, str, sbr, sbl],
    [
      const Offset(0, 0),
      Offset(outW.toDouble(), 0),
      Offset(outW.toDouble(), outH.toDouble()),
      Offset(0, outH.toDouble()),
    ],
  );
  final hInv = _invertH3x3(hMat);

  final srcBuf = sampleSrc.getBytes(order: img.ChannelOrder.rgb);
  final out = Uint8List(outW * outH * 3);
  // Shared inverse-bilinear loop (P09); only the source mapper — here the
  // inverse homography — is warper-specific.
  sampleBilinearInto(
    out: out,
    srcBuf: srcBuf,
    sw: sw,
    sh: sh,
    outW: outW,
    outH: outH,
    mapToSrc: (dx, dy) => _applyH(hInv, dx.toDouble(), dy.toDouble()),
  );
  return img.Image.fromBytes(
    width: outW,
    height: outH,
    bytes: out.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}

// ── Math helpers ───────────────────────────────────────────────────────────

/// max(dist(a1,a2), dist(b1,b2))  →  outW or outH via edge-length sizing #1.
double _maxEdge(Offset a1, Offset a2, Offset b1, Offset b2) =>
    [_dist(a1, a2), _dist(b1, b2)].reduce((a, b) => a > b ? a : b);

double _dist(Offset a, Offset b) => (a - b).distance;

/// Returns true when [pts] (TL, TR, BR, BL in order) form a convex quad.
bool _isConvex(List<Offset> pts) {
  int sign = 0;
  final n = pts.length;
  for (int i = 0; i < n; i++) {
    final o = pts[i], a = pts[(i + 1) % n], b = pts[(i + 2) % n];
    final c = (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    if (c.abs() < 1e-8) continue;
    final s = c > 0 ? 1 : -1;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}

/// Solves the DLT 8-equation system for the homography mapping [src] → [dst].
/// Returns a flat 9-element list [h00…h21, 1.0] (h22 = 1 by convention).
List<double> _solveHomography(List<Offset> src, List<Offset> dst) {
  final m = List<List<double>>.generate(8, (row) {
    final i = row ~/ 2;
    final x = src[i].dx, y = src[i].dy;
    final u = dst[i].dx, v = dst[i].dy;
    return row.isEven
        ? [x, y, 1.0, 0.0, 0.0, 0.0, -x * u, -y * u, u]
        : [0.0, 0.0, 0.0, x, y, 1.0, -x * v, -y * v, v];
  });
  return [..._gaussElim(m), 1.0];
}

/// Gauss–Jordan elimination on an 8×9 augmented matrix [A|b].
/// Returns the 8-element solution vector.
List<double> _gaussElim(List<List<double>> m) {
  const n = 8;
  for (int col = 0; col < n; col++) {
    int maxRow = col;
    for (int row = col + 1; row < n; row++) {
      if (m[row][col].abs() > m[maxRow][col].abs()) maxRow = row;
    }
    final tmp = m[col];
    m[col] = m[maxRow];
    m[maxRow] = tmp;
    if (m[col][col].abs() < 1e-12) {
      throw WarpException('singular homography system');
    }
    for (int row = 0; row < n; row++) {
      if (row == col) continue;
      final factor = m[row][col] / m[col][col];
      for (int c = col; c <= n; c++) {
        m[row][c] -= factor * m[col][c];
      }
    }
  }
  return List<double>.generate(n, (i) => m[i][n] / m[i][i]);
}

/// Inverts a 3×3 homography stored as a flat 9-element list (row-major).
List<double> _invertH3x3(List<double> h) {
  final a = h[0], b = h[1], c = h[2];
  final d = h[3], e = h[4], f = h[5];
  final g = h[6], hh = h[7], k = h[8];
  final c00 = e * k - f * hh, c01 = -(d * k - f * g), c02 = d * hh - e * g;
  final c10 = -(b * k - c * hh), c11 = a * k - c * g, c12 = -(a * hh - b * g);
  final c20 = b * f - c * e, c21 = -(a * f - c * d), c22 = a * e - b * d;
  final det = a * c00 + b * c01 + c * c02;
  if (det.abs() < 1e-10) throw WarpException('singular homography');
  return [
    c00 / det,
    c10 / det,
    c20 / det,
    c01 / det,
    c11 / det,
    c21 / det,
    c02 / det,
    c12 / det,
    c22 / det,
  ];
}

/// Applies a flat 9-element row-major 3×3 homography to point (x, y).
Offset _applyH(List<double> h, double x, double y) {
  final w = h[6] * x + h[7] * y + h[8];
  return Offset(
    (h[0] * x + h[1] * y + h[2]) / w,
    (h[3] * x + h[4] * y + h[5]) / w,
  );
}

// ── Isolate-safe args ──────────────────────────────────────────────────────

class _WarpArgs {
  final Uint8List bytes;
  final CropCorners corners;
  final int maxDim;
  const _WarpArgs({
    required this.bytes,
    required this.corners,
    required this.maxDim,
  });
}
