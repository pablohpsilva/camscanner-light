import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'image_enhancer.dart';

/// Long side (px) of the proxy on which the illumination field is estimated.
/// The shadow gradient is low-frequency, so a moderate proxy captures it
/// faithfully while keeping the expensive max-filter cheap. 512 is small
/// enough to be fast yet large enough that a text block does NOT average into
/// a single gray blob (the failure of the old 48 px proxy).
const int _kProxyLongSide = 512;

/// Max-filter (grayscale/colour dilation) radius on the proxy. Must exceed the
/// half-thickness of the darkest ink stroke at proxy scale so that, under any
/// text, the estimate is replaced by the surrounding paper brightness. Too
/// small and text bleeds into the illumination map (over-brightening near
/// letters); too large and the map stops following real shadow detail.
const int _kDilateRadius = 7;

/// Gaussian blur radius on the proxy that smooths the dilated estimate into a
/// soft illumination gradient before it is divided out.
const int _kBlurRadius = 12;

/// Top fraction of pixels ignored when picking the per-channel white point in
/// the finishing stretch, so a few specular outliers don't set the reference.
const double _kWhiteClip = 0.01;

/// Fraction of the white point below which finishing leaves pixels untouched —
/// only the top of the range is pulled to 255, so text/ink are never lifted
/// (which would grey them out).
const double _kBlackAnchor = 0.55;

/// Upper bound on the per-channel flat-field gain (255/bg). Real hand/phone
/// shadows on paper only dim it to ~15-40% brightness (gain 2.5-6), so this
/// still fully whitens them; but it stops near-black off-paper regions (bg→0)
/// from exploding sensor noise into colour speckle.
const double _kMaxGain = 6.0;

/// "Scanned document" filter. Flattens uneven illumination (hand/phone
/// shadows) with a PER-CHANNEL flat-field division — estimate the local paper
/// white under every region and divide it out — which removes the shadow
/// gradient AND the warm colour cast of shadows in one step, leaving a clean
/// white page with crisp, correctly-coloured ink. Applied to the whole page
/// (no content detection). Runs in a [compute] isolate — never blocks the UI.
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
    // The EXIF scrubber keeps the Orientation tag; encodeJpg strips EXIF, so
    // bake orientation into pixels first. Safe no-op for already-flat bytes.
    final src = img.bakeOrientation(decoded);
    final bg = _estimateBackground(src); // full-res per-channel paper white
    _flatten(src, bg); // divide each channel by its local white
    _whitePointStretch(src); // gentle per-channel finish
    return Uint8List.fromList(img.encodeJpg(src, quality: 95));
  } catch (_) {
    return bytes;
  }
}

/// Full-resolution, per-channel estimate of the local paper-background colour.
/// Downscale -> per-channel max-filter (erase ink) -> blur (smooth) -> upscale.
/// Each output channel holds that channel's local "what white looks like here",
/// so dividing by it neutralises both the shadow gradient and its colour cast.
img.Image _estimateBackground(img.Image src) {
  final longest = math.max(src.width, src.height);
  final img.Image proxy;
  if (longest > _kProxyLongSide) {
    final scale = _kProxyLongSide / longest;
    proxy = img.copyResize(
      src,
      width: math.max(1, (src.width * scale).round()),
      height: math.max(1, (src.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  } else {
    proxy = src.clone();
  }

  final dilated = _maxFilter(proxy, _kDilateRadius);
  final blurred = img.gaussianBlur(dilated, radius: _kBlurRadius);

  return img.copyResize(
    blurred,
    width: src.width,
    height: src.height,
    interpolation: img.Interpolation.linear,
  );
}

/// Per-channel morphological dilation: each output channel becomes the max of
/// that channel over a (2r+1)^2 window. Replacing dark ink with the brightest
/// nearby paper colour is what makes the estimate track paper white, not text.
img.Image _maxFilter(img.Image src, int radius) {
  if (radius <= 0) return src.clone();
  final out = img.Image(width: src.width, height: src.height);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      var mr = 0, mg = 0, mb = 0;
      for (var dy = -radius; dy <= radius; dy++) {
        final yy = (y + dy).clamp(0, src.height - 1);
        for (var dx = -radius; dx <= radius; dx++) {
          final xx = (x + dx).clamp(0, src.width - 1);
          final p = src.getPixel(xx, yy);
          final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
          if (r > mr) mr = r;
          if (g > mg) mg = g;
          if (b > mb) mb = b;
        }
      }
      out.setPixelRgb(x, y, mr, mg, mb);
    }
  }
  return out;
}

/// Flat-field correction: divide each channel by its local background so every
/// region normalises to the same white. Shadowed paper (low bg) is boosted to
/// white; ink (far below the local bg) stays dark; a warm cast (bg redder than
/// blue) is cancelled because each channel is scaled by its own reference.
void _flatten(img.Image src, img.Image bg) {
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final b = bg.getPixel(x, y);
      final px = src.getPixel(x, y);
      final br = b.r.toInt(), bgc = b.g.toInt(), bb = b.b.toInt();
      if (br > 0) {
        px.r = (px.r.toInt() * math.min(255 / br, _kMaxGain)).clamp(0, 255).toInt();
      }
      if (bgc > 0) {
        px.g = (px.g.toInt() * math.min(255 / bgc, _kMaxGain)).clamp(0, 255).toInt();
      }
      if (bb > 0) {
        px.b = (px.b.toInt() * math.min(255 / bb, _kMaxGain)).clamp(0, 255).toInt();
      }
    }
  }
}

/// Gentle finishing: per channel, pull the near-white top of the range up to a
/// true 255 (removing residual haze) while leaving everything below
/// [_kBlackAnchor]·whitePoint untouched, so ink and colour are never lifted.
/// The white point is a high percentile, not the max, so specular outliers do
/// not set the reference.
void _whitePointStretch(img.Image src) {
  final n = src.width * src.height;
  if (n == 0) return;
  final clip = ((n * _kWhiteClip).ceil()).clamp(1, n);

  for (var ch = 0; ch < 3; ch++) {
    final hist = List<int>.filled(256, 0);
    for (final px in src) {
      hist[_channel(px, ch).toInt()]++;
    }
    // White point: highest value with more than [clip] pixels at or above it.
    int hi = 255, cum = 0;
    while (hi > 0 && cum + hist[hi] < clip) {
      cum += hist[hi--];
    }
    if (hi <= 0) continue;
    final anchor = (hi * _kBlackAnchor).round();
    if (hi <= anchor) continue;
    final span = hi - anchor;
    for (final px in src) {
      final v = _channel(px, ch).toInt();
      if (v <= anchor) continue;
      final nv = (anchor + (v - anchor) * 255 ~/ span).clamp(0, 255);
      _setChannel(px, ch, nv);
    }
  }
}

num _channel(img.Pixel px, int ch) =>
    ch == 0 ? px.r : (ch == 1 ? px.g : px.b);

void _setChannel(img.Pixel px, int ch, int v) {
  if (ch == 0) {
    px.r = v;
  } else if (ch == 1) {
    px.g = v;
  } else {
    px.b = v;
  }
}
