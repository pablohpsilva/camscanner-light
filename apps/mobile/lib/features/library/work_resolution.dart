/// Pure, dependency-free working-resolution decision helper.
///
/// Mirrors the downscale-cap logic in `native_page_processor.dart`'s
/// `_warpStraight`, but with no `opencv_dart`, `package:image`, or Flutter
/// deps so it runs under a plain `flutter test` (which cannot load libdartcv).
library;

/// The result of a working-resolution decision.
///
/// [scale] is `1.0` when no downscale is applied; otherwise `cap / longest`.
/// [targetW] / [targetH] are the resulting dimensions, always clamped `>= 2`.
class WorkResolution {
  final double scale;
  final int targetW;
  final int targetH;

  const WorkResolution(this.scale, this.targetW, this.targetH);
}

/// Compute the working-resolution scale + target dims from a source size and a
/// long-side [cap].
///
/// - When the longer of [srcW]/[srcH] is `<= cap`: no downscale — returns
///   `scale == 1.0` with the source dims unchanged.
/// - When the longer side is `> cap`: `scale = cap / longest`, and each target
///   dim is `(src * scale).round()`, clamped to `>= 2`.
WorkResolution computeWorkResolution(int srcW, int srcH, int cap) {
  final longest = srcW > srcH ? srcW : srcH;
  if (longest <= cap) {
    return WorkResolution(1.0, srcW, srcH);
  }
  final scale = cap / longest;
  var targetW = (srcW * scale).round();
  if (targetW < 2) targetW = 2;
  var targetH = (srcH * scale).round();
  if (targetH < 2) targetH = 2;
  return WorkResolution(scale, targetW, targetH);
}
