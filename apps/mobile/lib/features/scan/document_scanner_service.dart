import 'captured_image.dart';

/// Launches the platform document scanner (Android ML Kit / iOS VisionKit) and
/// returns the captured, already-cropped page images.
abstract interface class DocumentScannerService {
  /// Returns the scanned page images in order, or an empty list if the user
  /// cancelled or scanning failed. NEVER throws.
  ///
  /// [pageLimit] caps the number of pages (honoured on Android; iOS VisionKit
  /// is inherently multi-page and ignores it). Null means "no practical cap".
  Future<List<CapturedImage>> scan({int? pageLimit});
}
