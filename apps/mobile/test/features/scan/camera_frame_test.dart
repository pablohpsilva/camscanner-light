import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';

void main() {
  test('CameraFrame holds dims, format, and planes', () {
    final frame = CameraFrame(
      width: 4,
      height: 2,
      format: CameraFrameFormat.bgra8888,
      planes: [
        CameraFramePlane(
          bytes: Uint8List.fromList(List.filled(4 * 2 * 4, 7)),
          bytesPerRow: 4 * 4,
          bytesPerPixel: 4,
        ),
      ],
    );
    expect(frame.width, 4);
    expect(frame.height, 2);
    expect(frame.format, CameraFrameFormat.bgra8888);
    expect(frame.planes, hasLength(1));
    expect(frame.planes.first.bytesPerRow, 16);
    expect(frame.planes.first.bytes.first, 7);
  });
}
