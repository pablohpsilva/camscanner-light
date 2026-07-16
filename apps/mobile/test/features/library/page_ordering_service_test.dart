import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/page_dao.dart';
import 'package:mobile/features/library/page_ordering_service.dart';

void main() {
  late AppDatabase db;
  late Directory base;
  late DocumentFileStore store;
  late PageOrderingService service;
  // ignore: prefer_function_declarations_over_variables
  final clock = () => DateTime.utc(2026, 6, 27, 20, 0, 0);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    base = Directory.systemTemp.createTempSync('ordering');
    store = DocumentFileStore(base);
    service = PageOrderingService(
      db,
      store,
      PageDao(db, store),
      clock,
      SilentAppLogger(),
    );
  });
  tearDown(() async {
    await db.close();
    base.deleteSync(recursive: true);
  });

  Future<int> newDoc(String name) => db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          name: name,
          createdAt: clock(),
          modifiedAt: clock(),
        ),
      );

  Future<void> addPage(int docId, int pos) async {
    final rel = store.relativeFor(docId, pos);
    await store.writeRelative(rel, [pos]); // a real on-disk file to copy
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: docId,
            position: pos,
            relativeImagePath: rel,
          ),
        );
  }

  Future<List<int>> positions(int docId) async {
    final rows =
        await (db.select(db.pages)
              ..where((p) => p.documentId.equals(docId))
              ..orderBy([(p) => OrderingTerm.asc(p.position)]))
            .get();
    return rows.map((r) => r.position).toList();
  }

  group('deletePage', () {
    test('renumbers survivors and returns the remaining count', () async {
      final id = await newDoc('Doc');
      await addPage(id, 1);
      await addPage(id, 2);
      await addPage(id, 3);
      final remaining = await service.deletePage(id, 2);
      expect(remaining, 2);
      expect(await positions(id), [1, 2]);
    });

    test('deleting the only page removes the document', () async {
      final id = await newDoc('Doc');
      await addPage(id, 1);
      final remaining = await service.deletePage(id, 1);
      expect(remaining, 0);
      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(id))).getSingleOrNull();
      expect(doc, isNull);
    });
  });

  test('reorderPages applies the new order', () async {
    final id = await newDoc('Doc');
    await addPage(id, 1);
    await addPage(id, 2);
    await service.reorderPages(id, [2, 1]); // swap
    // Former page 2 is now position 1.
    final rows =
        await (db.select(db.pages)
              ..where((p) => p.documentId.equals(id))
              ..orderBy([(p) => OrderingTerm.asc(p.position)]))
            .get();
    expect(rows.first.relativeImagePath, store.relativeFor(id, 2));
  });

  test(
    'mergeInto appends source pages to target and deletes the source',
    () async {
      final target = await newDoc('Target');
      final source = await newDoc('Source');
      await addPage(target, 1);
      await addPage(source, 1);
      await addPage(source, 2);
      await service.mergeInto(target, source);
      expect(await positions(target), [1, 2, 3]);
      final src = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(source))).getSingleOrNull();
      expect(src, isNull, reason: 'source document removed');
    },
  );

  test('splitAfter moves trailing pages into a new document', () async {
    final id = await newDoc('Doc');
    await addPage(id, 1);
    await addPage(id, 2);
    await addPage(id, 3);
    final newDocResult = await service.splitAfter(id, 1);
    expect(await positions(id), [1], reason: 'source keeps 1..position');
    expect(await positions(newDocResult.id), [
      1,
      2,
    ], reason: 'moved pages renumber from 1');
    expect(newDocResult.name, 'Doc (split)');
  });
}
