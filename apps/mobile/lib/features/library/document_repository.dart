import '../scan/captured_image.dart';
import 'document.dart';
import 'document_summary.dart';
import 'page_image.dart';

/// The only persistence surface the widget layer knows (DIP). The Drift
/// implementation hides the DB, scrubber, file store, and clock.
abstract interface class DocumentRepository {
  /// Persists [capture] (EXIF-scrubbed) and creates a one-page document.
  /// Throws [DocumentSaveException] on any failure (the capture is not lost).
  Future<Document> createFromCapture(CapturedImage capture);

  /// All documents (newest first) with page count and first-page thumbnail path
  /// (absolute, resolved at read time; null when the document has no page).
  Future<List<DocumentSummary>> listDocumentSummaries();

  /// Pages of [documentId], position ascending, with ABSOLUTE image paths
  /// (resolved at read time). Empty when the document has no pages.
  Future<List<PageImage>> getDocumentPages(int documentId);

  /// Deletes [documentId], its pages, and its on-disk image files. Row-first:
  /// an authoritative DB delete (pages then document, one transaction), then a
  /// best-effort file cleanup. A non-existent id is a no-op.
  Future<void> deleteDocument(int documentId);
}

class DocumentSaveException implements Exception {
  final String message;
  const DocumentSaveException(this.message);
  @override
  String toString() => 'DocumentSaveException: $message';
}
