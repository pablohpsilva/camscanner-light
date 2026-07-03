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
    base = await Directory.systemTemp.createTemp('ftsrank');
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

  // Seeds a doc and sets each page's ocrText from [pageTexts] (index 0 → pos 1).
  Future<int> seed(String name, List<String?> pageTexts) async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: name, createdAt: now, modifiedAt: now));
    for (var i = 0; i < pageTexts.length; i++) {
      await db.into(db.pages).insert(PagesCompanion.insert(
            documentId: id,
            position: i + 1,
            relativeImagePath: 'documents/$id/page_${i + 1}.jpg',
            ocrText: Value(pageTexts[i]),
          ));
    }
    return id;
  }

  List<String> names(List<dynamic> r) =>
      r.map((s) => s.document.name as String).toList();

  test('multi-word query matches terms across different pages of one doc',
      () async {
    await seed('Report', ['ACME corporation header', null, 'final INVOICE total']);
    await seed('Decoy', ['acme only, nothing else here']);
    final r = await repo.searchDocuments('acme invoice');
    expect(names(r), ['Report']);
  });

  test('mid-word substring still matches (trigram parity with LIKE)', () async {
    await seed('Scans', ['these were all rescanned yesterday']);
    expect(names(await repo.searchDocuments('scan')), ['Scans']);
  });

  test('more/closer hits rank above an incidental single hit', () async {
    await seed('Weak', ['mentions invoice once, buried in prose about cats']);
    await seed('Strong', ['invoice invoice invoice invoice']);
    final r = await repo.searchDocuments('invoice');
    expect(names(r).first, 'Strong', reason: 'higher term frequency ranks first');
  });

  test('a name match sorts ahead of a text-only match', () async {
    await seed('Just some body text', ['this mentions mango somewhere']);
    await seed('Mango recipes', ['unrelated content']);
    final r = await repo.searchDocuments('mango');
    expect(names(r).first, 'Mango recipes');
  });

  test('operator-laden input never throws and still matches', () async {
    await seed('Doc', ['quarterly report data']);
    final r = await repo.searchDocuments('"report* (NEAR quarterly');
    expect(names(r), ['Doc']);
  });

  test('sub-3-char term falls back to LIKE and still matches substrings',
      () async {
    await seed('AB Co', ['the ab shorthand appears here']);
    expect(names(await repo.searchDocuments('ab')), ['AB Co']);
  });
}
