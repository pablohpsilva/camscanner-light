import 'dart:typed_data';

import 'auto_enhancer.dart';
import 'color_enhancer.dart';
import 'coons_warper.dart';
import 'crop_corners.dart';
import 'enhancer_mode.dart';
import 'grayscale_enhancer.dart';
import 'hybrid_warper.dart';
import 'image_enhancer.dart';
import 'image_warper.dart';
import 'page_processor.dart';
import 'perspective_warper.dart';
import 'warp_enhancer.dart';

/// The shipped pure-Dart pipeline behind the [PageProcessor] seam. Encapsulates
/// the full-frame enhance and the fused cropped warp+enhance, preserving the
/// existing "real warper → fused, stubbed warper → two-step" behavior so tests
/// that inject a fake warper still exercise it.
class DartPageProcessor implements PageProcessor {
  final ImageWarper warper;
  const DartPageProcessor(this.warper);

  @override
  Future<Uint8List?> process(
      Uint8List bytes, CropCorners corners, EnhancerMode mode) async {
    final isFullFrame = corners == CropCorners.fullFrame;
    if (isFullFrame) {
      if (mode == EnhancerMode.none) return null; // nothing to do
      try {
        return await _enhancerFor(mode).enhance(bytes);
      } catch (_) {
        return null;
      }
    }

    // Cropped: fused fast path for the real warper; two-step for a stubbed one.
    if (warper is HybridWarper ||
        warper is PerspectiveWarper ||
        warper is CoonsWarper) {
      final fused = await warpAndEnhance(bytes, corners, mode);
      if (fused != null) return fused;
      // Warp failed → de-shadow the un-warped frame (never lose the page).
      if (mode == EnhancerMode.none) return null;
      try {
        return await _enhancerFor(mode).enhance(bytes);
      } catch (_) {
        return null;
      }
    }

    Uint8List? warped;
    try {
      warped = await warper.warp(bytes, corners);
    } catch (_) {
      warped = null;
    }
    final base = warped ?? bytes;
    if (mode == EnhancerMode.none) return warped; // null if warp made nothing
    try {
      return await _enhancerFor(mode).enhance(base);
    } catch (_) {
      return base;
    }
  }

  ImageEnhancer _enhancerFor(EnhancerMode mode) => switch (mode) {
        EnhancerMode.auto => const AutoEnhancer(),
        EnhancerMode.color => const ColorEnhancer(),
        EnhancerMode.grayscale => const GrayscaleEnhancer(),
        EnhancerMode.none => const NoneEnhancer(),
      };
}
