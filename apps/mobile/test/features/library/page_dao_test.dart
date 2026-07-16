import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/page_dao.dart';
import 'package:mobile/features/library/enhancer_mode.dart';

void main() {
  late AppDatabase db;
  late Directory base;
  late DocumentFileStore store;
  late PageDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    base = Directory.systemTemp.createTempSync('pagedao');
    store = DocumentFileStore(base);
    dao = PageDao(db, store);
  });
  tearDown(() async {
    await db.close();
    base.deleteSync(recursive: true);
  });

  Future<int> newDoc() => db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          name: 'Doc',
          createdAt: DateTime.utc(2026, 1, 1),
          modifiedAt: DateTime.utc(2026, 1, 1),
        ),
      );

  Future<void> addPage(
    int docId,
    int position, {
    EnhancerMode mode = EnhancerMode.none,
    int rotation = 0,
    String? ocrText,
  }) => db
      .into(db.pages)
      .insert(
        PagesCompanion.insert(
          documentId: docId,
          position: position,
          relativeImagePath: store.relativeFor(docId, position),
          enhancerMode: Value(mode.index),
          rotationQuarterTurns: Value(rotation),
          ocrText: Value(ocrText),
        ),
      );

  group('requirePage', () {
    test('returns the row when the page exists', () async {
      final id = await newDoc();
      await addPage(id, 1);
      final page = await dao.requirePage(id, 1, 'op');
      expect(page.documentId, id);
      expect(page.position, 1);
    });

    test(
      'throws DocumentSaveException with the op prefix when missing',
      () async {
        final id = await newDoc();
        expect(
          () => dao.requirePage(id, 9, 'rotatePage'),
          throwsA(
            isA<DocumentSaveException>().having(
              (e) => e.message,
              'message',
              contains('rotatePage: no page'),
            ),
          ),
        );
      },
    );

    test('throws DocumentExportException when export is true', () async {
      final id = await newDoc();
      expect(
        () => dao.requirePage(id, 9, 'exportImage failed', export: true),
        throwsA(isA<DocumentExportException>()),
      );
    });
  });

  group('maxPositionPage', () {
    test('returns the highest-position row', () async {
      final id = await newDoc();
      await addPage(id, 1);
      await addPage(id, 2);
      await addPage(id, 3);
      expect((await dao.maxPositionPage(id))!.position, 3);
    });

    test('returns null when the document has no pages', () async {
      expect(await dao.maxPositionPage(await newDoc()), isNull);
    });
  });

  group('getDocumentPages', () {
    test(
      'maps rows to PageImage in position order with absolute paths',
      () async {
        final id = await newDoc();
        await addPage(id, 2, mode: EnhancerMode.color, rotation: 1);
        await addPage(id, 1, ocrText: 'hello');
        final pages = await dao.getDocumentPages(id);
        expect(pages.map((p) => p.position), [1, 2]);
        expect(
          pages.first.imagePath,
          store.absoluteFor(store.relativeFor(id, 1)).path,
        );
        expect(pages.first.ocrText, 'hello');
        expect(pages[1].enhancerMode, EnhancerMode.color);
        expect(pages[1].rotationQuarterTurns, 1);
        expect(pages.first.corners, CropCorners.fullFrame);
      },
    );

    test('returns empty for a document with no pages', () async {
      expect(await dao.getDocumentPages(await newDoc()), isEmpty);
    });
  });

  group('pageCount', () {
    test('counts pages of the document', () async {
      final id = await newDoc();
      await addPage(id, 1);
      await addPage(id, 2);
      expect(await dao.pageCount(id), 2);
    });

    test('is 0 for a document with no pages', () async {
      expect(await dao.pageCount(await newDoc()), 0);
    });
  });

  group('renumberAfterDelete', () {
    test(
      'decrements positions strictly greater than the deleted one',
      () async {
        final id = await newDoc();
        await addPage(id, 1);
        await addPage(id, 2);
        await addPage(id, 3);
        // Simulate deleting position 2, then renumber the survivors above it.
        await (db.delete(
          db.pages,
        )..where((t) => t.documentId.equals(id) & t.position.equals(2))).go();
        await dao.renumberAfterDelete(id, 2);
        final positions = (await dao.getDocumentPages(
          id,
        )).map((p) => p.position).toList();
        expect(positions, [1, 2]); // former page 3 became 2
      },
    );
  });
}
