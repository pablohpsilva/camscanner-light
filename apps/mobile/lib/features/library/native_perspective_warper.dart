import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'crop_corners.dart';
import 'native_warp_geometry.dart';
import 'perspective_warper.dart' show kDefaultFlatMaxDimension;

/// Native (dartcv) perspective flatten — the isolate-side mirror of the Dart
/// `perspective_warper`, split out of the `NativePageProcessor` god-file (P08).
/// The output-size rule is the pure, host-tested [nativeWarpOutputSize]; this
/// function only builds the quads and runs the cv transform/warp. Math is moved
/// verbatim — device warp parity is unchanged.
///
/// Perspective-flatten a straight crop, output size = the longer of each pair
/// of opposite edges (same rule as the Dart warper), capped to
/// [kDefaultFlatMaxDimension]. Returns a new Mat owned by the caller.
cv.Mat warpStraight(cv.Mat src, CropCorners c) {
  final w = src.cols, h = src.rows;
  final (pxW, pxH) = nativeWarpOutputSize(c, w, h, kDefaultFlatMaxDimension);

  final srcQuad = cv.VecPoint2f.fromList([
    cv.Point2f(c.topLeft.dx * w, c.topLeft.dy * h),
    cv.Point2f(c.topRight.dx * w, c.topRight.dy * h),
    cv.Point2f(c.bottomRight.dx * w, c.bottomRight.dy * h),
    cv.Point2f(c.bottomLeft.dx * w, c.bottomLeft.dy * h),
  ]);
  final dstQuad = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(pxW.toDouble(), 0),
    cv.Point2f(pxW.toDouble(), pxH.toDouble()),
    cv.Point2f(0, pxH.toDouble()),
  ]);
  cv.Mat? m;
  try {
    m = cv.getPerspectiveTransform2f(srcQuad, dstQuad);
    return cv.warpPerspective(src, m, (pxW, pxH), flags: cv.INTER_LINEAR);
  } finally {
    srcQuad.dispose();
    dstQuad.dispose();
    m?.dispose();
  }
}
