import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory base;
  setUp(() => base = Directory.systemTemp.createTempSync('b1fs'));
  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  test('relativeFor builds a stable relative path (no leading slash)', () {
    final store = DocumentFileStore(base);
    expect(store.relativeFor(7, 1), 'documents/7/page_1.jpg');
  });

  test('mergedRelativeFor keys the copy by source doc + position (P10)', () {
    final store = DocumentFileStore(base);
    // Freeze the collision-avoiding merge naming convention.
    expect(store.mergedRelativeFor(7, 3, 2), 'documents/7/page_m3_2.jpg');
    // Two different sources merged into the same target never collide.
    expect(
      store.mergedRelativeFor(7, 4, 2),
      isNot(store.mergedRelativeFor(7, 3, 2)),
    );
  });

  test('writeRelative creates dirs and writes bytes', () async {
    final store = DocumentFileStore(base);
    final rel = store.relativeFor(7, 1);
    await store.writeRelative(rel, [1, 2, 3]);
    final f = File(p.join(base.path, rel));
    expect(f.existsSync(), isTrue);
    expect(f.readAsBytesSync(), [1, 2, 3]);
  });

  test('absoluteFor resolves the SAME relative path under a CHANGED base '
      '(iOS container-GUID safety)', () async {
    final store = DocumentFileStore(base);
    final rel = store.relativeFor(7, 1);
    await store.writeRelative(rel, [9]);

    // Simulate the container moving: copy the tree to a new base, resolve there.
    final base2 = Directory.systemTemp.createTempSync('b1fs2');
    addTearDown(() => base2.deleteSync(recursive: true));
    final src = File(p.join(base.path, rel));
    final dst = File(p.join(base2.path, rel))
      ..parent.createSync(recursive: true);
    dst.writeAsBytesSync(src.readAsBytesSync());

    final store2 = DocumentFileStore(base2);
    expect(
      store2.absoluteFor(rel).existsSync(),
      isTrue,
      reason: 'relative path must resolve under the new base',
    );
  });

  test('deleteDocumentDir removes the per-document directory', () async {
    final store = DocumentFileStore(base);
    await store.writeRelative(store.relativeFor(7, 1), [1]);
    await store.deleteDocumentDir(7);
    expect(
      Directory(p.join(base.path, 'documents', '7')).existsSync(),
      isFalse,
    );
  });
}
