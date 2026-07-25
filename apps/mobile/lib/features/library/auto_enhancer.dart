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

/// Upper bound on the per-channel flat-field gain (255/bg). Real hand/phone
/// shadows on paper only dim it to ~15-40% brightness (gain 2.5-6), so this
/// still fully whitens them; but it stops near-black off-paper regions (bg→0)
/// from exploding sensor noise into colour speckle.
const double kAutoMaxGain = 6.0;

/// Radius (proxy px) of the min/max window that estimates the LOCAL ink (min)
/// and LOCAL paper white (max) luminance under each region. Large enough to
/// span a text block so the min lands on real ink and the max on real paper.
const int kAutoLocalWindowRadius = 16;

/// Gaussian radius smoothing the local black/white reference fields into soft
/// gradients before they are divided out (avoids blocky contrast transitions).
const int kAutoLocalBlurRadius = 24;

/// Local luminance span (white − black) at/below which a region is treated as
/// blank paper and left untouched — prevents amplifying sensor noise into
/// speckle. The guard ramps SMOOTHLY from here up to [kAutoLocalSpanHi] so a
/// hair's-worth of span difference never flips a whole region on/off (which
/// caused visible seams AND native/Dart parity blow-ups on a hard threshold).
const int kAutoLocalSpanLo = 20;

/// Local span at/above which the local contrast stretch runs at full
/// [kAutoLocalStrength]. Between [kAutoLocalSpanLo] and this, strength ramps
/// linearly with span.
const int kAutoLocalSpanHi = 60;

/// Blend of the locally-stretched luma vs the original (0 = off, 1 = full).
/// < 1 keeps already-clean images looking natural while still rescuing faded
/// text on bright backgrounds.
const double kAutoLocalStrength = 0.8;

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
  _localContrast(pixels, w, h); // local luma stretch, color preserved

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

/// Per-channel morphological erosion: each output becomes the MIN over a
/// (2r+1)^2 window. Separable, same structure as [_maxFilter]. Used on the
/// single-channel luma proxy to find the local ink (darkest) reference.
Uint8List _minFilter(Uint8List src, int w, int h, int radius) {
  if (radius <= 0) return Uint8List.fromList(src);
  final tmp = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final lo = x - radius < 0 ? 0 : x - radius;
      final hi = x + radius >= w ? w - 1 : x + radius;
      var m = 255;
      for (var xx = lo; xx <= hi; xx++) {
        final v = src[row + xx];
        if (v < m) m = v;
      }
      tmp[row + x] = m;
    }
  }
  final out = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final lo = y - radius < 0 ? 0 : y - radius;
    final hi = y + radius >= h ? h - 1 : y + radius;
    for (var x = 0; x < w; x++) {
      var m = 255;
      // Vertical pass reads the horizontally-filtered [tmp], not [src] —
      // mirrors the (correct) two-pass composition in [_maxFilter]. Reading
      // src here would silently degrade this to a vertical-only filter.
      for (var yy = lo; yy <= hi; yy++) {
        final v = tmp[yy * w + x];
        if (v < m) m = v;
      }
      out[y * w + x] = m;
    }
  }
  return out;
}

/// Single-channel max (local paper white) — 1-ch analogue of [_maxFilter].
Uint8List _maxFilter1(Uint8List src, int w, int h, int radius) {
  if (radius <= 0) return Uint8List.fromList(src);
  final tmp = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final lo = x - radius < 0 ? 0 : x - radius;
      final hi = x + radius >= w ? w - 1 : x + radius;
      var m = 0;
      for (var xx = lo; xx <= hi; xx++) {
        final v = src[row + xx];
        if (v > m) m = v;
      }
      tmp[row + x] = m;
    }
  }
  final out = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final lo = y - radius < 0 ? 0 : y - radius;
    final hi = y + radius >= h ? h - 1 : y + radius;
    for (var x = 0; x < w; x++) {
      var m = 0;
      // Vertical pass reads the horizontally-filtered [tmp], not [src] — see
      // the matching comment in [_minFilter].
      for (var yy = lo; yy <= hi; yy++) {
        final v = tmp[yy * w + x];
        if (v > m) m = v;
      }
      out[y * w + x] = m;
    }
  }
  return out;
}

