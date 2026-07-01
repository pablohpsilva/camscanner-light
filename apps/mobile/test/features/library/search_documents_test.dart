import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'dart:io';

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('o5search');
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );
  });

  tearDown(() async {
    await db.close();
    if (await base.exists()) await base.delete(recursive: true);
  });

  // Seeds a document with [pageCount] pages; the first page carries [ocrText].
  Future<int> seedDoc(String name, {String? ocrText, int pageCount = 1}) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: name, createdAt: now, modifiedAt: now));
    for (var pos = 1; pos <= pageCount; pos++) {
      await db.into(db.pages).insert(PagesCompanion.insert(
            documentId: id,
            position: pos,
            relativeImagePath: 'documents/$id/page_$pos.jpg',
            ocrText: Value(pos == 1 ? ocrText : null),
          ));
    }
    return id;
  }

  test('matches by document name (case-insensitive)', () async {
    await seedDoc('Invoice March');
    await seedDoc('Grocery list');
    final results = await repo.searchDocuments('invoice');
    expect(results.map((s) => s.document.name), ['Invoice March']);
  });

  test('matches by a page OCR text even when the name does not', () async {
    await seedDoc('Untitled', ocrText: 'TOTAL DUE 42.00 USD');
    await seedDoc('Other');
    final results = await repo.searchDocuments('total due');
    expect(results.map((s) => s.document.name), ['Untitled']);
  });

  test('a document with two matching pages appears once', () async {
    final id = await seedDoc('Doc', pageCount: 2);
    // give BOTH pages the query text
    await (db.update(db.pages)..where((t) => t.documentId.equals(id)))
        .write(const PagesCompanion(ocrText: Value('SHARED KEYWORD')));
    final results = await repo.searchDocuments('keyword');
    expect(results.length, 1);
    expect(results.single.pageCount, 2); // counts ALL pages, not just matches
  });

  test('empty/whitespace query returns the full list', () async {
    await seedDoc('A');
    await seedDoc('B');
    final all = await repo.listDocumentSummaries();
    final blank = await repo.searchDocuments('   ');
    expect(blank.map((s) => s.document.id).toSet(),
        all.map((s) => s.document.id).toSet());
  });

  test('a non-matching query returns empty', () async {
    await seedDoc('Alpha');
    expect(await repo.searchDocuments('zzznope'), isEmpty);
  });
}
