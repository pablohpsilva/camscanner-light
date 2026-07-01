import 'crop_corners.dart';

/// One page's resolved image for the viewer. [imagePath] is the original
/// EXIF-scrubbed capture (absolute). [flatImagePath] is the perspective-
/// flattened derivative (absolute); null when corners are full-frame or
/// the warp was skipped. [displayPath] is the path consumers should use.
class PageImage {
  final int position;
  final String imagePath;
  final CropCorners corners;
  final String? flatImagePath;
  final String? ocrText;

  const PageImage({
    required this.position,
    required this.imagePath,
    this.corners = CropCorners.fullFrame,
    this.flatImagePath,
    this.ocrText,
  });

  /// Flat image when available; original otherwise.
  String get displayPath => flatImagePath ?? imagePath;
}
