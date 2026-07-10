import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'crop_corners.dart';
import 'image_warper.dart';
import 'perspective_warper.dart' show kDefaultFlatMaxDimension;

/// Unwarps a curved 8-point crop (4 corners + 4 edge-midpoint deviations) to a
/// flat rectangle via a bilinearly-blended Coons patch. Pure Dart, runs in a
/// compute() isolate. Straight crops are handled upstream by [HybridWarper];
/// this class assumes at least one bent edge.
class CoonsWarper implements ImageWarper {
  final int maxDimension;
  const CoonsWarper({this.maxDimension = kDefaultFlatMaxDimension});

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) {
    if (corners == CropCorners.fullFrame) return Future.value(null);
    return compute(
      _coonsFn,
      _CoonsArgs(bytes: bytes, corners: corners, maxDim: maxDimension),
    );
  }
}

class _CoonsArgs {
  final Uint8List bytes;
  final CropCorners corners;
  final int maxDim;
  const _CoonsArgs({
    required this.bytes,
    required this.corners,
    required this.maxDim,
  });
}

Uint8List? _coonsFn(_CoonsArgs args) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(args.bytes);
  } catch (e) {
    throw WarpException('failed to decode JPEG: $e');
  }
  if (decoded == null) throw WarpException('failed to decode JPEG');
  final src = img.bakeOrientation(decoded);
  return Uint8List.fromList(
    img.encodeJpg(
      warpCoonsToImage(src, args.corners, args.maxDim),
      quality: 92,
    ),
  );
}

/// Unwarps a curved 8-point crop from an already-oriented image and returns the
/// rectified [img.Image] (no JPEG encode — the caller encodes, so a fused
/// warp+enhance pass pays a single decode/encode). Throws [WarpException] on a
/// degenerate patch.
///
/// The Coons-patch sampling runs on the raw interleaved-RGB byte buffer with
/// hand-rolled bilinear interpolation instead of `getPixelInterpolate` per
/// pixel — the same interpolation, much faster on a large output.
img.Image warpCoonsToImage(img.Image src, CropCorners c, int maxDim) {
  final w = src.width, h = src.height;

  Offset px(Offset n) => Offset(n.dx * w, n.dy * h);
  final tl = px(c.topLeft), tr = px(c.topRight);
  final br = px(c.bottomRight), bl = px(c.bottomLeft);

  // Control point in pixels: C = center + 2·dev.
  Offset ctrl(Offset a, Offset b, Offset devNorm) {
    final center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    return center + Offset(devNorm.dx * w, devNorm.dy * h) * 2.0;
  }

  final cTop = ctrl(tl, tr, c.topMidDev);
  final cRight = ctrl(tr, br, c.rightMidDev);
  final cBottom = ctrl(br, bl, c.bottomMidDev);
  final cLeft = ctrl(bl, tl, c.leftMidDev);

  Offset qbez(Offset p0, Offset ci, Offset p1, double t) {
    final mt = 1 - t, a = (1 - t) * (1 - t), b = 2 * mt * t, cc = t * t;
    return Offset(
      a * p0.dx + b * ci.dx + cc * p1.dx,
      a * p0.dy + b * ci.dy + cc * p1.dy,
    );
  }

  Offset top(double u) => qbez(tl, cTop, tr, u);
  Offset bottom(double u) => qbez(bl, cBottom, br, u);
  Offset left(double v) => qbez(tl, cLeft, bl, v);
  Offset right(double v) => qbez(tr, cRight, br, v);

  double arc(Offset Function(double) curve) {
    double len = 0;
    Offset prev = curve(0);
    for (int i = 1; i <= 16; i++) {
      final p = curve(i / 16);
      len += (p - prev).distance;
      prev = p;
    }
    return len;
  }

  int outW = math.max(arc(top), arc(bottom)).round();
  int outH = math.max(arc(left), arc(right)).round();
  if (outW < 2 || outH < 2) {
    throw WarpException('degenerate quad: output too small');
  }
  final cap = maxDim;
  if (outW > cap || outH > cap) {
    final s = cap / math.max(outW, outH);
    outW = math.max(2, (outW * s).round());
    outH = math.max(2, (outH * s).round());
  }

  final srcBuf = src.getBytes(order: img.ChannelOrder.rgb);
  final stride = w * 3;
  final xMax = (w - 1).toDouble(), yMax = (h - 1).toDouble();
  final out = Uint8List(outW * outH * 3);
  var o = 0;
  for (int dy = 0; dy < outH; dy++) {
    final v = dy / (outH - 1);
    final lc = left(v), rc = right(v);
    for (int dx = 0; dx < outW; dx++) {
      final u = dx / (outW - 1);
      final tc = top(u), bc = bottom(u);
      final bx =
          (1 - u) * (1 - v) * tl.dx +
          u * (1 - v) * tr.dx +
          (1 - u) * v * bl.dx +
          u * v * br.dx;
      final by =
          (1 - u) * (1 - v) * tl.dy +
          u * (1 - v) * tr.dy +
          (1 - u) * v * bl.dy +
          u * v * br.dy;
      final rawX =
          (1 - v) * tc.dx + v * bc.dx + (1 - u) * lc.dx + u * rc.dx - bx;
      final rawY =
          (1 - v) * tc.dy + v * bc.dy + (1 - u) * lc.dy + u * rc.dy - by;
      final fx = rawX < 0 ? 0.0 : (rawX > xMax ? xMax : rawX);
      final fy = rawY < 0 ? 0.0 : (rawY > yMax ? yMax : rawY);
      final x0 = fx.toInt(), y0 = fy.toInt();
      final x1 = x0 + 1 < w ? x0 + 1 : x0;
      final y1 = y0 + 1 < h ? y0 + 1 : y0;
      final wx = fx - x0, wy = fy - y0;
      final i00 = y0 * stride + x0 * 3, i10 = y0 * stride + x1 * 3;
      final i01 = y1 * stride + x0 * 3, i11 = y1 * stride + x1 * 3;
      for (var ch = 0; ch < 3; ch++) {
        final t = srcBuf[i00 + ch] + (srcBuf[i10 + ch] - srcBuf[i00 + ch]) * wx;
        final b = srcBuf[i01 + ch] + (srcBuf[i11 + ch] - srcBuf[i01 + ch]) * wx;
        out[o + ch] = (t + (b - t) * wy).round().clamp(0, 255);
      }
      o += 3;
    }
  }
  return img.Image.fromBytes(
    width: outW,
    height: outH,
    bytes: out.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}
