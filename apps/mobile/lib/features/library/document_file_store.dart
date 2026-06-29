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
