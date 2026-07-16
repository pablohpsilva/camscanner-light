import 'dart:typed_data';
import 'dart:ui' show Offset;

/// The shared inverse-bilinear warp sampling loop (P09). For each output pixel
/// `(dx, dy)`, [mapToSrc] returns the (possibly out-of-range) source coordinate
/// in the sampled-source buffer's pixel space; this loop clamps it to the buffer
/// edges, does a 4-tap bilinear read on the interleaved-RGB [srcBuf]
/// (`sw`×`sh`, stride `sw*3`), and writes the rounded 3-channel result into
/// [out] (`outW`×`outH`, same interleaved-RGB layout).
///
/// Both the perspective homography and the Coons patch feed this one loop — only
/// their [mapToSrc] differs (a homography apply vs a Coons blend). Extracting it
/// removes ~40 duplicated hot-loop lines; the arithmetic is byte-identical to the
/// two inline copies it replaces (values are provably in `[0,255]` after
/// interpolating in-range bytes, so `.round()` alone is exact — no clamp).
void sampleBilinearInto({
  required Uint8List out,
  required Uint8List srcBuf,
  required int sw,
  required int sh,
  required int outW,
  required int outH,
  required Offset Function(int dx, int dy) mapToSrc,
}) {
  final stride = sw * 3;
  final xMax = (sw - 1).toDouble(), yMax = (sh - 1).toDouble();
  var o = 0;
  for (var dy = 0; dy < outH; dy++) {
    for (var dx = 0; dx < outW; dx++) {
      final sp = mapToSrc(dx, dy);
      final fx = sp.dx < 0 ? 0.0 : (sp.dx > xMax ? xMax : sp.dx);
      final fy = sp.dy < 0 ? 0.0 : (sp.dy > yMax ? yMax : sp.dy);
      final x0 = fx.toInt(), y0 = fy.toInt();
      final x1 = x0 + 1 < sw ? x0 + 1 : x0;
      final y1 = y0 + 1 < sh ? y0 + 1 : y0;
      final wx = fx - x0, wy = fy - y0;
      final i00 = y0 * stride + x0 * 3, i10 = y0 * stride + x1 * 3;
      final i01 = y1 * stride + x0 * 3, i11 = y1 * stride + x1 * 3;
      for (var ch = 0; ch < 3; ch++) {
        final t = srcBuf[i00 + ch] + (srcBuf[i10 + ch] - srcBuf[i00 + ch]) * wx;
        final b = srcBuf[i01 + ch] + (srcBuf[i11 + ch] - srcBuf[i01 + ch]) * wx;
        out[o + ch] = (t + (b - t) * wy).round();
      }
      o += 3;
    }
  }
}
