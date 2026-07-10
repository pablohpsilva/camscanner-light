import 'dart:typed_data';

import 'crop_corners.dart';
import 'enhancer_mode.dart';

/// Turns a captured JPEG into the stored page bytes: decode → (warp if cropped)
/// → filter(mode) → encode. The single seam for page processing so the native
/// and pure-Dart pipelines are interchangeable and a fallback can wrap them.
abstract interface class PageProcessor {
  /// Returns the processed JPEG, or null when there is nothing to do
  /// (`mode == EnhancerMode.none && corners == CropCorners.fullFrame`) — the
  /// caller then stores the scrubbed input verbatim. Implementations also
  /// return null on failure (corrupt/timeout) so a wrapping fallback can run.
  /// Never throws.
  Future<Uint8List?> process(
    Uint8List bytes,
    CropCorners corners,
    EnhancerMode mode,
  );
}
