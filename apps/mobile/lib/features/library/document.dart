/// Plain domain model for a saved document (decoupled from Drift row types).
class Document {
  final int id;
  final String name;
  final DateTime createdAt; // UTC
  final DateTime modifiedAt; // UTC
  const Document({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
  });
}

/// Plain domain model for one page. [relativeImagePath] is relative to the app
/// documents dir (resolved at read time).
class Page {
  final int id;
  final int documentId;
  final int position;
  final String relativeImagePath;
  const Page({
    required this.id,
    required this.documentId,
    required this.position,
    required this.relativeImagePath,
  });
}
