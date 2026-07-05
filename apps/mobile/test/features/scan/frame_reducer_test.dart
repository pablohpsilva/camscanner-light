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

/// Builds a YUV420 frame whose Y(x,y) == `luma(x,y)`, with optional Y row/pixel
/// stride. U/V are filled mid-gray (unused by reduceToGray).
CameraFrame _yuv(int w, int h,
    {int? yRow, int yPixStride = 1, required int Function(int x, int y) luma}) {
  final row = yRow ?? w * yPixStride;
  final yb = Uint8List(row * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      yb[y * row + x * yPixStride] = luma(x, y);
    }
  }
  final cw = w ~/ 2, ch = h ~/ 2;
  final u = Uint8List(cw * ch)..fillRange(0, cw * ch, 128);
  final v = Uint8List(cw * ch)..fillRange(0, cw * ch, 128);
  return CameraFrame(
    width: w, height: h, format: CameraFrameFormat.yuv420,
    planes: [
      CameraFramePlane(bytes: yb, bytesPerRow: row, bytesPerPixel: yPixStride),
      CameraFramePlane(bytes: u, bytesPerRow: cw, bytesPerPixel: 1),
      CameraFramePlane(bytes: v, bytesPerRow: cw, bytesPerPixel: 1),
    ],
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

  test('ceiling division: non-multiple dims include the partial last strip', () {
    final g = reduceToGray(_bgra(5, 3, pixel: (x, y) => 0), maxSide: 2);
    // k = ceil(5/2) = 3; outW = ceil(5/3) = 2; outH = ceil(3/3) = 1
    expect(g.width, 2);
    expect(g.height, 1);
    expect(g.bytes.length, 2);
  });

  test('BGRA luma isolates the green weight (pure green -> 149)', () {
    final bytes = Uint8List(4)..[0] = 0..[1] = 255..[2] = 0..[3] = 255; // B,G,R,A
    final f = CameraFrame(
      width: 1, height: 1, format: CameraFrameFormat.bgra8888,
      planes: [CameraFramePlane(bytes: bytes, bytesPerRow: 4, bytesPerPixel: 4)],
    );
    expect(reduceToGray(f, maxSide: 400).bytes[0], (150 * 255) >> 8); // 149
  });

  test('BGRA luma isolates the blue weight (pure blue -> 28)', () {
    final bytes = Uint8List(4)..[0] = 255..[1] = 0..[2] = 0..[3] = 255; // B,G,R,A
    final f = CameraFrame(
      width: 1, height: 1, format: CameraFrameFormat.bgra8888,
      planes: [CameraFramePlane(bytes: bytes, bytesPerRow: 4, bytesPerPixel: 4)],
    );
    expect(reduceToGray(f, maxSide: 400).bytes[0], (29 * 255) >> 8); // 28
  });

  test('YUV samples the Y plane directly', () {
    final g = reduceToGray(_yuv(4, 4, luma: (x, y) => x * 10 + y), maxSide: 400);
    expect(g.width, 4);
    expect(g.height, 4);
    expect(g.bytes[0], 0);  // (0,0)
    expect(g.bytes[1], 10); // (1,0)
    expect(g.bytes[4], 1);  // (0,1)
  });

  test('YUV honors Y row stride padding', () {
    final f = _yuv(2, 2, yRow: 2 + 5, luma: (x, y) => (x == 1 && y == 1) ? 99 : 5);
    expect(reduceToGray(f, maxSide: 400).bytes, [5, 5, 5, 99]);
  });

  test('YUV honors Y pixel stride', () {
    final f = _yuv(2, 2, yPixStride: 2, luma: (x, y) => x * 10 + y);
    expect(reduceToGray(f, maxSide: 400).bytes, [0, 10, 1, 11]);
  });
}
