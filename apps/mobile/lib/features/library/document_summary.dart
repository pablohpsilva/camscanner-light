import 'document.dart';

/// Read model for the documents list: a [Document] plus its page count and the
/// absolute path to its first page's image (for the thumbnail). Built by the
/// repository at read time; [thumbnailPath] is already resolved to an ABSOLUTE
/// path (relative→absolute happens in the repository, fresh each launch) and is
/// null when the document has no page.
class DocumentSummary {
  final Document document;
  final int pageCount;
  final String? thumbnailPath;

  const DocumentSummary({
    required this.document,
    required this.pageCount,
    this.thumbnailPath,
  });
}
