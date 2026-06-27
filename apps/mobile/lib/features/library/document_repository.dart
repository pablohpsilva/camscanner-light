import '../scan/captured_image.dart';
import 'document.dart';

/// The only persistence surface the widget layer knows (DIP). The Drift
/// implementation hides the DB, scrubber, file store, and clock.
abstract interface class DocumentRepository {
  /// Persists [capture] (EXIF-scrubbed) and creates a one-page document.
  /// Throws [DocumentSaveException] on any failure (the capture is not lost).
  Future<Document> createFromCapture(CapturedImage capture);

  /// All documents, newest first.
  Future<List<Document>> listDocuments();
}

class DocumentSaveException implements Exception {
  final String message;
  const DocumentSaveException(this.message);
  @override
  String toString() => 'DocumentSaveException: $message';
}
