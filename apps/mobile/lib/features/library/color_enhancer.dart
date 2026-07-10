import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';

class ColorEnhancer implements ImageEnhancer {
  const ColorEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_colorFn, bytes);
}

Uint8List _colorFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final oriented = img.bakeOrientation(decoded);
    return Uint8List.fromList(
      img.encodeJpg(colorEnhanceOriented(oriented), quality: 92),
    );
  } catch (_) {
    return bytes;
  }
}

/// Applies the colour boost in place to an already-oriented image and returns
/// it (no decode/encode — the caller owns those, enabling a fused warp+enhance
/// pass). Input must already be in the display frame (orientation baked).
img.Image colorEnhanceOriented(img.Image oriented) {
  img.adjustColor(oriented, contrast: 1.1, brightness: 1.05);
  return oriented;
}
