import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';

/// Binarizes a JPEG to pure black-and-white using Otsu's automatic threshold.
/// Runs in a [compute] isolate — never blocks the UI thread.
class BwEnhancer implements ImageEnhancer {
  const BwEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_bwFn, bytes);
}

// Top-level function required by compute() (must be isolate-sendable).
Uint8List _bwFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    // bakeOrientation: EXIF scrubber keeps the Orientation tag; encodeJpg
    // strips EXIF, so orientation must be baked into pixels first.
    // For already-baked flat bytes (post-warp), this is a safe no-op.
    final oriented = img.bakeOrientation(decoded);
    img.grayscale(oriented);                    // mutates in place
    final t = _otsuThreshold(oriented);                           // automatic split — no magic numbers
    img.luminanceThreshold(oriented, threshold: t / 255.0);       // mutates in place; pixels → 0 or maxVal
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
  } catch (_) {
    return bytes;
  }
}

// Otsu's method: finds the threshold that maximises inter-class variance
// between background and foreground. Operates on a grayscale Image where
// all channels are equal — reads pixel.r as the luminance value.
int _otsuThreshold(img.Image src) {
  final hist = List<int>.filled(256, 0);
  for (final px in src) {
    hist[px.r.toInt()]++;
  }
  final total = src.width * src.height;
  double sum = 0;
  for (var i = 0; i < 256; i++) { sum += i * hist[i]; }

  double sumB = 0, maxVar = 0;
  int wB = 0, threshold = 128;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final v = wB.toDouble() * wF * (mB - mF) * (mB - mF);
    if (v > maxVar) {
      maxVar = v;
      threshold = t;
    }
  }
  return threshold;
}
