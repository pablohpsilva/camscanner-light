import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves relative image paths against an injected base directory and owns
/// per-document file IO. The base dir is INJECTED (the composition root calls
/// `path_provider` once and passes it in) — never fetched internally, so host
/// unit tests can pass a temp dir.
class DocumentFileStore {
  final Directory baseDir;
  const DocumentFileStore(this.baseDir);

  String relativeFor(int docId, int position) =>
      'documents/$docId/page_$position.jpg';

  /// Collision-avoiding image path for a page copied INTO [docId] during a
  /// merge, keyed by its [sourceDocId]/[sourcePosition] so two merged sources
  /// can't clash. Keeps the merge naming convention in the store (P10 SAFE-05).
  String mergedRelativeFor(int docId, int sourceDocId, int sourcePosition) =>
      'documents/$docId/page_m${sourceDocId}_$sourcePosition.jpg';

  String flatRelativeFor(int docId, int position) =>
      'documents/$docId/page_${position}_flat.jpg';

  /// Derivative ("flat") path for the page whose image is at [relativeImagePath].
  /// Inserts `_flat` before the extension (`.../page_7.jpg` -> `.../page_7_flat.jpg`)
  /// so the flat is 1:1 with the page's own image file — stable under reorder,
  /// unlike a position-derived name. For a never-reordered page this equals
  /// flatRelativeFor(docId, position), so already-stored flats still resolve.
  String flatForImage(String relativeImagePath) =>
      '${p.withoutExtension(relativeImagePath)}_flat${p.extension(relativeImagePath)}';

  String pdfRelativeFor(int docId) => 'documents/$docId/export.pdf';

  File absoluteFor(String relativePath) =>
      File(p.join(baseDir.path, relativePath));

  Future<void> writeRelative(String relativePath, List<int> bytes) async {
    final f = absoluteFor(relativePath);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  Future<void> deleteDocumentDir(int docId) async {
    final dir = Directory(p.join(baseDir.path, 'documents', '$docId'));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
