import 'auto_enhancer.dart' show kAutoWhiteClip, kAutoBlackAnchor;

/// Builds the flat 768-element BGR white-point-stretch LUT table (P08) —
/// `[b0,g0,r0, b1,g1,r1, …]`, channel order B,G,R — reproducing the per-channel
/// stretch in auto_enhancer.dart's `_whitePointStretch` (kAutoWhiteClip clip,
/// kAutoBlackAnchor black anchor, linear span). [histograms] is `[B, G, R]`,
/// each a 256-bin count; the total pixel count is derived from channel 0 (every
/// pixel contributes once per channel). cv-free so it is host-unit-testable; the
/// native enhancer reads the Mat bytes, builds the histograms, calls this, then
/// wraps the result in a `cv.Mat`. Kept byte-identical to the original inline
/// loop so device parity is unchanged. (P09 unifies this with the Dart side.)
List<int> whitePointLut3Table(List<List<int>> histograms) {
  final n = histograms[0].fold<int>(0, (a, b) => a + b);
  final clip = (n * kAutoWhiteClip).ceil().clamp(1, n);
  // Flat 768-element list: [b0,g0,r0, b1,g1,r1, ...] matching BGR channel order.
  final lut = List<int>.filled(256 * 3, 0);
  // Default: identity for all channels.
  for (var v = 0; v < 256; v++) {
    lut[v * 3] = v;
    lut[v * 3 + 1] = v;
    lut[v * 3 + 2] = v;
  }
  for (var ch = 0; ch < 3; ch++) {
    final hc = histograms[ch];
    int hi = 255, cum = 0;
    while (hi > 0 && cum + hc[hi] < clip) {
      cum += hc[hi--];
    }
    if (hi <= 0) continue;
    final anchor = (hi * kAutoBlackAnchor).round();
    if (hi <= anchor) continue;
    final span = hi - anchor;
    for (var v = anchor + 1; v < 256; v++) {
      lut[v * 3 + ch] = (anchor + (v - anchor) * 255 ~/ span).clamp(0, 255);
    }
  }
  return lut;
}
