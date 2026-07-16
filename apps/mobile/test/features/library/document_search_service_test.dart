import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/search/document_search_service.dart';

void main() {
  late AppDatabase db;
  late Directory base;
  late DocumentFileStore store;
  late DocumentSearchService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    base = Directory.systemTemp.createTempSync('search_svc');
    store = DocumentFileStore(base);
    service = DocumentSearchService(db, store);
  });
  tearDown(() async {
    await db.close();
    base.deleteSync(recursive: true);
  });

  Future<int> newDoc(String name, DateTime created) => db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          name: name,
          createdAt: created,
          modifiedAt: created,
        ),
      );

  Future<void> addPage(
    int docId,
    int pos, {
    String? ocrText,
    String? flatRel,
  }) => db
      .into(db.pages)
      .insert(
        PagesCompanion.insert(
          documentId: docId,
          position: pos,
          relativeImagePath: store.relativeFor(docId, pos),
          flatRelativePath: Value(flatRel),
          ocrText: Value(ocrText),
        ),
      );

  group('listSummaries', () {
    test('returns documents newest-first with page count', () async {
      final older = await newDoc('Older', DateTime.utc(2026, 1, 1));
      final newer = await newDoc('Newer', DateTime.utc(2026, 2, 1));
      await addPage(older, 1);
      await addPage(newer, 1);
      await addPage(newer, 2);
      final list = await service.listSummaries();
      expect(list.map((s) => s.document.id), [newer, older]);
      expect(list.first.pageCount, 2);
      expect(list.last.pageCount, 1);
    });

    test(
      'thumbnail is the first page flat when present, else the image',
      () async {
        final id = await newDoc('Doc', DateTime.utc(2026, 1, 1));
        await addPage(id, 1, flatRel: 'documents/$id/page_1_flat.jpg');
        final s = (await service.listSummaries()).single;
        expect(
          s.thumbnailPath,
          store.absoluteFor('documents/$id/page_1_flat.jpg').path,
        );
      },
    );
  });

  group('search', () {
    test('a blank query returns the full list', () async {
      await newDoc('A', DateTime.utc(2026, 1, 1));
      await newDoc('B', DateTime.utc(2026, 2, 1));
      expect((await service.search('   ')).length, 2);
    });

    test(
      'LIKE fallback (short query) matches document name substrings',
      () async {
        await newDoc('Invoice', DateTime.utc(2026, 1, 1));
        await newDoc('Receipt', DateTime.utc(2026, 2, 1));
        final hits = await service.search('in'); // 2 chars -> LIKE
        expect(hits.map((s) => s.document.name), ['Invoice']);
      },
    );

    test('LIKE fallback matches page OCR-text substrings', () async {
      final id = await newDoc('Doc', DateTime.utc(2026, 1, 1));
      await addPage(id, 1, ocrText: 'total abcd');
      final hits = await service.search('ab'); // 2 chars -> LIKE
      expect(hits.map((s) => s.document.id), [id]);
    });

    test('an unmatched query returns empty', () async {
      await newDoc('Doc', DateTime.utc(2026, 1, 1));
      expect(await service.search('zz'), isEmpty);
    });
  });
}
