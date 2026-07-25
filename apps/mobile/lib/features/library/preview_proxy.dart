import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Downsize to a ≤1080 px long-side JPEG proxy for a fast LIVE filter preview.
/// Top-level so it can run in a `compute` isolate (never blocks the UI thread).
/// Shared by the scan-review and page-editor filter pickers (single source of
/// truth for the preview proxy — B2/B3 use the same strategy on their two
/// distinct screens).
///
/// On ANY failure — empty, truncated, or otherwise undecodable [bytes] — the
/// original [bytes] are returned unchanged, so the enhancer still gets something
/// to work with (or fails into the raw-image fallback). `img.decodeImage` does
/// NOT merely return null on bad input: it can THROW (e.g. a `RangeError` when a
/// decoder probes past the end of a tiny buffer), so the whole body is guarded.
Uint8List previewProxyJpeg(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final oriented = img.bakeOrientation(decoded);
    final longest = math.max(oriented.width, oriented.height);
    if (longest <= 1080) return bytes;
    final scale = 1080 / longest;
    final small = img.copyResize(
      oriented,
      width: math.max(1, (oriented.width * scale).round()),
      height: math.max(1, (oriented.height * scale).round()),
    );
    return Uint8List.fromList(img.encodeJpg(small, quality: 90));
  } catch (_) {
    return bytes;
  }
}
