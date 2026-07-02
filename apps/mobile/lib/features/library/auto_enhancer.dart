import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';

/// Longest side of the downscaled proxy used to estimate the illumination map.
/// A large blur becomes cheap on a thumbnail, and the paper's shadow gradient
/// is low-frequency, so a tiny proxy captures it faithfully.
const int _kBackgroundProxyPx = 48;

/// Max-filter (grayscale dilation) radius on the proxy — erases dark ink so
/// only paper brightness remains in the background estimate.
const int _kDilateRadius = 1;

/// Gaussian blur radius on the proxy — smooths the estimate into a gradient.
const int _kBlurRadius = 3;

/// "Scanned document" filter. Flattens uneven illumination (hand/phone shadows)
/// via flat-field background division, then a global white-point stretch so the
/// page background goes clean white and text stays crisp — the classic scanner
/// look. Applied to the WHOLE page (no content detection): a document scanner's
/// job is a clean, de-shadowed page. Runs in a [compute] isolate — never blocks
/// the UI thread.
class AutoEnhancer implements ImageEnhancer {
  const AutoEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) => compute(_autoFn, bytes);
}

// Top-level function required by compute() (must be isolate-sendable).
Uint8List _autoFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    // EXIF scrubber keeps the Orientation tag; encodeJpg strips EXIF, so bake
    // orientation into pixels first. Safe no-op for already-flat bytes.
    final oriented = img.bakeOrientation(decoded);
    final bg = _estimateBackground(oriented);
    _divideByBackground(oriented, bg);
    _autoLevels(oriented); // global white-point + contrast finish
    return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
  } catch (_) {
    return bytes;
  }
}

/// Full-resolution per-pixel estimate of the paper-background brightness.
/// Downscale -> grayscale max-filter (erase ink) -> blur (smooth) -> upscale.
/// Returned image is grayscale: r == g == b == local background luminance.
img.Image _estimateBackground(img.Image src) {
  // 1. Downscale to a tiny proxy. Skip if the frame is already smaller than
  //    the proxy (tiny/test images) so we never upscale-then-downscale.
  final longest = math.max(src.width, src.height);
  final img.Image proxy;
  if (longest > _kBackgroundProxyPx) {
    final scale = _kBackgroundProxyPx / longest;
    proxy = img.copyResize(
      src,
      width: math.max(1, (src.width * scale).round()),
      height: math.max(1, (src.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  } else {
    proxy = src.clone();
  }

  // 2. Grayscale, then max-filter to remove dark ink from the estimate.
  img.grayscale(proxy);
  final dilated = _maxFilter(proxy, _kDilateRadius);

  // 3. Blur into a smooth illumination gradient (includes the shadow).
  final blurred = img.gaussianBlur(dilated, radius: _kBlurRadius);

  // 4. Upscale back to full resolution.
  return img.copyResize(
    blurred,
    width: src.width,
    height: src.height,
    interpolation: img.Interpolation.linear,
  );
}

/// Grayscale morphological dilation: each pixel becomes the max luminance in a
/// (2r+1)^2 window. Input is grayscale (r == g == b), so we read/write r.
img.Image _maxFilter(img.Image src, int radius) {
  if (radius <= 0) return src;
  final out = src.clone();
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      var mx = 0;
      for (var dy = -radius; dy <= radius; dy++) {
        final yy = (y + dy).clamp(0, src.height - 1);
        for (var dx = -radius; dx <= radius; dx++) {
          final xx = (x + dx).clamp(0, src.width - 1);
          final v = src.getPixel(xx, yy).r.toInt();
          if (v > mx) mx = v;
        }
      }
      out.setPixelRgb(x, y, mx, mx, mx);
    }
  }
  return out;
}

/// Flat-field correction: divide each channel by the local background so every
/// region normalizes to the same white. [bg] is grayscale (read r as the local
/// paper brightness). Shadowed paper (low bg) is boosted to white; ink (far
/// below the local bg) stays dark. Channels scale proportionally, so hue is
/// preserved. Guards bg == 0.
void _divideByBackground(img.Image src, img.Image bg) {
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final b = bg.getPixel(x, y).r.toInt();
      if (b <= 0) continue;
      final px = src.getPixel(x, y);
      px.r = (px.r.toInt() * 255 / b).clamp(0, 255).toInt();
      px.g = (px.g.toInt() * 255 / b).clamp(0, 255).toInt();
      px.b = (px.b.toInt() * 255 / b).clamp(0, 255).toInt();
    }
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
