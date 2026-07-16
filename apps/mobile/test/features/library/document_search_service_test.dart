import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/search/document_search_service.dart';

/// Records every SELECT statement drift runs, so a test can assert the SHAPE of
/// the first-page-thumbnail query (P12 PERF-01) — no full `SELECT * FROM pages`
/// scan.
class _SelectSpy extends QueryInterceptor {
  final statements = <String>[];
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runSelect(executor, statement, args);
  }
}

void main() {
  late AppDatabase db;
  late _SelectSpy spy;
  late Directory base;
  late DocumentFileStore store;
  late DocumentSearchService service;

  setUp(() {
    spy = _SelectSpy();
    db = AppDatabase(NativeDatabase.memory().interceptWith(spy));
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

    test(
      'thumbnail is the LOWEST-position page (multi-page precedence)',
      () async {
        final id = await newDoc('Doc', DateTime.utc(2026, 1, 1));
        await addPage(id, 2); // insert out of order to prove MIN(position) wins
        await addPage(id, 1, flatRel: 'documents/$id/page_1_flat.jpg');
        final s = (await service.listSummaries()).single;
        expect(
          s.thumbnailPath,
          store.absoluteFor('documents/$id/page_1_flat.jpg').path,
        );
      },
    );

    test('a document with no pages has a null thumbnail', () async {
      await newDoc('Empty', DateTime.utc(2026, 1, 1));
      expect((await service.listSummaries()).single.thumbnailPath, isNull);
    });

    test('PERF-01: the first-page query aggregates (MIN(position)), not a full '
        'pages scan', () async {
      final id = await newDoc('Doc', DateTime.utc(2026, 1, 1));
      await addPage(id, 1);
      await addPage(id, 2);
      await addPage(id, 3);
      spy.statements.clear();
      await service.listSummaries();
      final lower = spy.statements.map((s) => s.toLowerCase());
      expect(
        lower.any((s) => s.contains('min(position)')),
        isTrue,
        reason: 'first-page path must come from a MIN(position) aggregate',
      );
      // No unconditional full-table page scan just to find the first page.
      expect(
        lower.any(
          (s) =>
              s.contains('from "pages"') &&
              s.contains('order by') &&
              !s.contains('min('),
        ),
        isFalse,
        reason: 'must not SELECT every page row just to find the first',
      );
    });
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
