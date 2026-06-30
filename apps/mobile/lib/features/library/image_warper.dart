import 'dart:typed_data';

import 'crop_corners.dart';

/// DIP boundary for the perspective-warp operation. The widget layer and
/// repository depend on this interface; the concrete implementation
/// (PerspectiveWarper) is wired only at the composition root.
abstract interface class ImageWarper {
  /// Returns flattened JPEG bytes, or null when [corners] are full-frame
  /// (no-op). [bytes] is the EXIF-scrubbed source JPEG.
  /// Throws [WarpException] for self-crossing or degenerate quads.
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners);
}

class WarpException implements Exception {
  final String message;
  const WarpException(this.message);
  @override
  String toString() => 'WarpException: $message';
}
