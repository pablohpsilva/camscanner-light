import 'dart:typed_data';

import 'crop_corners.dart';
import 'enhancer_mode.dart';
import 'page_processor.dart';

/// Tries [primary] (native), transparently running [fallback] (Dart) when
/// primary fails. Distinguishes the legitimate "nothing to do" case
/// (none + full frame) — which both engines would answer null for — by
/// short-circuiting it here, so the fallback is never pointlessly invoked and
/// the caller still gets the correct passthrough (null).
class FallbackPageProcessor implements PageProcessor {
  final PageProcessor primary;
  final PageProcessor fallback;
  const FallbackPageProcessor({required this.primary, required this.fallback});

  @override
  Future<Uint8List?> process(
      Uint8List bytes, CropCorners corners, EnhancerMode mode) async {
    if (mode == EnhancerMode.none && corners == CropCorners.fullFrame) {
      return null; // nothing to do — store scrubbed bytes verbatim
    }
    try {
      final out = await primary.process(bytes, corners, mode);
      if (out != null) return out;
    } catch (_) {
      // fall through to fallback
    }
    return fallback.process(bytes, corners, mode);
  }
}
