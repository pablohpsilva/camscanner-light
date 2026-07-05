import 'dart:math' as math;
import 'dart:typed_data';

import 'camera_frame.dart';
import 'gray_frame.dart';

/// Reduces a raw camera [frame] to a small, tightly-packed grayscale [GrayFrame]
/// whose longest side is at most [maxSide]. Pure Dart (no OpenCV) so it runs on
/// the main isolate before the detection `compute()` hop and is host-testable.
///
/// Nearest-neighbour decimation by an integer factor `k` (same on both axes, so
/// aspect ratio — and therefore normalized detection corners — is preserved).
/// - YUV420: samples the Y plane (already luminance).
/// - BGRA8888: Rec.601 luma from B, G, R.
GrayFrame reduceToGray(CameraFrame frame, {required int maxSide}) {
  final longest = math.max(frame.width, frame.height);
  final k = longest <= maxSide ? 1 : (longest + maxSide - 1) ~/ maxSide;
  final outW = (frame.width + k - 1) ~/ k;
  final outH = (frame.height + k - 1) ~/ k;
  final out = Uint8List(outW * outH);
  switch (frame.format) {
    case CameraFrameFormat.bgra8888:
      _decimateBgra(frame, k, outW, outH, out);
    case CameraFrameFormat.yuv420:
      throw UnimplementedError('yuv420 added in Task 3');
  }
  return GrayFrame(width: outW, height: outH, bytes: out);
}

void _decimateBgra(
    CameraFrame frame, int k, int outW, int outH, Uint8List out) {
  final p = frame.planes[0];
  var o = 0;
  for (var oy = 0; oy < outH; oy++) {
    final srcRow = (oy * k) * p.bytesPerRow;
    for (var ox = 0; ox < outW; ox++) {
      final i = srcRow + (ox * k) * 4;
      final b = p.bytes[i], g = p.bytes[i + 1], r = p.bytes[i + 2];
      out[o++] = (77 * r + 150 * g + 29 * b) >> 8; // weights sum to 256
    }
  }
}
