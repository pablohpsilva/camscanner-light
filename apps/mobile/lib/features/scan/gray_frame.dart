import 'dart:typed_data';

/// A downscaled single-channel (8-bit grayscale) preview frame, tightly packed:
/// `bytes.length == width * height`, no row padding. Small enough to copy cheaply
/// across an isolate boundary for live edge detection.
class GrayFrame {
  final int width;
  final int height;
  final Uint8List bytes;
  const GrayFrame({
    required this.width,
    required this.height,
    required this.bytes,
  }) : assert(bytes.length == width * height,
            'GrayFrame: bytes.length (${bytes.length}) must equal width*height (${width * height})');
}
