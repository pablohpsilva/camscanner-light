import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';

/// Converts a JPEG to grayscale using luminance-weighted conversion.
/// Runs in a [compute] isolate — never blocks the UI thread.
class GrayscaleEnhancer implements ImageEnhancer {
  const GrayscaleEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_grayscaleFn, bytes);
}

// Top-level function required by compute() (must be isolate-sendable).
Uint8List _grayscaleFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes; // corrupt input — return unchanged
    // bakeOrientation: EXIF scrubber keeps the Orientation tag; encodeJpg
    // strips EXIF, so orientation must be baked into pixels first.
    // For already-baked flat bytes (post-warp), this is a safe no-op.
    final oriented = img.bakeOrientation(decoded); // positional arg
    return Uint8List.fromList(
      img.encodeJpg(grayscaleEnhanceOriented(oriented), quality: 92),
    );
  } catch (e) {
    // On any error during decoding or processing, return bytes unchanged
    return bytes;
  }
}

/// Converts an already-oriented image to grayscale in place and returns it (no
/// decode/encode — the caller owns those, enabling a fused warp+enhance pass).
/// Input must already be in the display frame (orientation baked).
img.Image grayscaleEnhanceOriented(img.Image oriented) {
  img.grayscale(oriented); // mutates in place
  return oriented;
}
