import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;

import '../../core/async/with_isolate_timeout.dart';
import 'image_enhancer.dart';
import 'oriented_enhance.dart';

/// Converts a JPEG to grayscale using luminance-weighted conversion.
/// Runs in a [compute] isolate — never blocks the UI thread.
class GrayscaleEnhancer implements ImageEnhancer {
  const GrayscaleEnhancer({
    this.timeout = const Duration(seconds: 12),
    this.runner,
  });

  /// Upper bound on the enhancement isolate. A wedged isolate cannot be killed
  /// from Dart, but the awaiting future detaches so the caller's `catch (_)`
  /// falls back to the un-enhanced bytes (never lose a page).
  final Duration timeout;

  /// Test seam: an injectable runner defaulting to the real `compute(...)`.
  /// Production behaviour is byte-identical to `compute(_grayscaleFn, bytes)`.
  @visibleForTesting
  final Future<Uint8List> Function(Uint8List)? runner;

  @override
  Future<Uint8List> enhance(Uint8List bytes) {
    final run = runner ?? ((b) => compute(_grayscaleFn, b));
    return withIsolateTimeout(() => run(bytes), timeout: timeout);
  }
}

// Top-level function required by compute() (must be isolate-sendable).
Uint8List _grayscaleFn(Uint8List bytes) =>
    runOrientedEnhance(bytes, grayscaleEnhanceOriented, quality: 92);

/// Converts an already-oriented image to grayscale in place and returns it (no
/// decode/encode — the caller owns those, enabling a fused warp+enhance pass).
/// Input must already be in the display frame (orientation baked).
img.Image grayscaleEnhanceOriented(img.Image oriented) {
  img.grayscale(oriented); // mutates in place
  return oriented;
}
