import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;

import '../../core/async/with_isolate_timeout.dart';
import 'image_enhancer.dart';
import 'oriented_enhance.dart';

/// Long side (px) of the proxy on which the illumination field is estimated.
/// The shadow gradient is low-frequency, so a moderate proxy captures it
/// faithfully while keeping the expensive max-filter cheap. 512 is small
/// enough to be fast yet large enough that a text block does NOT average into
/// a single gray blob (the failure of the old 48 px proxy).
const int kAutoProxyLongSide = 512;

/// Max-filter (grayscale/colour dilation) radius on the proxy. Must exceed the
/// half-thickness of the darkest ink stroke at proxy scale so that, under any
/// text, the estimate is replaced by the surrounding paper brightness. Too
/// small and text bleeds into the illumination map (over-brightening near
/// letters); too large and the map stops following real shadow detail.
const int kAutoDilateRadius = 7;

/// Gaussian blur radius on the proxy that smooths the dilated estimate into a
/// soft illumination gradient before it is divided out.
const int kAutoBlurRadius = 12;

/// Top fraction of pixels ignored when picking the per-channel white point in
/// the finishing stretch, so a few specular outliers don't set the reference.
const double kAutoWhiteClip = 0.01;

/// Fraction of the white point below which finishing leaves pixels untouched —
/// only the top of the range is pulled to 255, so text/ink are never lifted
/// (which would grey them out).
const double kAutoBlackAnchor = 0.55;

/// Upper bound on the per-channel flat-field gain (255/bg). Real hand/phone
/// shadows on paper only dim it to ~15-40% brightness (gain 2.5-6), so this
/// still fully whitens them; but it stops near-black off-paper regions (bg→0)
/// from exploding sensor noise into colour speckle.
const double kAutoMaxGain = 6.0;

/// "Scanned document" filter. Flattens uneven illumination (hand/phone
/// shadows) with a PER-CHANNEL flat-field division — estimate the local paper
/// white under every region and divide it out — which removes the shadow
/// gradient AND the warm colour cast of shadows in one step, leaving a clean
/// white page with crisp, correctly-coloured ink. Applied to the whole page
/// (no content detection). Runs in a [compute] isolate — never blocks the UI.
///
/// Performance: the per-pixel work runs on the raw interleaved-RGB byte buffer
/// (not `img.Pixel` accessors), the max-filter is separable, and the
/// background is bilinearly sampled straight into the flatten pass instead of
/// being upscaled into a full-resolution image first. This is ~2-3x faster
/// than the Pixel-based version while producing the same result.
class AutoEnhancer implements ImageEnhancer {
  const AutoEnhancer({this.timeout = const Duration(seconds: 12), this.runner});

  /// Upper bound on the enhancement isolate. A wedged isolate cannot be killed
  /// from Dart, but the awaiting future detaches so the caller's `catch (_)`
  /// falls back to the un-enhanced bytes (never lose a page).
  final Duration timeout;

  /// Test seam: an injectable runner defaulting to the real `compute(...)`.
  /// Production behaviour is byte-identical to `compute(_autoFn, bytes)`.
  @visibleForTesting
  final Future<Uint8List> Function(Uint8List)? runner;

  @override
  Future<Uint8List> enhance(Uint8List bytes) {
    final run = runner ?? ((b) => compute(_autoFn, b));
    return withIsolateTimeout(() => run(bytes), timeout: timeout);
  }
}

// Top-level function required by compute() (must be isolate-sendable).
// Auto finishes at q95; the shared body (P09) bakes orientation + guards decode.
Uint8List _autoFn(Uint8List bytes) =>
    runOrientedEnhance(bytes, autoEnhanceOriented, quality: 95);

