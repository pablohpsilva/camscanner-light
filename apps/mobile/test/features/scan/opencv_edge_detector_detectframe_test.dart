import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

void main() {
  // A bright rectangle centered on a dark background, as a tightly-packed
  // BGRA frame. The detector should find a plausible quad.
  CameraFrame brightRectBgra(int w, int h) {
    final bytes = Uint8List(w * h * 4); // all zero = opaque-ish dark
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final inside = x > w * 0.2 && x < w * 0.8 && y > h * 0.2 && y < h * 0.8;
        final v = inside ? 240 : 15;
        bytes[i] = v;      // B
        bytes[i + 1] = v;  // G
        bytes[i + 2] = v;  // R
        bytes[i + 3] = 255; // A
      }
    }
    return CameraFrame(
      width: w,
      height: h,
      format: CameraFrameFormat.bgra8888,
      planes: [CameraFramePlane(bytes: bytes, bytesPerRow: w * 4, bytesPerPixel: 4)],
    );
  }

  test('detectFrame finds a quad in a bright-rectangle BGRA frame', () async {
    const detector = OpenCvEdgeDetector();
    final result = await detector.detectFrame(brightRectBgra(320, 240));
    expect(result, isNotNull);
    expect(result!.confidence, greaterThan(0.5));
  });

  test('detectFrame returns null on a uniform (no-document) frame', () async {
    const detector = OpenCvEdgeDetector();
    final w = 320, h = 240;
    final bytes = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 128);
    final frame = CameraFrame(
      width: w,
      height: h,
      format: CameraFrameFormat.bgra8888,
      planes: [CameraFramePlane(bytes: bytes, bytesPerRow: w * 4, bytesPerPixel: 4)],
    );
    expect(await detector.detectFrame(frame), isNull);
  });
}
