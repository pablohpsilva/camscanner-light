import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
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
    base = await Directory.systemTemp.createTemp('o4txt');
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

  Future<int> seedPage({String? ocrText}) async {
    final now = DateTime.now();
    final docId = await db.into(db.documents).insert(
        DocumentsCompanion.insert(name: 'My Report', createdAt: now, modifiedAt: now));
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: docId,
        position: 1,
        relativeImagePath: 'documents/$docId/page_1.jpg',
        ocrText: Value(ocrText)));
    return docId;
  }

  test('writes a temp .txt with the cached text and a sanitized name', () async {
    final docId = await seedPage(ocrText: 'HELLO WORLD');
    final file = await repo.exportRecognizedText(docId, 1);

    expect(await file.readAsString(), 'HELLO WORLD');
    expect(file.path, endsWith('My Report_page_1.txt'));
    // Temp, not under the documents dir.
    expect(file.path.contains(base.path), isFalse);
  });

  test('throws when the page has no recognized text', () async {
    final docId = await seedPage(ocrText: null);
    expect(() => repo.exportRecognizedText(docId, 1),
        throwsA(isA<DocumentExportException>()));
  });

  test('throws when the page row does not exist', () async {
    expect(() => repo.exportRecognizedText(999, 1),
        throwsA(isA<DocumentExportException>()));
  });
}
