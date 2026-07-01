import 'dart:typed_data';

import 'coons_warper.dart';
import 'crop_corners.dart';
import 'image_warper.dart';
import 'perspective_warper.dart';

/// Routes a crop to the right unwarp engine: no-op for the full frame, exact
/// homography for straight crops (no perspective regression), and the Coons
/// patch only when an edge is bent.
class HybridWarper implements ImageWarper {
  final ImageWarper perspective;
  final ImageWarper coons;
  const HybridWarper({
    this.perspective = const PerspectiveWarper(),
    this.coons = const CoonsWarper(),
  });

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) {
    if (corners == CropCorners.fullFrame) return Future.value(null);
    return corners.isStraight
        ? perspective.warp(bytes, corners)
        : coons.warp(bytes, corners);
  }
}
