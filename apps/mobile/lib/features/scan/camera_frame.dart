import 'dart:typed_data';

/// Raw pixel layout of a streamed preview frame. Plugin-agnostic so the
/// detector and fakes never depend on `package:camera`.
enum CameraFrameFormat { bgra8888, yuv420 }

/// One image plane: its bytes plus the row stride (may exceed width*bpp due to
/// hardware row padding) and pixel stride.
class CameraFramePlane {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  const CameraFramePlane({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel,
  });
}

/// One live preview frame. [planes] is length 1 for [CameraFrameFormat.bgra8888]
/// (iOS) and length 3 (Y, U, V) for [CameraFrameFormat.yuv420] (Android).
class CameraFrame {
  final int width;
  final int height;
  final CameraFrameFormat format;
  final List<CameraFramePlane> planes;
  const CameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
  });
}
