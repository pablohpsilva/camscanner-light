import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_sort.dart';
import 'package:mobile/features/library/document_summary.dart';

DocumentSummary summary(
  int id,
  String name, {
  DateTime? created,
  DateTime? modified,
}) {
  final c = created ?? DateTime.utc(2026, 1, 1);
  return DocumentSummary(
    document: Document(
      id: id,
      name: name,
      createdAt: c,
      modifiedAt: modified ?? c,
    ),
    pageCount: 1,
    thumbnailPath: '/nonexistent/thumb-$id.jpg',
  );
}

List<String> names(List<DocumentSummary> docs) =>
    docs.map((d) => d.document.name).toList();

void main() {
  group('sortDocuments — name', () {
    final docs = [
      summary(1, 'Banana', created: DateTime.utc(2026, 1, 3)),
      summary(2, 'apple', created: DateTime.utc(2026, 1, 2)),
      summary(3, 'banana', created: DateTime.utc(2026, 1, 1)),
    ];

    test('ascending is case-insensitive (apple, Banana, banana)', () {
      final out = sortDocuments(
        docs,
        const DocumentSort(SortCriterion.name, SortDirection.asc),
      );
      expect(names(out), ['apple', 'Banana', 'banana']);
    });

    test('descending is case-insensitive (banana, Banana, apple)', () {
      // 'Banana' and 'banana' tie case-insensitively -> tie-break by createdAt
      // DESC: id1 (Jan 3) before id3 (Jan 1). So Banana(id1) before banana(id3).
      final out = sortDocuments(
        docs,
        const DocumentSort(SortCriterion.name, SortDirection.desc),
      );
      expect(names(out), ['Banana', 'banana', 'apple']);
    });
  });

  group('sortDocuments — created', () {
    final docs = [
      summary(1, 'a', created: DateTime.utc(2026, 1, 1)),
      summary(2, 'b', created: DateTime.utc(2026, 1, 3)),
      summary(3, 'c', created: DateTime.utc(2026, 1, 2)),
    ];
    test('descending = newest first', () {
      final out = sortDocuments(
        docs,
        const DocumentSort(SortCriterion.created, SortDirection.desc),
      );
      expect(names(out), ['b', 'c', 'a']);
    });
    test('ascending = oldest first', () {
      final out = sortDocuments(
        docs,
        const DocumentSort(SortCriterion.created, SortDirection.asc),
      );
      expect(names(out), ['a', 'c', 'b']);
    });
  });

  group('sortDocuments — modified', () {
    final docs = [
      summary(
        1,
        'a',
        created: DateTime.utc(2026, 1, 1),
        modified: DateTime.utc(2026, 2, 1),
      ),
      summary(
        2,
        'b',
        created: DateTime.utc(2026, 1, 1),
        modified: DateTime.utc(2026, 2, 3),
      ),
      summary(
        3,
        'c',
        created: DateTime.utc(2026, 1, 1),
        modified: DateTime.utc(2026, 2, 2),
      ),
    ];
    test('descending = newest-edited first', () {
      final out = sortDocuments(
        docs,
        const DocumentSort(SortCriterion.modified, SortDirection.desc),
      );
      expect(names(out), ['b', 'c', 'a']);
    });
  });

  group('sortDocuments — purity & determinism', () {
    test('does not mutate the input list', () {
      final input = [
        summary(1, 'b', created: DateTime.utc(2026, 1, 1)),
        summary(2, 'a', created: DateTime.utc(2026, 1, 2)),
      ];
      final before = names(input);
      sortDocuments(
        input,
        const DocumentSort(SortCriterion.name, SortDirection.asc),
      );
      expect(names(input), before, reason: 'input order must be unchanged');
    });

    test('accepts an unmodifiable list (operates on a copy)', () {
      final input = List<DocumentSummary>.unmodifiable([
        summary(1, 'b'),
        summary(2, 'a'),
      ]);
      // Must not throw (sort runs on a copy, never the unmodifiable original).
      final out = sortDocuments(
        input,
        const DocumentSort(SortCriterion.name, SortDirection.asc),
      );
      expect(names(out), ['a', 'b']);
    });

    test('tie-break: equal name -> newest createdAt first', () {
      final docs = [
        summary(1, 'Same', created: DateTime.utc(2026, 1, 1)),
        summary(2, 'Same', created: DateTime.utc(2026, 1, 5)),
      ];
      final out = sortDocuments(
        docs,
        const DocumentSort(SortCriterion.name, SortDirection.asc),
      );
      expect(out.map((d) => d.document.id).toList(), [2, 1]);
    });

    test('tie-break: equal name + equal createdAt -> lower id first', () {
      final t = DateTime.utc(2026, 1, 1);
      final docs = [
        summary(2, 'Same', created: t),
        summary(1, 'Same', created: t),
      ];
      final out = sortDocuments(
        docs,
        const DocumentSort(SortCriterion.name, SortDirection.asc),
      );
      expect(out.map((d) => d.document.id).toList(), [1, 2]);
    });

    test('handles empty and single-element lists', () {
      expect(sortDocuments(const [], DocumentSort.initial), isEmpty);
      final one = [summary(1, 'only')];
      expect(names(sortDocuments(one, DocumentSort.initial)), ['only']);
    });
  });

  group('nextSort', () {
    test('switching to an inactive criterion uses its default direction', () {
      const current = DocumentSort(SortCriterion.created, SortDirection.desc);
      expect(
        nextSort(current, SortCriterion.name),
        const DocumentSort(SortCriterion.name, SortDirection.asc),
      );
      expect(
        nextSort(current, SortCriterion.modified),
        const DocumentSort(SortCriterion.modified, SortDirection.desc),
      );
    });

    test('switching to created uses desc by default', () {
      const current = DocumentSort(SortCriterion.name, SortDirection.asc);
      expect(
        nextSort(current, SortCriterion.created),
        const DocumentSort(SortCriterion.created, SortDirection.desc),
      );
    });

    test('tapping the active criterion flips direction', () {
      const desc = DocumentSort(SortCriterion.created, SortDirection.desc);
      final asc = nextSort(desc, SortCriterion.created);
      expect(asc, const DocumentSort(SortCriterion.created, SortDirection.asc));
      expect(
        nextSort(asc, SortCriterion.created),
        const DocumentSort(SortCriterion.created, SortDirection.desc),
      );
    });
  });

  test('DocumentSort value equality', () {
    expect(
      const DocumentSort(SortCriterion.name, SortDirection.asc),
      const DocumentSort(SortCriterion.name, SortDirection.asc),
    );
    expect(
      const DocumentSort(SortCriterion.name, SortDirection.asc),
      isNot(const DocumentSort(SortCriterion.name, SortDirection.desc)),
    );
    expect(
      DocumentSort.initial,
      const DocumentSort(SortCriterion.created, SortDirection.desc),
    );
  });
}
