import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

void main() {
  // Flat gray YUV420 (Y=128, U=V=128) → mid-gray BGR, no document → null,
  // but must NOT throw and must produce a non-empty Mat internally.
  test('detectFrame handles a well-formed YUV420 frame without throwing',
      () async {
    const detector = OpenCvEdgeDetector();
    final w = 320, h = 240;
    final y = Uint8List(w * h)..fillRange(0, w * h, 128);
    final u = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
    final v = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
    final frame = CameraFrame(
      width: w,
      height: h,
      format: CameraFrameFormat.yuv420,
      planes: [
        CameraFramePlane(bytes: y, bytesPerRow: w, bytesPerPixel: 1),
        CameraFramePlane(bytes: u, bytesPerRow: w ~/ 2, bytesPerPixel: 1),
        CameraFramePlane(bytes: v, bytesPerRow: w ~/ 2, bytesPerPixel: 1),
      ],
    );
    final result = await detector.detectFrame(frame); // uniform → null
    expect(result, isNull);
  });
}
