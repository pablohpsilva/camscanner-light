import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'crop_corners.dart';
import 'image_warper.dart';

class PerspectiveWarper implements ImageWarper {
  const PerspectiveWarper();

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) {
    if (corners == CropCorners.fullFrame) return Future.value(null);
    return compute(_warpFn, _WarpArgs(bytes: bytes, corners: corners));
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
      img.encodeJpg(warpPerspectiveToImage(src, args.corners), quality: 92));
}

/// Perspective-flattens [corners] out of an already-oriented image and returns
/// the rectified [img.Image] (no JPEG encode — the caller encodes, so a fused
/// warp+enhance pass pays a single decode/encode). Throws [WarpException] on a
/// self-crossing or degenerate quad.
///
/// The inverse-mapped sampling runs on the raw interleaved-RGB byte buffer with
/// hand-rolled bilinear interpolation instead of `getPixelInterpolate` per
/// pixel — the same interpolation, ~5-10x faster on a multi-megapixel warp.
img.Image warpPerspectiveToImage(img.Image src, CropCorners corners) {
  final w = src.width, h = src.height;
  final tl = Offset(corners.topLeft.dx * w, corners.topLeft.dy * h);
  final tr = Offset(corners.topRight.dx * w, corners.topRight.dy * h);
  final br = Offset(corners.bottomRight.dx * w, corners.bottomRight.dy * h);
  final bl = Offset(corners.bottomLeft.dx * w, corners.bottomLeft.dy * h);

  if (!_isConvex([tl, tr, br, bl])) {
    throw WarpException('self-crossing or degenerate quad');
  }

  final outW = _maxEdge(tl, tr, bl, br).round();
  final outH = _maxEdge(tl, bl, tr, br).round();
  if (outW < 2 || outH < 2) throw WarpException('degenerate quad: output too small');

  // Src → dst homography; invert for inverse mapping (dst pixel → src pixel).
  final hMat = _solveHomography(
    [tl, tr, br, bl],
    [const Offset(0, 0), Offset(outW.toDouble(), 0),
     Offset(outW.toDouble(), outH.toDouble()), Offset(0, outH.toDouble())],
  );
  final hInv = _invertH3x3(hMat);

  final srcBuf = src.getBytes(order: img.ChannelOrder.rgb);
  final stride = w * 3;
  final out = Uint8List(outW * outH * 3);
  final xMax = (w - 1).toDouble(), yMax = (h - 1).toDouble();
  var o = 0;
  for (var dy = 0; dy < outH; dy++) {
    for (var dx = 0; dx < outW; dx++) {
      final sp = _applyH(hInv, dx.toDouble(), dy.toDouble());
      final fx = sp.dx < 0 ? 0.0 : (sp.dx > xMax ? xMax : sp.dx);
      final fy = sp.dy < 0 ? 0.0 : (sp.dy > yMax ? yMax : sp.dy);
      final x0 = fx.toInt(), y0 = fy.toInt();
      final x1 = x0 + 1 < w ? x0 + 1 : x0;
      final y1 = y0 + 1 < h ? y0 + 1 : y0;
      final wx = fx - x0, wy = fy - y0;
      final i00 = y0 * stride + x0 * 3, i10 = y0 * stride + x1 * 3;
      final i01 = y1 * stride + x0 * 3, i11 = y1 * stride + x1 * 3;
      for (var ch = 0; ch < 3; ch++) {
        final top = srcBuf[i00 + ch] + (srcBuf[i10 + ch] - srcBuf[i00 + ch]) * wx;
        final bot = srcBuf[i01 + ch] + (srcBuf[i11 + ch] - srcBuf[i01 + ch]) * wx;
        out[o + ch] = (top + (bot - top) * wy).round().clamp(0, 255);
      }
      o += 3;
    }
  }
  return img.Image.fromBytes(
      width: outW, height: outH, bytes: out.buffer,
      numChannels: 3, order: img.ChannelOrder.rgb);
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
    final tmp = m[col]; m[col] = m[maxRow]; m[maxRow] = tmp;
    if (m[col][col].abs() < 1e-12) throw WarpException('singular homography system');
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
  final c00 = e * k - f * hh,  c01 = -(d * k - f * g),  c02 = d * hh - e * g;
  final c10 = -(b * k - c * hh), c11 = a * k - c * g,   c12 = -(a * hh - b * g);
  final c20 = b * f - c * e,   c21 = -(a * f - c * d),  c22 = a * e - b * d;
  final det = a * c00 + b * c01 + c * c02;
  if (det.abs() < 1e-10) throw WarpException('singular homography');
  return [
    c00/det, c10/det, c20/det,
    c01/det, c11/det, c21/det,
    c02/det, c12/det, c22/det,
  ];
}

/// Applies a flat 9-element row-major 3×3 homography to point (x, y).
Offset _applyH(List<double> h, double x, double y) {
  final w = h[6] * x + h[7] * y + h[8];
  return Offset((h[0] * x + h[1] * y + h[2]) / w,
                (h[3] * x + h[4] * y + h[5]) / w);
}

// ── Isolate-safe args ──────────────────────────────────────────────────────

class _WarpArgs {
  final Uint8List bytes;
  final CropCorners corners;
  const _WarpArgs({required this.bytes, required this.corners});
}
