import 'dart:typed_data';

import 'crop_corners.dart';
import 'image_warper.dart';

/// Perspective-flattening warper. Stub — full implementation in Task 5.
class PerspectiveWarper implements ImageWarper {
  const PerspectiveWarper();

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) async =>
      throw UnimplementedError('stub');
}
