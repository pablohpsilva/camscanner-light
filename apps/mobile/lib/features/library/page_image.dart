import 'crop_corners.dart';

/// One page's resolved image for the viewer. [imagePath] is ABSOLUTE (resolved
/// at read time via DocumentFileStore). [corners] is the page's crop quad
/// (full-frame when uncropped). Symmetric with DocumentSummary on the read side.
class PageImage {
  final int position;
  final String imagePath;
  final CropCorners corners;
  const PageImage({
    required this.position,
    required this.imagePath,
    this.corners = CropCorners.fullFrame,
  });
}
