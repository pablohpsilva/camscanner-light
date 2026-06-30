import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';

class AutoEnhancer implements ImageEnhancer {
  const AutoEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_autoFn, bytes);
}

Uint8List _autoFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final oriented = img.bakeOrientation(decoded);
    _autoLevels(oriented);
    img.adjustColor(oriented, saturation: 1.15);
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
  } catch (_) {
    return bytes;
  }
}

void _autoLevels(img.Image src) {
  final n = src.width * src.height;
  if (n == 0) return;
  final clip = ((n / 100).ceil()).clamp(1, n);

  final rHist = List<int>.filled(256, 0);
  final gHist = List<int>.filled(256, 0);
  final bHist = List<int>.filled(256, 0);
  for (final px in src) {
    rHist[px.r.toInt()]++;
    gHist[px.g.toInt()]++;
    bHist[px.b.toInt()]++;
  }

  final (rLo, rHi) = _histClip(rHist, clip);
  final (gLo, gHi) = _histClip(gHist, clip);
  final (bLo, bHi) = _histClip(bHist, clip);

  for (final px in src) {
    if (rHi > rLo) {
      px.r = ((px.r.toInt() - rLo) * 255 ~/ (rHi - rLo)).clamp(0, 255);
    }
    if (gHi > gLo) {
      px.g = ((px.g.toInt() - gLo) * 255 ~/ (gHi - gLo)).clamp(0, 255);
    }
    if (bHi > bLo) {
      px.b = ((px.b.toInt() - bLo) * 255 ~/ (bHi - bLo)).clamp(0, 255);
    }
  }
}

(int, int) _histClip(List<int> hist, int clip) {
  int lo = 0, cumLo = 0;
  while (lo < 255 && cumLo + hist[lo] < clip) { cumLo += hist[lo++]; }
  int hi = 255, cumHi = 0;
  while (hi > lo && cumHi + hist[hi] < clip) { cumHi += hist[hi--]; }
  return (lo, hi);
}
