import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/frame_reducer.dart';

/// Builds a BGRA frame where every channel of pixel (x,y) is `pixel(x,y)`
/// (so its luma equals that value), with optional row padding.
CameraFrame _bgra(int w, int h,
    {int? bytesPerRow, required int Function(int x, int y) pixel}) {
  final stride = bytesPerRow ?? w * 4;
  final bytes = Uint8List(stride * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = pixel(x, y);
      final i = y * stride + x * 4;
      bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v; bytes[i + 3] = 255;
    }
  }
  return CameraFrame(
    width: w, height: h, format: CameraFrameFormat.bgra8888,
    planes: [CameraFramePlane(bytes: bytes, bytesPerRow: stride, bytesPerPixel: 4)],
  );
}

void main() {
  test('already-small frame passes through with k=1 (no upscale)', () {
    final g = reduceToGray(_bgra(4, 3, pixel: (x, y) => 100), maxSide: 400);
    expect(g.width, 4);
    expect(g.height, 3);
    expect(g.bytes.length, 12);
    expect(g.bytes.every((b) => b == 100), isTrue);
  });

  test('decimates by ceil(longest/maxSide), preserving aspect', () {
    final g = reduceToGray(_bgra(800, 400, pixel: (x, y) => 128), maxSide: 400);
    expect(g.width, 400); // k = 2
    expect(g.height, 200);
  });

  test('BGRA luma uses Rec.601 integer weights (pure red -> 76)', () {
    final bytes = Uint8List(4)
      ..[0] = 0    // B
      ..[1] = 0    // G
      ..[2] = 255  // R
      ..[3] = 255; // A
    final f = CameraFrame(
      width: 1, height: 1, format: CameraFrameFormat.bgra8888,
      planes: [CameraFramePlane(bytes: bytes, bytesPerRow: 4, bytesPerPixel: 4)],
    );
    expect(reduceToGray(f, maxSide: 400).bytes[0], (77 * 255) >> 8); // 76
  });

  test('honors row padding (bytesPerRow > width*4)', () {
    final f = _bgra(2, 2,
        bytesPerRow: 2 * 4 + 8, pixel: (x, y) => (x == 1 && y == 1) ? 200 : 10);
    expect(reduceToGray(f, maxSide: 400).bytes, [10, 10, 10, 200]);
  });
}
