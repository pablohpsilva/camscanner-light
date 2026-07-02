import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
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

/// Background luminance at or below which a region is treated as dark content
/// (an embedded photo or filled block) and left uncorrected — so flat-field
/// division never blows it out to white. "Protect photos" bias: set high enough
/// that a genuine photo (background estimate ~40) is preserved while shadowed
/// paper (estimate typically >= ~110) is still fully corrected.
const int _kPaperFloor = 95;

/// Width of the smooth transition above [_kPaperFloor]. The correction weight
/// ramps 0 -> 1 across this band, avoiding hard seams / halos at content edges.
const int _kGateBand = 25;

/// Correction weight for a pixel whose local background luminance is
/// [backgroundLuminance]: 0.0 for dark content (<= [_kPaperFloor]), 1.0 for
/// paper (>= floor + [_kGateBand]), linear in between. Pure; exposed for tests.
@visibleForTesting
double correctionWeight(int backgroundLuminance) =>
    ((backgroundLuminance - _kPaperFloor) / _kGateBand).clamp(0.0, 1.0);

/// Standard deviation of luminance over the 3x3 window around ([x], [y])
/// (edges clamped). A texture cue: flat paper ~0, continuous-tone photo detail
/// is high. Exposed for tests.
@visibleForTesting
double localStdDev(img.Image src, int x, int y) {
  var sum = 0.0, sumSq = 0.0, n = 0.0;
  for (var dy = -1; dy <= 1; dy++) {
    final yy = (y + dy).clamp(0, src.height - 1);
    for (var dx = -1; dx <= 1; dx++) {
      final xx = (x + dx).clamp(0, src.width - 1);
      final l = src.getPixel(xx, yy).luminance.toDouble();
      sum += l;
      sumSq += l * l;
      n += 1;
    }
  }
  final mean = sum / n;
  final variance = (sumSq / n) - mean * mean;
  return variance <= 0 ? 0 : math.sqrt(variance);
}

/// Marks enclosed background holes as foreground. Foreground = channel > 127.
/// Flood-fills background reachable from the border; any background pixel NOT
/// reached is enclosed (a hole) and is set to foreground (255). Absorbs a
/// smooth/bright sub-area enclosed by detected photo content into the region.
/// Exposed for tests.
@visibleForTesting
img.Image fillHoles(img.Image mask) {
  final w = mask.width, h = mask.height;
  final reachable = List.generate(h, (_) => List<bool>.filled(w, false));
  final stack = <int>[]; // packed y*w + x
  void tryPush(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    if (reachable[y][x]) return;
    if (mask.getPixel(x, y).r.toInt() > 127) return; // foreground blocks fill
    reachable[y][x] = true;
    stack.add(y * w + x);
  }
  for (var x = 0; x < w; x++) { tryPush(x, 0); tryPush(x, h - 1); }
  for (var y = 0; y < h; y++) { tryPush(0, y); tryPush(w - 1, y); }
  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    final x = p % w, y = p ~/ w;
    tryPush(x + 1, y);
    tryPush(x - 1, y);
    tryPush(x, y + 1);
    tryPush(x, y - 1);
  }
  final out = mask.clone();
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mask.getPixel(x, y).r.toInt() <= 127 && !reachable[y][x]) {
        out.setPixelRgb(x, y, 255, 255, 255);
      }
    }
  }
  return out;
}

/// "Clean white paper" filter. Flattens uneven illumination (hand/phone
/// shadows) via flat-field background division, then a global white-point
/// stretch. Runs in a [compute] isolate — never blocks the UI thread.
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

/// Flat-field correction, gated on background brightness. Where the local
/// background [bg] is bright (paper, even under shadow) the pixel is fully
/// divided so shadows flatten to white; where [bg] is genuinely dark (a photo
/// or filled block) the pixel is left untouched, so dark content is never blown
/// out. A smooth ramp between the two (see [correctionWeight]) prevents edge
/// seams. Channels scale proportionally, so hue is preserved. Guards bg == 0.
void _divideByBackground(img.Image src, img.Image bg) {
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final b = bg.getPixel(x, y).r.toInt();
      if (b <= 0) continue;
      final alpha = correctionWeight(b);
      if (alpha <= 0) continue; // dark content — leave the pixel untouched
      // alpha=1 -> multiply by 255/b (full divide); alpha=0 -> unchanged.
      final scale = 1 + alpha * (255 / b - 1);
      final px = src.getPixel(x, y);
      px.r = (px.r.toInt() * scale).clamp(0, 255).toInt();
      px.g = (px.g.toInt() * scale).clamp(0, 255).toInt();
      px.b = (px.b.toInt() * scale).clamp(0, 255).toInt();
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
