import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/folder.dart';
import 'package:mobile/features/library/tag.dart';

void main() {
  test('Folder has value equality', () {
    final a = Folder(id: 1, name: 'Receipts', createdAt: DateTime.utc(2026));
    final b = Folder(id: 1, name: 'Receipts', createdAt: DateTime.utc(2026));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('Tag has value equality', () {
    final a = Tag(id: 2, name: 'tax', createdAt: DateTime.utc(2026));
    final b = Tag(id: 2, name: 'tax', createdAt: DateTime.utc(2026));
    expect(a, b);
  });
}
