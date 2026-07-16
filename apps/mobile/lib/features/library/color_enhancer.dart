import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;

import '../../core/async/with_isolate_timeout.dart';
import 'image_enhancer.dart';
import 'oriented_enhance.dart';

class ColorEnhancer implements ImageEnhancer {
  const ColorEnhancer({this.timeout = const Duration(seconds: 12), this.runner});

  /// Upper bound on the enhancement isolate. A wedged isolate cannot be killed
  /// from Dart, but the awaiting future detaches so the caller's `catch (_)`
  /// falls back to the un-enhanced bytes (never lose a page).
  final Duration timeout;

  /// Test seam: an injectable runner defaulting to the real `compute(...)`.
  /// Production behaviour is byte-identical to `compute(_colorFn, bytes)`.
  @visibleForTesting
  final Future<Uint8List> Function(Uint8List)? runner;

  @override
  Future<Uint8List> enhance(Uint8List bytes) {
    final run = runner ?? ((b) => compute(_colorFn, b));
    return withIsolateTimeout(() => run(bytes), timeout: timeout);
  }
}

Uint8List _colorFn(Uint8List bytes) =>
    runOrientedEnhance(bytes, colorEnhanceOriented, quality: 92);

/// Applies the colour boost in place to an already-oriented image and returns
/// it (no decode/encode — the caller owns those, enabling a fused warp+enhance
/// pass). Input must already be in the display frame (orientation baked).
img.Image colorEnhanceOriented(img.Image oriented) {
  img.adjustColor(oriented, contrast: 1.1, brightness: 1.05);
  return oriented;
}
