import 'dart:io';

import '../scan/captured_image.dart';
import 'crop_corners.dart';
import 'document.dart';
import 'document_summary.dart';
import 'image_enhancer.dart';
import 'page_image.dart';

/// The only persistence surface the widget layer knows (DIP). The Drift
/// implementation hides the DB, scrubber, file store, and clock.
abstract interface class DocumentRepository {
  /// Persists [capture] (EXIF-scrubbed) and creates a one-page document with the
  /// page's crop [corners] (defaults to full-frame). When [enhancer] is provided
  /// it is applied to the saved bytes after the warp (silent on failure).
  Future<Document> createFromCapture(
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  });

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

  /// Generates a PDF of [documentId] to on-device storage and returns the file.
  /// Throws [DocumentExportException] on any failure (e.g. a missing page file).
  Future<File> exportPdf(int documentId);

  /// Renames [documentId] to [newName] (trimmed) and bumps modifiedAt. Returns
  /// the updated document. Throws [DocumentRenameException] when the trimmed
  /// name is empty or no document with that id exists. The name stays on-device.
  Future<Document> rename(int documentId, String newName);

  /// Re-warps the page at [position] using [corners] and updates the stored
  /// flat image. If [corners] == [CropCorners.fullFrame], deletes the flat
  /// file (best-effort) and clears [flatRelativePath] in the DB. Throws
  /// [DocumentSaveException] when the page row does not exist. Rethrows
  /// [WarpException] or IO errors on warp/write failure (DB unchanged).
  Future<void> updatePageCorners(
      int documentId, int position, CropCorners corners);

  /// Appends a new page to [documentId] at position MAX(current)+1.
  /// Returns the 1-based position of the newly created page.
  /// Throws [DocumentSaveException] when [documentId] has no existing pages
  /// (a document without pages is an inconsistent state).
  Future<int> addPageToDocument(
    int documentId,
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  });

  /// Reassigns page positions for [documentId] according to [orderedPositions].
  ///
  /// [orderedPositions]: the original 1-based position values in their desired
  /// new order. Example: [2, 1] = swap two pages (former page 2 becomes first).
  ///
  /// Throws [DocumentSaveException] when [documentId] has no pages.
  Future<void> reorderPages(int documentId, List<int> orderedPositions);

  /// Deletes the page at [position] of [documentId]: removes its row, best-effort
  /// deletes its image and flat files, and renumbers the remaining pages so their
  /// positions stay contiguous (1..N-1). If it was the only page, the whole
  /// document (row + dir) is deleted.
  ///
  /// Returns the number of pages remaining (0 => the document was deleted).
  /// Throws [DocumentSaveException] when no page exists at ([documentId], [position]).
  Future<int> deletePage(int documentId, int position);

  /// Replaces the page at [position] of [documentId] in place with [capture]
  /// (EXIF-scrubbed), applying [corners] (default full-frame) and [enhancer]
  /// exactly as [addPageToDocument] does. Overwrites the page's stored image and
  /// flat derivative, updates its corners, and bumps `modifiedAt`. The page keeps
  /// its [position]. Throws [DocumentSaveException] when no page exists at
  /// ([documentId], [position]).
  Future<void> replacePage(
    int documentId,
    int position,
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  });
}

class DocumentSaveException implements Exception {
  final String message;
  const DocumentSaveException(this.message);
  @override
  String toString() => 'DocumentSaveException: $message';
}

class DocumentExportException implements Exception {
  final String message;
  const DocumentExportException(this.message);
  @override
  String toString() => 'DocumentExportException: $message';
}

class DocumentRenameException implements Exception {
  final String message;
  const DocumentRenameException(this.message);
  @override
  String toString() => 'DocumentRenameException: $message';
}
