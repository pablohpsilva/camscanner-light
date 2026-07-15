import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:image/image.dart' as img;

import '../../core/async/with_isolate_timeout.dart';
import 'auto_enhancer.dart';
import 'color_enhancer.dart';
import 'coons_warper.dart';
import 'crop_corners.dart';
import 'enhancer_mode.dart';
import 'grayscale_enhancer.dart';
import 'image_enhancer.dart';
import 'perspective_warper.dart';

/// Fuses perspective/Coons unwarp AND the selected enhancement into a SINGLE
/// [compute] isolate: one JPEG decode and one JPEG encode for the whole crop →
/// flat-page step. Previously the warper encoded a JPEG and the enhancer
/// immediately decoded it again — ~2 full codec passes of pure waste per page.
///
/// Routing matches [HybridWarper]: straight crops take the exact homography,
/// bent crops the Coons patch. Returns null for the full frame (no flat page)
/// and, per the never-throws contract, for ANY failure — the caller falls back
/// to enhancing the un-warped frame so a failed crop still de-shadows.
///
/// The [compute] isolate is guarded by [timeout] (default 12s — generous even
/// for the 12.5MP camera max). A wedged isolate cannot be killed from Dart, so
/// on timeout we simply detach and return `null`; that is the SAME null the
/// never-throws contract already yields on any failure, so [DartPageProcessor]
/// falls back to enhancing the un-warped frame exactly as before. [runner] is a
/// test-only seam to inject a never-completing isolate stand-in; production
/// leaves it null and runs the real [compute], byte-for-byte unchanged.
Future<Uint8List?> warpAndEnhance(
  Uint8List bytes,
  CropCorners corners,
  EnhancerMode mode, {
  Duration timeout = const Duration(seconds: 12),
  @visibleForTesting Future<Uint8List?> Function()? runner,
}) {
  if (corners == CropCorners.fullFrame) return Future.value(null);
  final run = runner ??
      () => compute(_warpEnhanceFn, _WarpEnhanceArgs(bytes, corners, mode));
  return withIsolateTimeout(run, timeout: timeout, onTimeout: () => null);
}

/// The enhancement filter that the fused pass applies for a given
/// [ImageEnhancer], so the cropped path can drive it by [EnhancerMode] without
/// threading a second parameter through the repository.
EnhancerMode enhancerModeOf(ImageEnhancer? enhancer) => switch (enhancer) {
  AutoEnhancer() => EnhancerMode.auto,
  ColorEnhancer() => EnhancerMode.color,
  GrayscaleEnhancer() => EnhancerMode.grayscale,
  _ => EnhancerMode.none,
};

class _WarpEnhanceArgs {
  final Uint8List bytes;
  final CropCorners corners;
  final EnhancerMode mode;
  const _WarpEnhanceArgs(this.bytes, this.corners, this.mode);
}

Uint8List? _warpEnhanceFn(_WarpEnhanceArgs a) {
  try {
    final decoded = img.decodeImage(a.bytes);
    if (decoded == null) return null;
    // Corners are normalized in the EXIF-applied display frame, so bake once
    // here; both the warp and the enhancement then operate on baked pixels.
    final src = img.bakeOrientation(decoded);
    final warped = a.corners.isStraight
        ? warpPerspectiveToImage(
            src,
            a.corners,
            const PerspectiveWarper().maxDimension,
          )
        : warpCoonsToImage(src, a.corners, const CoonsWarper().maxDimension);

    // Auto finishes at q95 (matches AutoEnhancer); the others at q92.
    final (processed, quality) = switch (a.mode) {
      EnhancerMode.auto => (autoEnhanceOriented(warped), 95),
      EnhancerMode.color => (colorEnhanceOriented(warped), 92),
      EnhancerMode.grayscale => (grayscaleEnhanceOriented(warped), 92),
      EnhancerMode.none => (warped, 92),
    };
    return Uint8List.fromList(img.encodeJpg(processed, quality: quality));
  } catch (_) {
    return null; // caller falls back to enhancing the un-warped frame
  }
}
