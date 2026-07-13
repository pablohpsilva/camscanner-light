import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/tag.dart';

void main() {
  final doc = Document(
      id: 1, name: 'D', createdAt: DateTime.utc(2026), modifiedAt: DateTime.utc(2026));

  test('defaults: folderId null, tags empty', () {
    final s = DocumentSummary(document: doc, pageCount: 1);
    expect(s.folderId, isNull);
    expect(s.tags, isEmpty);
  });

  test('carries folderId and tags when provided', () {
    final s = DocumentSummary(
        document: doc, pageCount: 1, folderId: 7,
        tags: [Tag(id: 2, name: 'tax', createdAt: DateTime.utc(2026))]);
    expect(s.folderId, 7);
    expect(s.tags.single.name, 'tax');
  });
}