/// Applies the flat-field + finishing pass to an already-oriented image and
/// returns the result as a new [img.Image] (no decode/encode — the caller owns
/// those, so a fused warp+enhance pass pays a single decode/encode). The input
/// must already be in the display frame (orientation baked).
img.Image autoEnhanceOriented(img.Image oriented) {
  final w = oriented.width, h = oriented.height;

  // Work on a plain interleaved RGB byte buffer (3 bytes/pixel). Normalising
  // to RGB drops any alpha (documents have none) and lets every hot loop use
  // direct integer indexing instead of the slow Pixel object accessors.
  final pixels = oriented.getBytes(order: img.ChannelOrder.rgb);

  // Per-channel local paper white, estimated on a small proxy: (pbuf, pw, ph).
  final (bg, pw, ph) = _estimateBackground(oriented);

  _flatten(pixels, w, h, bg, pw, ph); // divide by bilinearly-sampled white
  _whitePointStretch(pixels, w, h); // gentle per-channel finish

  return img.Image.fromBytes(
    width: w,
    height: h,
    bytes: pixels.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}

/// Per-channel estimate of the local paper-background colour, returned as a
/// SMALL interleaved-RGB buffer `(bytes, width, height)`. Downscale -> per
/// channel separable max-filter (erase ink) -> blur (smooth). The full-res
/// upsample is folded into [_flatten] (bilinear sampling) so no
/// full-resolution background image is ever allocated. Each output byte holds
/// that channel's local "what white looks like here", so dividing by it
/// neutralises both the shadow gradient and its colour cast.
(Uint8List, int, int) _estimateBackground(img.Image src) {
  final longest = math.max(src.width, src.height);
  final img.Image proxy;
  if (longest > kAutoProxyLongSide) {
    final scale = kAutoProxyLongSide / longest;
    proxy = img.copyResize(
      src,
      width: math.max(1, (src.width * scale).round()),
      height: math.max(1, (src.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  } else {
    proxy = src;
  }
  final pw = proxy.width, ph = proxy.height;

  final dilated = _maxFilter(
    proxy.getBytes(order: img.ChannelOrder.rgb),
    pw,
    ph,
    kAutoDilateRadius,
  );
  final blurred = img.gaussianBlur(
    img.Image.fromBytes(
      width: pw,
      height: ph,
      bytes: dilated.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    ),
    radius: kAutoBlurRadius,
  );
  return (blurred.getBytes(order: img.ChannelOrder.rgb), pw, ph);
}

/// Per-channel morphological dilation: each output channel becomes the max of
/// that channel over a (2r+1)^2 window. Replacing dark ink with the brightest
/// nearby paper colour is what makes the estimate track paper white, not text.
///
/// A square-window max is separable, so this runs a 1-D max horizontally then
/// vertically ((2r+1)+(2r+1) reads per pixel instead of (2r+1)^2) — the result
/// is identical to the full 2-D window.
Uint8List _maxFilter(Uint8List src, int w, int h, int radius) {
  if (radius <= 0) return Uint8List.fromList(src);
  final tmp = Uint8List(src.length);
  // Horizontal pass.
  for (var y = 0; y < h; y++) {
    final row = y * w * 3;
    for (var x = 0; x < w; x++) {
      final lo = x - radius < 0 ? 0 : x - radius;
      final hi = x + radius >= w ? w - 1 : x + radius;
      var mr = 0, mg = 0, mb = 0;
      for (var xx = lo; xx <= hi; xx++) {
        final i = row + xx * 3;
        if (src[i] > mr) mr = src[i];
        if (src[i + 1] > mg) mg = src[i + 1];
        if (src[i + 2] > mb) mb = src[i + 2];
      }
      final o = row + x * 3;
      tmp[o] = mr;
      tmp[o + 1] = mg;
      tmp[o + 2] = mb;
    }
  }
  // Vertical pass.
  final out = Uint8List(src.length);
  final stride = w * 3;
  for (var y = 0; y < h; y++) {
    final lo = y - radius < 0 ? 0 : y - radius;
    final hi = y + radius >= h ? h - 1 : y + radius;
    for (var x = 0; x < w; x++) {
      final col = x * 3;
      var mr = 0, mg = 0, mb = 0;
      for (var yy = lo; yy <= hi; yy++) {
        final i = yy * stride + col;
        if (tmp[i] > mr) mr = tmp[i];
        if (tmp[i + 1] > mg) mg = tmp[i + 1];
        if (tmp[i + 2] > mb) mb = tmp[i + 2];
      }
      final o = y * stride + col;
      out[o] = mr;
      out[o + 1] = mg;
      out[o + 2] = mb;
    }
  }
  return out;
}

/// Flat-field correction: divide each channel by its local background so every
/// region normalises to the same white. Shadowed paper (low bg) is boosted to
/// white; ink (far below the local bg) stays dark; a warm cast (bg redder than
/// blue) is cancelled because each channel is scaled by its own reference.
///
/// The background lives at proxy resolution ([bw]x[bh]); its value under each
/// full-res pixel is bilinearly interpolated here — the same interpolation a
/// linear upsample would produce, but without allocating a full-res image.
void _flatten(Uint8List px, int w, int h, Uint8List bg, int bw, int bh) {
  final sx = bw > 1 ? (bw - 1) / (w - 1) : 0.0;
  final sy = bh > 1 ? (bh - 1) / (h - 1) : 0.0;
  final bStride = bw * 3;
  for (var y = 0; y < h; y++) {
    final fy = y * sy;
    final y0 = fy.toInt();
    final y1 = y0 + 1 < bh ? y0 + 1 : y0;
    final wy = fy - y0;
    final r0 = y0 * bStride, r1 = y1 * bStride;
    final o = y * w * 3;
    for (var x = 0; x < w; x++) {
      final fx = x * sx;
      final x0 = fx.toInt();
      final x1 = x0 + 1 < bw ? x0 + 1 : x0;
      final wx = fx - x0;
      final c0 = x0 * 3, c1 = x1 * 3;
      final oi = o + x * 3;
      for (var ch = 0; ch < 3; ch++) {
        final p00 = bg[r0 + c0 + ch], p10 = bg[r0 + c1 + ch];
        final p01 = bg[r1 + c0 + ch], p11 = bg[r1 + c1 + ch];
        final top = p00 + (p10 - p00) * wx;
        final bot = p01 + (p11 - p01) * wx;
        final b = top + (bot - top) * wy;
        if (b > 0) {
          final gain = math.min(255 / b, kAutoMaxGain);
          final nv = (px[oi + ch] * gain).toInt();
          px[oi + ch] = nv > 255 ? 255 : nv;
        }
      }
    }
  }
}

/// Gentle finishing: per channel, pull the near-white top of the range up to a
/// true 255 (removing residual haze) while leaving everything below
/// [kAutoBlackAnchor]·whitePoint untouched, so ink and colour are never lifted.
/// The white point is a high percentile, not the max, so specular outliers do
/// not set the reference.
///
/// All three channel histograms are built in a single pass over the buffer and
/// applied through per-channel lookup tables in a single pass back — two full
/// scans total instead of six.
void _whitePointStretch(Uint8List px, int w, int h) {
  final n = w * h;
  if (n == 0) return;
  final clip = ((n * kAutoWhiteClip).ceil()).clamp(1, n);

  final hist = [
    List<int>.filled(256, 0),
    List<int>.filled(256, 0),
    List<int>.filled(256, 0),
  ];
  for (var i = 0; i < px.length; i += 3) {
    hist[0][px[i]]++;
    hist[1][px[i + 1]]++;
    hist[2][px[i + 2]]++;
  }

  // Build a lookup table per channel that reproduces the original stretch.
  final lut = [Uint8List(256), Uint8List(256), Uint8List(256)];
  for (var ch = 0; ch < 3; ch++) {
    for (var v = 0; v < 256; v++) {
      lut[ch][v] = v; // default: identity
    }
    // White point: highest value with more than [clip] pixels at or above it.
    final hc = hist[ch];
    int hi = 255, cum = 0;
    while (hi > 0 && cum + hc[hi] < clip) {
      cum += hc[hi--];
    }
    if (hi <= 0) continue;
    final anchor = (hi * kAutoBlackAnchor).round();
    if (hi <= anchor) continue;
    final span = hi - anchor;
    for (var v = anchor + 1; v < 256; v++) {
      lut[ch][v] = (anchor + (v - anchor) * 255 ~/ span).clamp(0, 255);
    }
  }

  final l0 = lut[0], l1 = lut[1], l2 = lut[2];
  for (var i = 0; i < px.length; i += 3) {
    px[i] = l0[px[i]];
    px[i + 1] = l1[px[i + 1]];
    px[i + 2] = l2[px[i + 2]];
  }
}
