import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/tag_merge.dart';

void main() {
  test(
    'mergeTagIds unions existing and chosen tag ids without dropping any',
    () {
      final a = mergeTagIds({1, 2}, {4});
      expect(a, {1, 2, 4});
    },
  );

  test('mergeTagIds is idempotent when chosen overlaps existing', () {
    final result = mergeTagIds({1, 3}, {1, 4});
    expect(result, {1, 3, 4});
  });

  test('mergeTagIds with empty chosen returns existing unchanged', () {
    final result = mergeTagIds({1, 2, 3}, {});
    expect(result, {1, 2, 3});
  });

  test('mergeTagIds with empty existing returns chosen unchanged', () {
    final result = mergeTagIds({}, {5, 6});
    expect(result, {5, 6});
  });
}
