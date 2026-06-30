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
    img.adjustColor(oriented, contrast: 1.1, brightness: 1.05);
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
  } catch (_) {
    return bytes;
  }
}