/// Estimates the LOCAL black (ink) and white (paper) luminance reference
/// fields on a proxy. Returns `(black, white, pw, ph)` as 1-ch proxy buffers.
(Uint8List, Uint8List, int, int) _estimateLocalRefs(
  Uint8List px,
  int w,
  int h,
) {
  // Full-res luma → proxy (average downscale, same discipline as Stage 1).
  final luma = Uint8List(w * h);
  for (var i = 0, j = 0; i < px.length; i += 3, j++) {
    luma[j] = (0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2])
        .round()
        .clamp(0, 255);
  }
  final lumaImg = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: luma.buffer,
    numChannels: 1,
  );
  final longest = math.max(w, h);
  final img.Image proxy;
  if (longest > kAutoProxyLongSide) {
    final scale = kAutoProxyLongSide / longest;
    proxy = img.copyResize(
      lumaImg,
      width: math.max(1, (w * scale).round()),
      height: math.max(1, (h * scale).round()),
      interpolation: img.Interpolation.average,
    );
  } else {
    proxy = lumaImg;
  }
  final pw = proxy.width, ph = proxy.height;
  final pbuf = proxy.getBytes(order: img.ChannelOrder.red); // 1-ch
  final black = _blur1(
    _minFilter(pbuf, pw, ph, kAutoLocalWindowRadius),
    pw,
    ph,
  );
  final white = _blur1(
    _maxFilter1(pbuf, pw, ph, kAutoLocalWindowRadius),
    pw,
    ph,
  );
  return (black, white, pw, ph);
}

/// Gaussian-blur a 1-ch buffer via the image package (wrap → blur → unwrap),
/// radius [kAutoLocalBlurRadius], matching the native gaussianBlur.
Uint8List _blur1(Uint8List src, int w, int h) {
  final blurred = img.gaussianBlur(
    img.Image.fromBytes(width: w, height: h, bytes: src.buffer, numChannels: 1),
    radius: kAutoLocalBlurRadius,
  );
  return blurred.getBytes(order: img.ChannelOrder.red);
}

/// Stage 2: local luminance contrast stretch that preserves colour. Estimates
/// the local black (ink) and white (paper) luminance references and rescales
/// each pixel's luma between them, applying the same multiplicative scale to
/// R/G/B so hue/saturation are preserved. Blank/low-contrast regions (span at
/// or below [kAutoLocalSpanLo]) are left untouched so noise is not amplified;
/// the guard ramps smoothly up to full strength at [kAutoLocalSpanHi].
void _localContrast(Uint8List px, int w, int h) {
  final (black, white, bw, bh) = _estimateLocalRefs(px, w, h);
  final sx = bw > 1 ? (bw - 1) / (w - 1) : 0.0;
  final sy = bh > 1 ? (bh - 1) / (h - 1) : 0.0;
  for (var y = 0; y < h; y++) {
    final fy = y * sy;
    final y0 = fy.toInt();
    final y1 = y0 + 1 < bh ? y0 + 1 : y0;
    final wy = fy - y0;
    final r0 = y0 * bw, r1 = y1 * bw;
    final o = y * w * 3;
    for (var x = 0; x < w; x++) {
      final fx = x * sx;
      final x0 = fx.toInt();
      final x1 = x0 + 1 < bw ? x0 + 1 : x0;
      final wx = fx - x0;
      // Bilinear sample black & white refs.
      double sample(Uint8List f) {
        final t = f[r0 + x0] + (f[r0 + x1] - f[r0 + x0]) * wx;
        final b = f[r1 + x0] + (f[r1 + x1] - f[r1 + x0]) * wx;
        return t + (b - t) * wy;
      }

      final bRef = sample(black);
      final wRef = sample(white);
      final span = wRef - bRef;
      final oi = o + x * 3;
      final r = px[oi], g = px[oi + 1], b = px[oi + 2];
      final yLuma = 0.299 * r + 0.587 * g + 0.114 * b;
      final guard =
          ((span - kAutoLocalSpanLo) / (kAutoLocalSpanHi - kAutoLocalSpanLo))
              .clamp(0.0, 1.0);
      double yout;
      if (guard <= 0.0) {
        yout = yLuma;
      } else {
        final spanSafe = span < 1.0 ? 1.0 : span;
        final yPrime = ((yLuma - bRef) * 255.0 / spanSafe).clamp(0.0, 255.0);
        yout = yLuma + kAutoLocalStrength * guard * (yPrime - yLuma);
      }
      final scale = yout / (yLuma < 1.0 ? 1.0 : yLuma);
      final nr = (r * scale).round();
      final ng = (g * scale).round();
      final nb = (b * scale).round();
      px[oi] = nr > 255 ? 255 : (nr < 0 ? 0 : nr);
      px[oi + 1] = ng > 255 ? 255 : (ng < 0 ? 0 : ng);
      px[oi + 2] = nb > 255 ? 255 : (nb < 0 ? 0 : nb);
    }
  }
}
