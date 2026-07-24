import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// A uniform bright background (near-white, luma ~245) with a faded-gray text
/// block (luma ~170) centered in it. Models "photo of a document on a bright
/// white desk with light/faded print" — the case the global stretch washed out.
/// [textRect] is (left, top, right, bottom) in pixels.
Uint8List brightBgFadedTextJpg({int w = 240, int h = 160}) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  // Bright neutral background.
  for (final px in im) {
    px
      ..r = 246
      ..g = 245
      ..b = 244;
  }
  // Faded gray text block (low contrast against the bright bg).
  final l = w ~/ 4, t = h ~/ 4, r = 3 * w ~/ 4, b = 3 * h ~/ 4;
  for (var y = t; y < b; y++) {
    for (var x = l; x < r; x++) {
      // Simulate text strokes: every 4th column is "ink", rest is paper.
      if (x % 4 == 0) {
        im.getPixel(x, y)
          ..r = 170
          ..g = 170
          ..b = 170;
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

/// (left, top, right, bottom) of the faded-text block for a given size, so
/// tests can sample ink vs paper regions.
(int, int, int, int) fadedTextRect(int w, int h) =>
    (w ~/ 4, h ~/ 4, 3 * w ~/ 4, 3 * h ~/ 4);
