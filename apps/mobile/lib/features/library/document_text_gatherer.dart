import 'document_repository.dart';

/// Gathers a whole document's recognized (OCR) text as one string, in page
/// order. The per-page text already lives on each [PageImage] (the same source
/// the FTS index concatenates), so this reads [DocumentRepository.getDocumentPages]
/// rather than duplicating any DB/FTS logic.
///
/// Pages are ordered by [PageImage.position]; pages with no usable text
/// (null / empty / whitespace-only) are skipped, and the remaining page texts
/// are joined with a blank line. Returns an empty string when the document has
/// no recognized text — the caller decides how to surface that (e.g. a "no
/// text" snackbar) rather than copying an empty clipboard.
class DocumentTextGatherer {
  final DocumentRepository repository;

  const DocumentTextGatherer({required this.repository});

  Future<String> gather(int documentId) async {
    final pages = await repository.getDocumentPages(documentId);
    final ordered = [...pages]
      ..sort((a, b) => a.position.compareTo(b.position));
    final texts = <String>[
      for (final page in ordered)
        if (page.ocrText != null && page.ocrText!.trim().isNotEmpty)
          page.ocrText!.trim(),
    ];
    return texts.join('\n\n');
  }
}
